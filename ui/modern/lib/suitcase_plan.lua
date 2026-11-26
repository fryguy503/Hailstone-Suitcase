-- Computes a complete sequence of ordinary cursor moves without touching live inventory.
local P = {}

local FIRST_WORN, LAST_WORN = 0, 22
local PRIMARY, SECONDARY, RANGE, AMMO = 13, 14, 11, 22
local FIRST_PACK, LAST_PACK = 23, 32

local function serial(item)
  local value = item and item.serial
  if type(value) == "string" and value ~= "" and not value:match("^0+$") then return value end
end

function P.capture(item)
  if not item then return false end
  return {id = item.id, serial = serial(item), name = item.name, icon = item.icon,
    count = item.count, attuned = item.attuned, configuration = item.configuration}
end

-- The cursor API does not expose the serial. Slot checks can require it when the step was planned with one.
function P.sameItem(expected, observed, exact)
  if not expected or not observed then return not expected and not observed end
  if expected.id ~= observed.id or (expected.count or 1) ~= (observed.count or 1) then return false end
  if expected.configuration ~= nil and (exact or observed.configuration ~= nil)
    and expected.configuration ~= observed.configuration then return false end
  local want, got = serial(expected), serial(observed)
  return not want or (not got and not exact) or want == got
end

local function wornPlace(slot)
  return "i:" .. slot
end

local function placeOf(row)
  if row.place then return row.place end
  local top = wornPlace(row.slot)
  return row.sub and row.sub >= 0 and (top .. ":" .. row.sub) or top
end

local function record(snapshot)
  local source = {rows = {}, places = {}, items = {}, witnesses = {}, storage = {}}
  for slot = FIRST_WORN, LAST_WORN do
    source.places[wornPlace(slot)] = {slot = slot, sub = -1}
  end
  for key, at in pairs(snapshot.places or {}) do
    source.places[key] = {slot = at.slot, sub = at.sub or -1, bag = at.bag, item = at.item}
  end
  for _, row in ipairs(snapshot.rows or {}) do
    if row.item and not row.stale and (row.where == "worn" or row.where == "carried") then
      local key = placeOf(row)
      source.rows[#source.rows + 1] = row
      source.items[key] = row.item
      source.places[key] = source.places[key] or {slot = row.slot, sub = row.sub or -1}
      if row.where == "carried" and row.sub and row.sub >= 0 then
        local list = source.witnesses[row.slot] or {}
        list[#list + 1] = row.item
        source.witnesses[row.slot] = list
      end
    end
  end
  for key, at in pairs(source.places) do
    if at.slot >= FIRST_PACK and at.slot <= LAST_PACK then
      if at.sub >= 0 and type(at.bag) ~= "table" then at.bag = source.items[wornPlace(at.slot)] end
      source.storage[#source.storage + 1] = key
    end
  end
  table.sort(source.storage, function(a, b)
    local left, right = source.places[a], source.places[b]
    return left.slot == right.slot and left.sub < right.sub or left.slot < right.slot
  end)
  return source
end

local function matchingRow(rows, target)
  local exact, same = {}, {}
  local savedSerial = serial(target)
  local persistentSerial = savedSerial and savedSerial:match("%D")
  local incompatibleExact = false
  for _, row in ipairs(rows) do
    local item = row.item
    if item.id == target.id then
      local configurationMatches = target.configuration == nil or target.configuration == item.configuration
      if savedSerial and savedSerial == serial(item) then
        if persistentSerial or configurationMatches then exact[#exact + 1] = row
        else incompatibleExact = true end
      end
      if configurationMatches and (target.attuned == nil or target.attuned == item.attuned) then
        same[#same + 1] = row
      end
    end
  end
  -- Bastion's alphanumeric serial identifies the same item after augment changes. Decimal RoF2 serials may churn or
  -- be reassigned between sessions, so require the saved configuration when available and refuse a conflicting match.
  local candidates = (#exact > 0 or persistentSerial or incompatibleExact) and exact or same
  if #candidates == 1 then return candidates[1] end
  return nil, #candidates > 1 and "ambiguous" or "missing"
end

local function twoHanded(item)
  return item and (item.type == 1 or item.type == 4 or item.type == 35)
end

local function instrument(item)
  local kind = item and item.type
  return type(kind) == "number" and kind >= 23 and kind <= 26
end

local function itemName(item)
  return item.name or "Item " .. tostring(item.id)
end

local function fitsSlot(item, slot, actual, dualWield)
  if not item then return false end
  local kind = item.type
  if item.augment or (item.bagSlots or 0) > 0 or kind == 54 or item.usable == false then return false end
  local inMask = item.equipSlots and (item.equipSlots & (1 << slot)) ~= 0
  if slot == RANGE then
    if kind == 27 or kind == 28 then return false end
    inMask = inMask or (item.stats and (item.stats.range or 0) > 0)
  elseif slot == AMMO then
    inMask = inMask or kind == 19 or kind == 27 or kind == 28
  end
  if not inMask then return false end
  if slot == PRIMARY then
    local offhand = actual[wornPlace(SECONDARY)]
    return not offhand or (not twoHanded(item) and not (instrument(item) and instrument(offhand)))
  end
  if slot == SECONDARY then
    local mainhand = actual[wornPlace(PRIMARY)]
    local weapon = kind ~= 27 and kind ~= 28 and kind ~= 43 and kind ~= 44
      and item.stats and (item.stats.damage or 0) > 0
    return not twoHanded(item) and not twoHanded(mainhand)
      and not (instrument(item) and instrument(mainhand)) and not (weapon and dualWield == false)
  end
  return true
end

local function fitsBag(at, item, witnesses)
  if at.sub < 0 then return true end
  if (item.bagSlots or 0) > 0 or type(item.size) ~= "number" then return false end
  local bag = at.bag
  if bag and type(bag.bagSize) == "number" and type(bag.bagType) == "number" then
    if item.size > bag.bagSize then return false end
    if bag.bagType == 2 then return item.type == 27 end
    if bag.bagType == 8 then return item.type == 19 end
    if bag.bagType == 58 then return item.tradeskill == true end
    return bag.bagType ~= 60
  end
  -- Older clients omit container metadata. Existing contents bound capacity and rule out special bags.
  local sized, notQuiver, notThrowingBag, notTradeskillBag = false, false, false, false
  for _, witness in ipairs(witnesses or {}) do
    sized = sized or (type(witness.size) == "number" and witness.size >= item.size)
    notQuiver = notQuiver or (witness.type ~= nil and witness.type ~= 27 and witness.type ~= 43)
    notThrowingBag = notThrowingBag or (witness.type ~= nil and witness.type ~= 19)
    notTradeskillBag = notTradeskillBag or witness.tradeskill == false
  end
  return sized and (item.type == 27 or notQuiver) and (item.type == 19 or notThrowingBag)
    and (item.tradeskill == true or notTradeskillBag)
end

local function canPut(item, existing)
  -- An inventory click merges matching stacks. Plan a separate pickup first if both stacks must be moved.
  return not existing or not item.stackable or not existing.stackable or item.id ~= existing.id
end

local function findStorage(source, actual, item, preferred)
  local function fits(key)
    local at = source.places[key]
    return at and at.slot >= FIRST_PACK and not actual[key] and fitsBag(at, item, source.witnesses[at.slot])
  end
  if preferred and fits(preferred) then return preferred end
  local best, bestSize
  for _, key in ipairs(source.storage) do
    if fits(key) then
      local at = source.places[key]
      local capacity = math.huge
      if at.sub >= 0 then
        capacity = at.bag and at.bag.bagSize or 0
        for _, witness in ipairs(source.witnesses[at.slot] or {}) do
          capacity = math.max(capacity, witness.size or 0)
        end
      end
      if not best or capacity < bestSize then best, bestSize = key, capacity end
    end
  end
  return best
end

local function locate(actual, item)
  for key, there in pairs(actual) do
    if item == there then return key end
  end
end

local function chain(source, actual, from, targetFor, dualWield, preferSource)
  local after = {}
  for key, item in pairs(actual) do after[key] = item end
  local steps, cursor = {}, nil
  local function click(key)
    local at = source.places[key]
    local there = after[key]
    local kind = not cursor and "pickup" or (at.slot <= LAST_WORN and "equip" or "stow")
    steps[#steps + 1] = {slot = at.slot, sub = at.sub, place = key, kind = kind,
      before = there, after = cursor, cursorBefore = cursor, cursorAfter = there,
      wholeStack = kind == "pickup" and there.stackable and (there.count or 1) > 1}
    after[key], cursor = cursor, there
  end

  click(from)
  while cursor do
    local slot = targetFor[cursor]
    local to = slot and wornPlace(slot)
    if to and canPut(cursor, after[to]) and fitsSlot(cursor, slot, after, dualWield) then
      click(to)
    else
      local storage = findStorage(source, after, cursor, preferSource and from)
      if not storage then return nil, nil, "No compatible bag space for " .. itemName(cursor) .. "." end
      click(storage)
    end
  end
  return after, steps
end

local function draft(source, destination, targetFor, dualWield, preferSource)
  local actual = source.items
  local steps = {}
  local function try(from)
    local after, moves, problem = chain(source, actual, from, targetFor, dualWield, preferSource)
    if not after then return false, problem end
    for _, move in ipairs(moves) do steps[#steps + 1] = move end
    actual = after
    return true
  end

  -- Equip into empty slots first to free space. Follow cross-slot swaps in a single cursor chain.
  -- Stow a worn blocker only when no requested item can equip against the current hand/stack state.
  while true do
    local unfinished, done, reason = false, false, nil
    for priority = 1, 4 do
      for slot = FIRST_WORN, LAST_WORN do
        local to = wornPlace(slot)
        local target, there = destination[slot], actual[to]
        if target ~= nil and (target or nil) ~= there then
          unfinished = true
          local from
          if priority >= 3 then
            if there and (target == false or priority == 4) then from = to end
          elseif target and (not there or priority == 2) and canPut(target, there)
            and fitsSlot(target, slot, actual, dualWield) then
            from = locate(actual, target)
          end
          if from then
            local changed, failure = try(from)
            if changed then done = true; break end
            reason = reason or failure
          end
        end
      end
      if done then break end
    end
    if not unfinished then return steps end
    if not done or #steps > 8 * (LAST_WORN + 1) then
      return nil, reason or "The saved equipment slots cannot be reached safely."
    end
  end
end

function P.plan(snapshot, targets)
  snapshot, targets = snapshot or {}, targets or {}
  local source = record(snapshot)
  local result = {steps = {}, slots = {}, changes = 0, blocked = false}
  local destination, targetFor = {}, {}
  local function reject(slot, status, message)
    if slot then
      result.slots[slot].status = status
      result.slots[slot].problem = message
    end
    result.blocked = true
    result.problem = result.problem or message
  end

  for slot = FIRST_WORN, LAST_WORN do
    local target = targets[slot]
    local current = source.items[wornPlace(slot)]
    local detail = {slot = slot, target = target, current = current, status = "ignored"}
    result.slots[slot] = detail
    if target == false then
      destination[slot] = false
      detail.status = current and "available" or "empty"
      if current then result.changes = result.changes + 1 end
    elseif type(target) == "table" then
      local row, unresolved = matchingRow(source.rows, target)
      if not row then
        result.changes = result.changes + 1
        local reason = unresolved == "ambiguous" and " has more than one matching copy." or " is missing from worn gear and bags."
        reject(slot, unresolved, itemName(target) .. reason)
      else
        detail.source, detail.item = row, row.item
        detail.status = row.item == current and "equipped" or "available"
        if row.item ~= current then result.changes = result.changes + 1 end
        if targetFor[row.item] ~= nil then
          reject(slot, "ambiguous", itemName(target) .. " is assigned to two equipment slots.")
        else
          destination[slot], targetFor[row.item] = row.item, slot
          if row.where == "worn" and row.slot ~= slot and targets[row.slot] == nil then
            reject(slot, "blocked", itemName(target) .. " is worn in a slot this set leaves unchanged.")
          end
        end
      end
    end
  end
  if result.blocked or result.changes == 0 then return result end
  if snapshot.cursor then
    reject(nil, "blocked", "Empty the item cursor before equipping a set.")
    return result
  end

  local final = {}
  for slot = FIRST_WORN, LAST_WORN do
    local target = destination[slot]
    if target == nil then target = source.items[wornPlace(slot)] end
    final[wornPlace(slot)] = target or nil
  end
  for slot = FIRST_WORN, LAST_WORN do
    local item = destination[slot]
    if item and item ~= source.items[wornPlace(slot)] and not fitsSlot(item, slot, final, snapshot.dualWield) then
      reject(slot, "blocked", itemName(item) .. " cannot be equipped in that slot with this set.")
    end
  end
  if result.blocked then return result end

  local steps, reason = draft(source, destination, targetFor, snapshot.dualWield, true)
  if not steps then steps, reason = draft(source, destination, targetFor, snapshot.dualWield, false) end
  if steps then result.steps = steps else reject(nil, "blocked", reason) end
  return result
end

return P
