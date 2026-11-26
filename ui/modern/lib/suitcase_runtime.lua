local Runtime = {}

local STEP_DELAY, FINAL_DELAY = 0.12, 0.32
local MODIFIER_TIMEOUT = 1.5
local QUANTITY_WINDOW = "QuantityWnd"

local blockedWindows = {
  {"CastingWindow", "Finish casting first."},
  {"QuantityWnd", "Close the quantity dialog first."},
  {"ConfirmationDialogBox", "Resolve the open confirmation first."},
  {"TradeWnd", "Finish trading first."},
  {"GiveWnd", "Finish the hand-in first."},
  {"LootWnd", "Close the loot window first."},
  {"MerchantWnd", "Close the merchant first."},
  {"BankWnd", "Close the bank first."},
  {"BigBankWnd", "Close the bank first."},
  {"WorldContainer", "Close the tradeskill container first."},
  {"BazaarConfirmationWnd", "Resolve the open purchase first."},
  {"RespawnWnd", "Finish respawning first."},
}

local function sameItem(expected, actual, exact)
  if not expected or not actual then return not expected and not actual end
  if expected.id ~= actual.id or (expected.count or 1) ~= (actual.count or 1) then return false end
  if expected.charges ~= nil and actual.charges ~= nil and expected.charges ~= actual.charges then return false end
  if expected.configuration and (exact or actual.configuration) and expected.configuration ~= actual.configuration then
    return false
  end
  local serial = expected.serial
  -- Hailstone exposes serials in AllItems but Preview 02's cursor Item omits them.
  if exact and type(serial) == "string" and serial ~= "" and not serial:match("^0+$") then
    return serial == actual.serial
  end
  return true
end

local function placeKey(slot, sub)
  return sub and sub >= 0 and ("i:" .. slot .. ":" .. sub) or ("i:" .. slot)
end

local function samePlayer(first, second)
  return first and second and first.name == second.name and first.zone_id == second.zone_id
    and first.spawn_id == second.spawn_id
end

function Runtime.new(api, ui, owner)
  local inventory, windows = api.inventory, api.windows
  local instance, job, cached = {}, nil, nil
  local result = {running = false, done = 0, total = 0}

  local function ownerCall(name, ...)
    local bridge = type(owner) == "function" and owner() or owner
    local call = bridge and bridge[name]
    if not call then return nil end
    local ok, value = pcall(call, ...)
    if ok then return value end
  end

  function instance.snapshot(refresh)
    if not api.session.InGame() or not inventory.AllItems then return nil end
    local character = api.character.Name()
    local revision = inventory.ItemsRevision()
    if not refresh and cached and cached.character == character and cached.revision == revision then return cached end

    local rows, occupied, places, worn, carried = {}, {}, {}, {}, {}
    local wearables, positions = {}, {}
    local firstBag, lastBag = inventory.FirstBagSlot or 23, inventory.LastBagSlot or 32
    local _, capacity = inventory.InventorySpace()
    local generalSlots = capacity or (lastBag - firstBag + 1)
    for _, row in ipairs(inventory.AllItems() or {}) do
      if row.where == "worn" or row.where == "carried" then
        row.sub = row.sub or -1
        row.place = row.place or placeKey(row.slot, row.sub)
        rows[#rows + 1], occupied[row.place] = row, row
        if row.where == "worn" or (row.item.equipSlots or 0) ~= 0 then
          positions[#positions + 1], wearables[#wearables + 1] = {slot = row.slot, sub = row.sub}, row.item
        end
        if row.where == "worn" then
          worn[row.slot] = row.item
        else
          carried[#carried + 1] = row
          if capacity and row.sub < 0 and (row.item.bagSlots or 0) > 0 then
            generalSlots = generalSlots - row.item.bagSlots + 1
          end
        end
      end
    end

    local configurations = #positions > 0 and ownerCall("item_configurations", positions)
    if type(configurations) == "table" then
      for index, item in ipairs(wearables) do
        local configuration = configurations[index]
        if type(configuration) == "string" and configuration ~= "" then item.configuration = configuration end
      end
    end

    local function recordPlace(slot, sub, bag, where)
      local key = placeKey(slot, sub)
      local row = occupied[key]
      places[key] = {slot = slot, sub = sub, place = key, bag = bag, where = where, item = row and row.item}
    end

    for slot = 0, inventory.LastWornSlot or 22 do recordPlace(slot, -1, nil, "worn") end
    for slot = firstBag, math.min(lastBag, firstBag + generalSlots - 1) do
      local top = occupied[placeKey(slot)]
      local bag = top and top.item
      recordPlace(slot, -1, nil, "carried")
      for sub = 0, (bag and bag.bagSlots or 0) - 1 do recordPlace(slot, sub, bag, "carried") end
    end
    cached = {character = character, revision = revision, rows = rows, places = places,
      worn = worn, carried = carried, cursor = inventory.Item(inventory.CursorSlot or 33),
      dualWield = ownerCall("dual_wield")}
    return cached
  end

  local function cursorItem()
    return inventory.Item(inventory.CursorSlot or 33)
  end

  local function blockReason(player)
    if not player or not player.in_zone or not api.session.InGame() then return "Wait until you are in the zone." end
    if player.cur_hp and player.cur_hp <= 0 then return "You must be alive to swap sets." end
    if player.casting_spell_id and player.casting_spell_id ~= 0 then return "Finish casting first." end
    if api.trade and api.trade.State and api.trade.State() then return "Finish trading first." end
    if inventory.ItemJob and inventory.ItemJob() ~= nil then return "Wait for the other inventory action to finish." end
    if api.cursor and ((api.cursor.HoldingButton and api.cursor.HoldingButton()) or
        (api.cursor.Coin and api.cursor.Coin() ~= nil)) then
      return "Clear your cursor first."
    end
    for _, blocked in ipairs(blockedWindows) do
      local open = ownerCall("window_state", blocked[1])
      if open == nil and blocked[1] == QUANTITY_WINDOW then open = windows.Shown(QUANTITY_WINDOW) end
      if open then return blocked[2] end
    end
  end

  local function finish(message, failed)
    result = {running = false, done = job.done, total = #job.steps, message = message, error = failed or false}
    job = nil
    ownerCall("report_result", message)
  end

  local function stop(reason)
    local held = api.session.InGame() and cursorItem()
    local message = "Swap stopped after " .. job.done .. " of " .. #job.steps .. " moves. " .. reason
    if held then message = message .. " Cursor holds " .. (held.name or "an item") .. "." end
    finish(message, true)
  end

  function instance.status()
    if not job then return result end
    return {running = true, done = job.done, total = #job.steps, paused = job.waitModifier ~= nil,
      message = job.waitModifier and "Release Ctrl or Shift to continue." or "Swapping equipment…"}
  end

  function instance.cancel(reason)
    if job then stop(reason or "Canceled.") end
  end

  function instance.reset()
    job, cached = nil, nil
    result = {running = false, done = 0, total = 0}
  end

  function instance.start(plan, name)
    if job then return false, "A swap is already in progress." end
    local player = ownerCall("player_state")
    local why = blockReason(player)
    if why then return false, why end
    if cursorItem() then return false, "Clear your cursor first." end
    if not plan or plan.blocked or plan.problem or not plan.steps or #plan.steps == 0 then
      return false, plan and plan.problem or "There are no moves to perform."
    end
    local snapshot = instance.snapshot(true)
    if not snapshot then return false, "Inventory is unavailable." end
    local expected = {}
    for _, step in ipairs(plan.steps) do
      local location = snapshot.places[step.place]
      if not location then return false, "An inventory slot is no longer available." end
      if not expected[step.place] then expected[step.place] = {item = step.before, bag = location.bag} end
    end
    for slot, detail in pairs(plan.slots or {}) do
      local place = placeKey(slot)
      if detail.target ~= nil and not expected[place] then expected[place] = {item = detail.current} end
    end
    job = {steps = plan.steps, player = player, expected = expected, done = 0, nextAt = ui.GetTime(), name = name}
    return true
  end

  local function acceptWholeStack(step)
    -- ClickSlot opens QuantityWnd for a stack with no modifiers. Accept only the dialog
    -- opened by this click, after matching its minimum, maximum, and selected amount.
    if not windows.Shown(QUANTITY_WINDOW) then return false end
    local _, _, value, count = windows.ChildState(QUANTITY_WINDOW, "QTYW_Slider")
    local text = windows.Text(QUANTITY_WINDOW, "QTYW_SliderInput")
    local amount = tonumber(text)
    local expected = step.before.count
    return value == expected and count == expected + 1 and amount == expected
      and windows.Button(QUANTITY_WINDOW, "QTYW_Accept_Button") == true
  end

  local function click(step)
    if inventory.ClickSlot(step.slot, step.sub, "left") ~= true then return false end
    if not step.wholeStack then return true end
    return acceptWholeStack(step)
  end

  function instance.pulse()
    if not job then return end
    local now = ui.GetTime()
    if now < job.nextAt then return end
    local player = ownerCall("player_state")
    if not samePlayer(job.player, player) then return stop("Your zone or character changed.") end
    local why = blockReason(player)
    if why then return stop(why) end

    local pending = job.pending
    if pending then job.expected[pending.place].item = pending.after end
    local snapshot = instance.snapshot()
    if not snapshot then return stop("Inventory is unavailable.") end
    for place, expected in pairs(job.expected) do
      local actual = snapshot.places[place]
      if not actual or not sameItem(expected.item, actual.item, true) or not sameItem(expected.bag, actual.bag, true) then
        return stop("The inventory no longer matches the swap plan.")
      end
    end
    local held = cursorItem()
    if pending then
      if not sameItem(pending.cursorAfter, held, false) then return stop("The cursor item changed unexpectedly.") end
      job.done, job.pending = job.done + 1, nil
    end
    local step = job.steps[job.done + 1]
    if not step then
      if held then return stop("The cursor was expected to be empty.") end
      return finish(job.name and ("Equipped " .. job.name .. ".") or "Equipment set applied.")
    end
    if not sameItem(step.cursorBefore, held, false) then return stop("The cursor item changed unexpectedly.") end

    local io = ui.GetIO()
    if io.shift or io.ctrl then
      job.waitModifier = job.waitModifier or now
      if now - job.waitModifier >= MODIFIER_TIMEOUT then return stop("Ctrl or Shift is held down.") end
      return
    end
    job.waitModifier = nil

    if inventory.HasSlot and not inventory.HasSlot(step.slot, step.sub) then
      return stop("An inventory slot is no longer available.")
    end
    if step.kind == "stow" and inventory.CanPlace and not inventory.CanPlace(step.place) then
      return stop("The cursor item no longer fits its planned bag slot.")
    end
    local ok, clicked = pcall(click, step)
    if not ok then return stop("Hailstone did not allow this inventory action.") end
    if not clicked then return stop("Hailstone could not complete this inventory action.") end
    job.pending = step
    job.nextAt = now + (job.done + 1 == #job.steps and FINAL_DELAY or STEP_DELAY)
  end

  return instance
end

return Runtime
