local P = dofile("ui/modern/lib/suitcase_plan.lua")

local function item(id, serial, slots, fields)
  local gear = {id = id, serial = serial, name = "Item " .. id, icon = 500 + id, size = 2,
    count = 1, type = 10, equipSlots = 0, usable = true, stackable = false, tradeskill = false, attuned = false}
  for _, slot in ipairs(slots or {}) do gear.equipSlots = gear.equipSlots | (1 << slot) end
  for k, v in pairs(fields or {}) do gear[k] = v end
  return gear
end

local function row(slot, gear, sub)
  return {item = gear, slot = slot, sub = sub or -1, where = slot < 23 and "worn" or "carried",
    place = "i:" .. slot .. (sub and (":" .. sub) or "")}
end

local function snapshot(rows, places)
  return {rows = rows, places = places or {}}
end

local function apply(plan, snap, lastStep)
  assert(not plan.blocked, plan.problem)
  local live, cursor = {}, nil
  for _, entry in ipairs(snap.rows) do live[entry.place] = entry.item end
  for index = 1, lastStep or #plan.steps do
    local step = plan.steps[index]
    assert(live[step.place] == step.before)
    assert(cursor == step.cursorBefore)
    live[step.place], cursor = step.after, step.cursorAfter
  end
  return live, cursor
end

local function firstClick(plan, kind, slot)
  for index, step in ipairs(plan.steps) do
    if step.kind == kind and step.slot == slot then return index end
  end
end

do
  local helm, resist = item(1, "Helm1", {2}), item(2, "Helm2", {2})
  local bag = {bagSlots = 2, bagType = 0, bagSize = 3}
  local snap = snapshot({row(2, helm), row(23, bag), row(23, resist, 0)})
  local target = P.capture(resist)
  local plan = P.plan(snap, {[2] = target})
  assert(target.icon == resist.icon and target.name == resist.name and target.serial == "Helm2")
  assert(plan.changes == 1 and plan.slots[2].status == "available")
  assert(plan.slots[2].source.place == "i:23:0" and #plan.steps == 3)
  local after, cursor = apply(plan, snap)
  assert(after["i:2"] == resist and after["i:23:0"] == helm and not cursor)
  assert(snap.rows[3].item == resist and plan.slots[3].status == "ignored")
end

do
  local first, second = item(3, "Ring1", {15, 16}), item(3, "Ring2", {15, 16})
  local snap = snapshot({row(15, first), row(16, second)})
  local plan = P.plan(snap, {[15] = P.capture(second), [16] = P.capture(first)})
  assert(plan.changes == 2 and #plan.steps == 3)
  local after, cursor = apply(plan, snap)
  assert(after["i:15"] == second and after["i:16"] == first and not cursor)
  local leaveAlone = P.plan(snap, {[15] = P.capture(second)})
  assert(leaveAlone.blocked and leaveAlone.slots[15].status == "blocked" and #leaveAlone.steps == 0)
  local duplicate = P.plan(snap, {[15] = P.capture(first), [16] = P.capture(first)})
  assert(duplicate.blocked and duplicate.slots[16].status == "ambiguous")

  local moved = P.resolve({row(16, first), row(24, second, 2)}, P.capture(second))
  assert(moved.slot == 24 and moved.sub == 2, "inspection must follow the saved copy's current location")
  local unresolved, why = P.resolve({row(16, first)}, P.capture(second))
  assert(unresolved == nil and why == "missing", "inspection must not select a different copy")
end

do
  local saved, wrong = item(4, "OldUnique", {16}), item(4, "NewUnique", {16})
  local helm = item(5, "Helm5", {2})
  local bank = {item = saved, where = "bank", slot = 0, sub = -1, place = "b:0"}
  local snap = snapshot({row(23, wrong), row(24, helm), bank})
  local missing = P.plan(snap, {[16] = P.capture(saved), [2] = P.capture(helm)})
  assert(missing.blocked and missing.changes == 2 and #missing.steps == 0)
  assert(missing.slots[16].status == "missing" and missing.slots[2].status == "available")

  local numeric = item(4, "0000000000000154", {16})
  local replaced = item(4, "0000000000000188", {16})
  local fallback = P.plan(snapshot({row(23, replaced)}), {[16] = P.capture(numeric)})
  assert(not fallback.blocked and fallback.slots[16].item == replaced)
  local ambiguous = P.plan(snapshot({row(23, replaced), row(24, wrong)}), {[16] = P.capture(numeric)})
  assert(ambiguous.blocked and ambiguous.slots[16].status == "ambiguous")
  assert(P.sameItem(numeric, {id = 4, count = 1}))
  assert(not P.sameItem(numeric, {id = 4, count = 1}, true))
  assert(not P.sameItem(numeric, replaced))
end

do
  local signature, changed = "1:0:0:0:0:0", "2:0:0:0:0:0"
  local persistent = item(18, "Augmented", {16}, {configuration = signature})
  local persistentChanged = item(18, "Augmented", {16}, {configuration = changed})
  local target = P.capture(persistent)
  assert(target.configuration == signature)
  local exact = P.plan(snapshot({row(23, persistentChanged)}), {[16] = target})
  assert(not exact.blocked and exact.slots[16].item == persistentChanged)
  assert(not P.sameItem(persistent, persistentChanged, true))
  assert(P.sameItem(persistent, {id = persistent.id}))

  local old = item(18, "0000000000000149", {16}, {configuration = signature})
  local good = item(18, "0000000000000225", {16}, {configuration = signature})
  local other = item(18, "0000000000000226", {16}, {configuration = changed})
  local same = item(18, "0000000000000227", {16}, {configuration = signature})
  local reused = item(18, "0000000000000149", {16}, {configuration = changed})
  local wanted = {[16] = P.capture(old)}
  local fallback = P.plan(snapshot({row(23, good), row(24, other)}), wanted)
  assert(not fallback.blocked and fallback.slots[16].item == good)
  local missing = P.plan(snapshot({row(23, other)}), wanted)
  assert(missing.blocked and missing.slots[16].status == "missing")
  local ambiguous = P.plan(snapshot({row(23, good), row(24, same)}), wanted)
  assert(ambiguous.blocked and ambiguous.slots[16].status == "ambiguous")
  local conflicting = P.plan(snapshot({row(23, good), row(24, reused)}), wanted)
  assert(conflicting.blocked and conflicting.slots[16].status == "missing")
end

do
  local sword = item(6, "Sword", {13}, {type = 0})
  local shield = item(7, "Shield", {14}, {type = 8})
  local greatsword = item(8, "GreatSword", {13}, {type = 1})
  local snap = snapshot({row(13, sword), row(14, shield), row(23, greatsword)}, {["i:24"] = {slot = 24}})
  local two = P.plan(snap, {[13] = P.capture(greatsword), [14] = false})
  local after, cursor = apply(two, snap)
  assert(after["i:13"] == greatsword and after["i:14"] == nil and not cursor)
  assert(firstClick(two, "pickup", 14) < firstClick(two, "equip", 13))
  local bad = P.plan(snap, {[13] = P.capture(greatsword)})
  assert(bad.blocked and bad.slots[13].status == "blocked")

  local swapBack = snapshot({row(13, greatsword), row(23, sword), row(24, shield)})
  local one = P.plan(swapBack, {[13] = P.capture(sword), [14] = P.capture(shield)})
  local worn = apply(one, swapBack)
  assert(worn["i:13"] == sword and worn["i:14"] == shield)
  assert(firstClick(one, "equip", 13) < firstClick(one, "equip", 14))

  local offhandWeapon = item(9, "Dagger", {14}, {type = 2, stats = {damage = 50}})
  local noDual = snapshot({row(23, offhandWeapon)})
  noDual.dualWield = false
  assert(P.plan(noDual, {[14] = P.capture(offhandWeapon)}).blocked)
end

do
  local old = item(10, "LargeBoot", {19}, {size = 4})
  local new = item(11, "SmallBoot", {19}, {size = 1})
  local tiny = {bagSlots = 2, bagType = 0, bagSize = 1}
  local snap = snapshot({row(19, old), row(23, tiny), row(23, new, 0)}, {["i:23:1"] = {slot = 23, sub = 1}})
  local blocked = P.plan(snap, {[19] = P.capture(new)})
  assert(blocked.blocked and #blocked.steps == 0 and blocked.problem:find("No compatible bag space", 1, true))

  snap.places["i:24"] = {slot = 24, sub = -1}
  local sized = P.plan(snap, {[19] = P.capture(new)})
  local after = apply(sized, snap)
  assert(after["i:19"] == new and after["i:24"] == old)

  local witness = item(12, "Witness", {}, {size = 5, type = 0})
  local previewBag = {bagSlots = 3}
  local preview = snapshot({row(19, old), row(23, previewBag), row(23, new, 0), row(23, witness, 1)})
  local previewPlan = P.plan(preview, {[19] = P.capture(new)})
  local previewAfter = apply(previewPlan, preview)
  assert(previewAfter["i:19"] == new and previewAfter["i:23:0"] == old and previewAfter["i:23:1"] == witness)
  local retry = snapshot({row(19, new), row(23, previewBag), row(23, old, 0), row(23, witness, 1)})
  local already = P.plan(retry, {[19] = P.capture(new)})
  assert(already.changes == 0 and already.slots[19].status == "equipped" and #already.steps == 0)
end

do
  local arrows = item(13, "Arrows", {22}, {type = 27, count = 78, stackable = true})
  local older = item(13, "OldAmmo", {22}, {type = 27, count = 21, stackable = true})
  local snap = snapshot({row(22, older), row(23, arrows)}, {["i:24"] = {slot = 24}})
  local plan = P.plan(snap, {[22] = P.capture(arrows)})
  assert(firstClick(plan, "pickup", 22) < firstClick(plan, "equip", 22))
  assert(plan.steps[1].wholeStack and plan.steps[3].wholeStack)
  local after = apply(plan, snap)
  assert(after["i:22"] == arrows and after["i:24"] == older)
  snap.cursor = older
  assert(P.plan(snap, {[22] = P.capture(arrows)}).blocked)
end

do
  local oldHat = item(14, "OldHat", {2}, {size = 1})
  local newHat = item(15, "NewHat", {2}, {size = 1})
  local oldChest = item(16, "BigChest", {17}, {size = 5})
  local newChest = item(17, "SmallChest", {17}, {size = 1})
  local tiny = {bagSlots = 2, bagType = 0, bagSize = 1}
  local snap = snapshot({row(2, oldHat), row(17, oldChest), row(23, newHat), row(24, tiny), row(24, newChest, 0)},
    {["i:24:1"] = {slot = 24, sub = 1}})
  local plan = P.plan(snap, {[2] = P.capture(newHat), [17] = P.capture(newChest)})
  local after = apply(plan, snap)
  assert(after["i:2"] == newHat and after["i:17"] == newChest)
  assert(after["i:23"] == oldChest and after["i:24:1"] == oldHat)
end

print("Suitcase planner passed identity, clear slots, bag fit, hand order, cursor cycles, full stacks, and retry")
