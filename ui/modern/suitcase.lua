local API = hs.UI
local hud = dofile("lib/hud.lua")
local T = hud.T
local Plan = dofile("lib/suitcase_plan.lua")
local Sets = dofile("lib/suitcase_sets.lua")
local Runtime = dofile("lib/suitcase_runtime.lua")
local C = T.color

local ARMOR = {2, 3, 6, 7, 17, 9, 12, 18, 19}
local ACCESSORIES = {0, 1, 4, 5, 8, 10, 15, 16, 20}
local WEAPONS = {13, 14, 11, 22, 21}
local NAMES = {[0] = "Charm", "Ear 1", "Head", "Face", "Ear 2", "Neck", "Shoulders", "Arms", "Back", "Wrist 1",
  "Wrist 2", "Range", "Hands", "Primary", "Secondary", "Ring 1", "Ring 2", "Chest", "Legs", "Feet",
  "Waist", "Power", "Ammo"}

local owner, key, profile, snapshot, previews
local opened, inspected, form, name, editing = false, 2, nil, "", false
local message, messageError, invalidFile, nextPoll = nil, false, false, 0
local runtime = Runtime.new(API, ui, {
  player_state = function() return owner and owner.player_state() end,
  window_state = function(window) return owner and owner.window_state(window) end,
  item_configurations = function(places) return owner and owner.item_configurations(places) end,
  report_result = function(text) if owner then owner.report_result(text) end end,
})

local function notice(text, isError)
  message, messageError = text, isError == true
end

local function persist(nextProfile)
  if invalidFile or not owner.save_profile(key, nextProfile) then
    notice("Could not save this character's sets.", true)
    return false
  end
  profile, previews = nextProfile, nil
  return true
end

local function worn(slot)
  for _, row in ipairs(snapshot and snapshot.rows or {}) do
    if row.where == "worn" and row.slot == slot then return row.item end
  end
end

local function capture()
  local targets = {}
  for slot = 0, 22 do targets[slot] = false end
  for _, row in ipairs(snapshot.rows) do
    if row.where == "worn" and NAMES[row.slot] then targets[row.slot] = Plan.capture(row.item) or false end
  end
  return targets
end

local function preview(set)
  if not snapshot then return nil end
  previews = previews or {}
  if not previews[set.id] then previews[set.id] = Plan.plan(snapshot, set.targets) end
  return previews[set.id]
end

local function selectSet(set)
  profile.selected, inspected, form, editing = set.id, 2, nil, false
  notice(nil)
end

local function equip(set, byCommand)
  if runtime.status().running then
    if byCommand then owner.report_result("A swap is already in progress.") end
    return
  end
  selectSet(set)
  local current = runtime.snapshot()
  local plan = current and Plan.plan(current, set.targets)
  local why
  if not plan then why = "Inventory is unavailable."
  elseif plan.blocked then why = plan.problem or "This set cannot be equipped."
  elseif plan.changes == 0 then why = set.name .. " is already equipped."
  else
    local ok
    ok, why = runtime.start(plan, set.name)
    if ok then
      notice("Equipping " .. set.name .. "…")
      nextPoll = 0
      return
    end
    why = why or "The swap could not start."
  end
  notice(why, not plan or plan.blocked or plan.changes ~= 0)
  if byCommand then owner.report_result(why) end
end

local function changeSlot(slot, target)
  local selected, index = Sets.selected(profile)
  if not selected then return end
  local nextProfile, changed = Sets.copy(profile), Sets.change(selected)
  changed.targets[slot] = target
  nextProfile.sets[index] = changed
  if persist(nextProfile) then notice("Set updated.") end
end

local function runForm()
  local nextProfile = Sets.copy(profile)
  local selected, index = Sets.selected(profile)
  if form == "delete" then
    table.remove(nextProfile.sets, index)
    local nextSet = nextProfile.sets[math.min(index, #nextProfile.sets)]
    nextProfile.selected = nextSet and nextSet.id
    if persist(nextProfile) then form = nil; notice("Set deleted.") end
    return
  end
  local clean = Sets.name(name)
  if not clean then return notice("Use a name up to 48 bytes, without quotes or semicolons.", true) end
  local duplicate = Sets.find(profile, clean)
  if duplicate and (form ~= "rename" or duplicate.id ~= selected.id) then return notice("That set name is already used.", true) end
  if form == "rename" then
    local changed = Sets.change(selected)
    changed.name = clean
    nextProfile.sets[index] = changed
  else
    snapshot = runtime.snapshot()
    if not snapshot then return notice("Inventory is unavailable.", true) end
    local id = nextProfile.next_id
    nextProfile.sets[#nextProfile.sets + 1] = {id = id, name = clean, targets = capture()}
    nextProfile.next_id, nextProfile.selected = id + 1, id
  end
  if persist(nextProfile) then form = nil; notice("Saved " .. clean .. ".") end
end

local function request(query)
  if query == "" then opened = true; return end
  local set = Sets.find(profile, query)
  if not set then owner.report_result("No set named " .. query .. "."); return end
  equip(set, true)
end

local function poll(now)
  if now < nextPoll then return end
  nextPoll = now + 0.15
  local context = owner.profile_state(key)
  local active = context and context.key
  if active ~= key then
    if runtime.status().running then runtime.cancel("Your character or zone changed.") end
    runtime.reset()
    key, profile = active, active and Sets.read(context.data)
    invalidFile = context and context.invalid or false
    opened, form, inspected, editing = false, nil, 2, false
    snapshot, previews = nil, nil
    notice(invalidFile and "Could not read this character's saved sets." or nil, invalidFile)
  end
  if not key then return end
  if not runtime.status().running then
    local current = runtime.snapshot()
    if not current or not snapshot or current.revision ~= snapshot.revision then previews = nil end
    snapshot = current
  end
  for _, query in ipairs(owner.take_requests(key) or {}) do request(query) end
end

local function paint(x, y, w, h, c, alpha, radius)
  ui.DrawRectFilled(x, y, x + w, y + h, c[1], c[2], c[3], alpha or c[4] or 1, radius or 0)
end

local function edge(x, y, w, h, c, alpha, radius)
  ui.DrawRect(x, y, x + w, y + h, c[1], c[2], c[3], alpha or c[4] or 1, radius or 0, 1)
end

local function text(x, y, value, width, color, font, align)
  if width <= 0 then return end
  local at = align == "center" and x + width / 2 or x
  T.Text(at, y, T.Fit(value, width, font), color, font, align)
end

local function blank(x, y, w, h)
  ui.SetCursorScreenPos(x, y)
  ui.Dummy(w, h)
end

local function problem(row)
  return row and (row.status == "missing" or row.status == "ambiguous" or row.status == "blocked")
end

local function gearIcon(x, y, size, row, s)
  local saved = row and row.target
  local item = type(saved) == "table" and saved or nil
  local red = problem(row)
  local tex, u0, v0, u1, v1
  if item and item.icon and item.icon > 0 then tex, u0, v0, u1, v1 = API.assets.ItemIcon(item.icon) end
  T.Icon(x, y, size, s, not red and tex or nil, u0, v0, u1, v1, red and C.danger or nil, {radius = 4})
  if red and tex then
    local inset = 1.5 * s
    ui.DrawImage(tex, x + inset, y + inset, x + size - inset, y + size - inset, u0, v0, u1, v1, 1, 0.38, 0.42, 1)
  end
end

local function itemName(row)
  if not row or row.target == nil then return "Leave unchanged" end
  if row.target == false then return "Empty slot" end
  return row.target.name or ("Item #" .. row.target.id)
end

local function location(row)
  if not row or row.status == "ignored" then return "Ignored" end
  if row.status == "empty" then return "Already empty" end
  if row.status == "equipped" then return "Equipped" end
  if row.status == "missing" then return "Missing from bags" end
  if row.status == "ambiguous" then return "More than one matching item" end
  if row.status == "blocked" then return row.problem or "Blocked" end
  if row.target == false then return "Stow worn item" end
  local source = row.source
  if not source then return "Carried" end
  if source.where == "worn" then return "Worn in " .. (NAMES[source.slot] or "another slot") end
  return source.sub and source.sub >= 0 and string.format("Bag %d, slot %d", source.slot - 22, source.sub + 1)
    or "Inventory slot " .. (source.slot - 22)
end

local function itemHelp(row, label)
  if not ui.IsItemHovered() then return end
  local target = row and row.target
  if type(target) == "table" then
    if ui.IsItemClicked(ui.Mouse.Right) then
      if ui.GetIO().alt then T.TakeAltRightClick() else T.TakeRightClick() end
      -- Re-resolve against the current inventory so a moved item never inspects the contents of its old slot.
      local current = runtime.snapshot(true)
      if not current then return notice("Inventory is unavailable.", true) end
      local source = Plan.resolve(current.rows, target)
      local ok, openedItem
      if source then
        ok, openedItem = pcall(API.inventory.ClickSlot, source.slot, source.sub, "rightheld")
      else
        ok, openedItem = pcall(owner.inspect_saved, target.id, target.configuration)
      end
      if not ok or not openedItem then notice("Hailstone could not inspect this item.", true) end
      return
    end
    label = label .. (row.source and "\nRight-click to inspect" or "\nRight-click for saved item stats")
  end
  if not ui.IsMouseDown(ui.Mouse.Right) then ui.SetTooltip(label) end
end

local function tile(slot, row, x, y, width, height, weapon, font, s)
  local red, active = problem(row), inspected == slot
  paint(x, y, width, height, red and C.danger or C.inset, red and 0.20 or 0.78, 5 * s)
  edge(x, y, width, height, red and C.danger or active and C.accent or C.ink, (red or active) and 0.9 or 0.14, 5 * s)
  local size = (weapon and 26 or 27) * s
  gearIcon(weapon and x + (width - size) / 2 or x + 4 * s, y + 3 * s, size, row, s)
  if weapon then
    text(x + 2 * s, y + size + 5 * s, NAMES[slot], width - 4 * s, red and C.danger or C.text, font, "center")
  else
    local tx, tw = x + size + 9 * s, width - size - 14 * s
    text(tx, y + (red and 2 or 9) * s, NAMES[slot], tw, C.text, font)
    if red then
      text(tx, y + 15 * s, row.status == "missing" and "Missing" or "Blocked", tw, C.danger, T.font.tiny)
    end
  end
  if T.Hit("##suitcase-slot" .. slot, x, y, x + width, y + height) then inspected = slot end
  T.HoverFx(x, y, x + width, y + height, s, 5)
  itemHelp(row, NAMES[slot] .. "\n" .. itemName(row) .. "\n" .. location(row))
end

local function mannequin(x, y, w, s)
  local cx = x + w / 2
  local col, alpha = C.muted, 0.43
  local function line(x1, y1, x2, y2)
    ui.DrawLine(cx + x1 * s, y + y1 * s, cx + x2 * s, y + y2 * s, col[1], col[2], col[3], alpha, 2 * s)
  end
  ui.DrawCircle(cx, y + 16 * s, 10 * s, col[1], col[2], col[3], alpha, 2 * s)
  line(0, 26, 0, 32)
  line(-17, 38, 0, 32); line(0, 32, 17, 38)
  line(-17, 38, -28, 66); line(17, 38, 28, 66)
  line(-17, 38, -11, 71); line(17, 38, 11, 71)
  line(-11, 71, -17, 108); line(11, 71, 17, 108)
  line(-11, 71, 11, 71); line(0, 72, 0, 84)
  line(0, 84, -8, 109); line(0, 84, 8, 109)
end

local function inventory(plan, width, s)
  local x, y = ui.GetCursorScreenPos()
  local rows = plan and plan.slots or {}
  local col = math.floor(width * .30)
  local font, step = T.font.small, 36 * s
  for index, slot in ipairs(ARMOR) do
    tile(slot, rows[slot], x, y + (index - 1) * step, col, step - 3 * s, false, font, s)
  end
  for index, slot in ipairs(ACCESSORIES) do
    tile(slot, rows[slot], x + width - col, y + (index - 1) * step, col, step - 3 * s, false, font, s)
  end
  local inset, center = x + col + 8 * s, width - col * 2 - 16 * s
  mannequin(inset, y + 67 * s, center, s)
  local row = rows[inspected]
  text(inset, y + 196 * s, NAMES[inspected], center, C.muted, T.font.small, "center")
  text(inset, y + 216 * s, itemName(row), center, problem(row) and C.danger or C.text, T.font.normal, "center")
  text(inset, y + 237 * s, location(row), center, problem(row) and C.danger or C.muted, T.font.small, "center")
  local gap = 4 * s
  local wy, ww = y + #ARMOR * step + 3 * s, (width - (#WEAPONS - 1) * gap) / #WEAPONS
  for index, slot in ipairs(WEAPONS) do
    tile(slot, rows[slot], x + (index - 1) * (ww + gap), wy, ww, 46 * s, true, T.font.tiny, s)
  end
  blank(x, y, width, #ARMOR * step + 51 * s)
end

local function listView(plan, width, s)
  local x, y = ui.GetCursorScreenPos()
  local slotWidth, locWidth = 82 * s, math.max(83 * s, width * .24)
  text(x + 5 * s, y + 3 * s, "Slot", slotWidth - 8 * s, C.muted, T.font.small)
  text(x + slotWidth, y + 3 * s, "Saved item", width - slotWidth - locWidth, C.muted, T.font.small)
  text(x + width - locWidth, y + 3 * s, "Location", locWidth - 4 * s, C.muted, T.font.small)
  local ry, step = y + 24 * s, 30 * s
  for slot = 0, 22 do
    local row = plan and plan.slots[slot]
    if row and row.target ~= nil and (row.target ~= false or row.current) then
      if problem(row) then paint(x, ry, width, step, C.danger, .13, 4 * s) end
      ui.DrawLine(x, ry, x + width, ry, C.ink[1], C.ink[2], C.ink[3], .14, 1)
      local color = problem(row) and C.danger or C.text
      local ty = ry + 8 * s
      text(x + 5 * s, ty, NAMES[slot], slotWidth - 8 * s, C.muted, T.font.small)
      gearIcon(x + slotWidth, ry + 3 * s, 24 * s, row, s)
      text(x + slotWidth + 30 * s, ty, itemName(row), width - slotWidth - locWidth - 34 * s, color, T.font.small)
      text(x + width - locWidth, ty, location(row), locWidth - 4 * s, problem(row) and C.danger or C.muted, T.font.small)
      if T.Hit("##suitcase-row" .. slot, x, ry, x + width, ry + step) then inspected = slot end
      itemHelp(row, itemName(row) .. "\n" .. location(row))
      ry = ry + step
    end
  end
  blank(x, y, width, ry - y)
end

local function sidebar(width, height, running, s)
  ui.BeginChild("##suitcase-sets", width, height, false)
  local x, y = ui.GetCursorScreenPos()
  local inside = ui.GetContentRegionAvail()
  local ry = y
  if #profile.sets == 0 then text(x + 6 * s, ry + 5 * s, "No saved sets", inside - 10 * s, C.muted, T.font.small) end
  for _, set in ipairs(profile.sets) do
    local selected = set.id == profile.selected
    local data = preview(set)
    local label = not data and "Inventory unavailable" or data.blocked and "Blocked" or
      data.changes == 0 and "Equipped" or ("%d change%s"):format(data.changes, data.changes == 1 and "" or "s")
    paint(x, ry, inside - 2 * s, 43 * s, selected and C.accent or C.inset, selected and .20 or .65, 5 * s)
    if selected then edge(x, ry, inside - 2 * s, 43 * s, C.accent, .65, 5 * s) end
    text(x + 7 * s, ry + 5 * s, set.name, inside - 14 * s, C.text, T.font.normal)
    text(x + 7 * s, ry + 24 * s, label, inside - 14 * s, data and data.blocked and C.danger or C.muted, T.font.tiny)
    if T.Hit("##suitcase-set" .. set.id, x, ry, x + inside - 2 * s, ry + 43 * s) and not running then selectSet(set) end
    if ui.IsItemHovered() then ui.SetTooltip(set.name .. "\n" .. label) end
    ry = ry + 47 * s
  end
  blank(x, y, inside - 2 * s, math.max(25 * s, ry - y))
  ui.EndChild()
end

local function drawForm(selected, running, s)
  if not form then return end
  if form == "delete" then
    ui.Text("Delete " .. selected.name .. "?")
    ui.SameLine()
    if ui.Button("Delete Set") then runForm() end
  else
    ui.SetNextItemWidth(210 * s)
    name = ui.InputTextWithHint("##suitcase-name", "Set name", name, 80)
    ui.SameLine()
    ui.BeginDisabled(running or not snapshot)
    if ui.Button(form == "rename" and "Rename Set" or "Save Set") then runForm() end
    ui.EndDisabled()
  end
  ui.SameLine()
  if ui.Button("Cancel##suitcase-form") then form = nil; notice(nil) end
end

local function drawDetails(selected, height, status, s)
  local plan = selected and preview(selected)
  local width = ui.GetContentRegionAvail()
  local x, y = ui.GetCursorScreenPos()
  if selected then text(x, y + s, selected.name, width - 150 * s, C.text, T.font.large) end
  local summary = plan and ("%d slot%s to change"):format(plan.changes, plan.changes == 1 and "" or "s") or ""
  text(x, y + 25 * s, summary, width - 150 * s, C.muted, T.font.small)
  for index, layout in ipairs({"inventory", "list"}) do
    local bx = x + width - (136 - (index - 1) * 76) * s
    if T.Button("##suitcase-" .. layout, bx, y + 3 * s, bx + (index == 1 and 71 or 60) * s, y + 30 * s, s,
        layout == "inventory" and "Inventory" or "List", {primary = profile.layout == layout}) and profile.layout ~= layout then
      local nextProfile = Sets.copy(profile)
      nextProfile.layout = layout
      persist(nextProfile)
    end
  end
  blank(x, y, width, 39 * s)
  if not selected then
    ui.TextWrapped("Save Equipped to make a set from the gear you’re wearing.")
    return
  end
  local body = math.max(130 * s, height - (editing and 137 or 109) * s)
  ui.BeginChild("##suitcase-preview", width, body, false)
  local content = ui.GetContentRegionAvail()
  if profile.layout == "list" then listView(plan, content, s) else inventory(plan, content, s) end
  ui.EndChild()
  local running = status.running == true
  local detail = message or (plan and plan.blocked and plan.problem)
    or (plan and (plan.changes == 0 and "Set equipped" or "Ready to swap")) or "Inventory unavailable"
  if running then
    detail = status.paused and status.message or ("Swapping · %d / %d moves"):format(status.done, status.total)
  end
  local sx, sy = ui.GetCursorScreenPos()
  local color = (messageError or (plan and plan.blocked)) and C.danger or C.muted
  text(sx, sy, detail, width - 2 * s, color, T.font.small)
  blank(sx, sy, width, 18 * s)
  if ui.IsItemHovered() then ui.SetTooltip(detail) end
  local bx, by = ui.GetCursorScreenPos()
  if T.Button("##suitcase-edit", bx, by, bx + 83 * s, by + 26 * s, s, editing and "Done Editing" or "Edit Set",
      {enabled = not running}) then editing, form = not editing, nil end
  local hx = bx + width - 193 * s
  if T.Button("##suitcase-hotkey", hx, by, hx + 100 * s, by + 26 * s, s, "Make Hotkey",
      {enabled = not running, tooltip = "Put the set on your cursor for your normal hotbar"}) then
    local called, ok, why = pcall(Sets.make_hotkey, selected, API)
    if not called then ok, why = false, "Hailstone did not allow hotkey creation." end
    notice(ok and "Click a slot on your hotbar to place it." or why, not ok)
  end
  if T.Button("##suitcase-equip", bx + width - 87 * s, by, bx + width, by + 26 * s, s, running and "Stop Swap" or "Equip Set",
      {primary = true, enabled = running or (plan and not plan.blocked and plan.changes ~= 0) == true}) then
    if running then
      runtime.cancel()
      notice(runtime.status().message, true)
      nextPoll = 0
    else
      equip(selected, false)
    end
  end
  blank(bx, by, width, 26 * s)
  if editing and not running then
    ui.Text(NAMES[inspected])
    ui.SameLine()
    ui.BeginDisabled(not snapshot)
    if ui.Button("Use Worn") then
      local item = worn(inspected)
      changeSlot(inspected, item and Plan.capture(item) or false)
    end
    ui.SameLine()
    if ui.Button("Set Empty") then changeSlot(inspected, false) end
    ui.SameLine()
    if ui.Button("Ignore Slot") then changeSlot(inspected, nil) end
    ui.EndDisabled()
    ui.SameLine()
    if ui.Button("Rename") then form, name = "rename", selected.name end
    ui.SameLine()
    if ui.Button("Delete") then form = "delete" end
  end
end

local DIALOG = {
  shown = true,
  keepTitle = true,
  size = function() return 683, 605 end,
  resizable = {525, 450},
  onClose = function() opened = false end,
}

local function drawWindow(x, y, s, status)
  local width = ui.GetContentRegionAvail()
  text(x, y + 2 * s, "Equipment Sets", width - 130 * s, C.text, T.font.large)
  if T.Button("##suitcase-save", x + width - 116 * s, y, x + width, y + 27 * s, s, "Save Equipped",
      {enabled = snapshot ~= nil and not status.running}) then form, name = "save", "" end
  blank(x, y, width, 34 * s)
  drawForm(Sets.selected(profile), status.running, s)
  local _, height = ui.GetContentRegionAvail()
  sidebar(math.floor(math.min(142 * s, width * .24)), height, status.running, s)
  ui.SameLine(0, 11 * s)
  ui.BeginChild("##suitcase-details", 0, height, false)
  drawDetails(Sets.selected(profile), height, status, s)
  if #profile.sets == 0 and message then ui.TextWrapped(message) end
  ui.EndChild()
end

ui.window("Suitcase", function()
  owner = API.plugins.Get("script:suitcase")
  if not owner or not API.session.InGame() then
    if key then runtime.reset() end
    key, profile, snapshot, previews, opened, nextPoll = nil, nil, nil, nil, false, 0
    return
  end
  poll(ui.GetTime())
  local wasRunning = runtime.status().running
  runtime.pulse()
  local status = runtime.status()
  if wasRunning and not status.running then
    notice(status.message, status.error)
    snapshot, previews = runtime.snapshot(), nil
    nextPoll = 0
  end
  if not opened or not profile then return end
  hud.Dialog("SuitcaseWnd", "Suitcase", DIALOG, function(x, y, _, _, s) drawWindow(x, y, s, status) end)
end)
