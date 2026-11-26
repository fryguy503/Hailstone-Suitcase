local Runtime = dofile("ui/modern/lib/suitcase_runtime.lua")
local Plan = dofile("ui/modern/lib/suitcase_plan.lua")

local function key(slot, sub)
  return "i:" .. slot .. (sub and sub >= 0 and ":" .. sub or "")
end

local function item(id, name, extra)
  local result = {id = id, name = name, serial = "HS" .. id, count = 1, size = 1,
    type = 10, equipSlots = 1 << 2, usable = true, tradeskill = false, bagSlots = 0}
  for k, v in pairs(extra or {}) do result[k] = v end
  return result
end

local function fixture()
  local f = {time = 1, revision = 1, messages = {}, windows = {}, clicks = 0,
    player = {name = "Tester", zone_id = 1, spawn_id = 100, cur_hp = 100, in_zone = true},
    gear = {["i:23"] = item(90, "Pack", {bagSlots = 3}), ["i:2"] = item(1, "Old Helmet"),
      ["i:23:0"] = item(2, "New Helmet")}}

  local function swap(slot, sub)
    local place = key(slot, sub)
    f.gear["i:33"], f.gear[place] = f.gear[place], f.gear["i:33"]
    f.revision = f.revision + 1
  end

  local inventory = {
    AllItems = function()
      local rows = {{where = "bank", slot = 0, item = item(5, "Bank Only"), place = "b:0"}}
      for place, held in pairs(f.gear) do
        local slot, sub = place:match("i:(%d+):?(%d*)")
        slot, sub = tonumber(slot), tonumber(sub) or -1
        if slot ~= 33 then
          local observed = {}
          for k, v in pairs(held) do observed[k] = v end
          rows[#rows + 1] = {where = slot < 23 and "worn" or "carried", slot = slot, sub = sub,
            bag = sub >= 0 and "Pack" or nil, item = observed, place = place}
        end
      end
      return rows
    end,
    InventorySpace = function() return 2, 6 end,
    ItemsRevision = function() return f.revision end,
    Item = function(slot, sub)
      local held = f.gear[key(slot, sub)]
      if held then return {id = held.id, name = held.name, count = held.count} end
    end,
    ItemJob = function() return f.otherJob end,
    HasSlot = function() return true end,
    CanPlace = function() return not f.noPlacement end,
    ClickSlot = function(slot, sub)
      f.clicks = f.clicks + 1
      local held = f.gear[key(slot, sub)]
      if not f.gear["i:33"] and held and held.stackable and held.count > 1 then
        f.quantity = {slot, sub, held.count}
        f.windows.QuantityWnd = true
      elseif f.confirmAttune and slot < 23 then
        f.windows.ConfirmationDialogBox = true
      else
        swap(slot, sub)
      end
      return true
    end,
  }
  local api = {
    inventory = inventory,
    session = {InGame = function() return f.player.in_zone end},
    character = {Name = function() return f.player.name end},
    windows = {
      Shown = function(name) return f.windows[name] end,
      Text = function() return tostring(f.quantity[3]), true end,
      ChildState = function() return nil, nil, f.quantity[3], f.quantity[3] + 1 end,
      Button = function(window, button)
        assert(window == "QuantityWnd" and button == "QTYW_Accept_Button")
        swap(f.quantity[1], f.quantity[2])
        f.quantity, f.windows.QuantityWnd = nil, nil
        return true
      end,
    },
  }
  f.runtime = Runtime.new(api, {
    GetTime = function() return f.time end,
    GetIO = function() return {shift = f.shift} end,
  }, {
    player_state = function() return f.player end,
    window_state = function(name) return f.windows[name] == true end,
    report_result = function(message) f.messages[#f.messages + 1] = message end,
    item_configurations = function(positions)
      if not f.configurations then return nil end
      local result = {}
      for index, position in ipairs(positions) do
        local held = f.gear[key(position.slot, position.sub)]
        result[index] = held and f.configurations[held.id] or ""
      end
      return result
    end,
  })

  function f.plan(set)
    return Plan.plan(f.runtime.snapshot(), set or {[2] = Plan.capture(f.gear["i:23:0"])})
  end

  function f.pulse(count)
    for _ = 1, count or 1 do
      f.time = f.time + 0.5
      f.runtime.pulse()
    end
  end

  return f
end

local complete = fixture()
local snapshot = complete.runtime.snapshot()
assert(#snapshot.rows == 3 and snapshot.places["i:26"] and not snapshot.places["i:27"])
assert(snapshot.places["i:23:0"].bag.name == "Pack" and snapshot.worn[2].name == "Old Helmet")
for _, row in ipairs(snapshot.rows) do
  if row.place == "i:23:0" then assert(row.bag == "Pack") end
end
assert(complete.runtime.start(complete.plan(), "Test Set"))
complete.pulse(4)
assert(complete.clicks == 3 and complete.gear["i:2"].name == "New Helmet")
assert(complete.gear["i:23:0"].name == "Old Helmet" and not complete.gear["i:33"])
assert(not complete.runtime.status().running and complete.runtime.status().done == 3)
assert(complete.messages[1] == "Equipped Test Set.")

local busy = fixture()
busy.player.casting_spell_id = 1
assert(not busy.runtime.start(busy.plan()) and busy.clicks == 0)
busy.player.casting_spell_id = 0
busy.otherJob = 0
assert(not busy.runtime.start(busy.plan()) and busy.clicks == 0)
busy.otherJob = nil
assert(busy.runtime.start(busy.plan()))
busy.shift = true
busy.pulse()
assert(busy.runtime.status().message:match("Release") and busy.clicks == 0)
busy.shift = false
busy.pulse()
busy.gear["i:2"] = item(3, "Unexpected Helmet")
busy.revision = busy.revision + 1
busy.pulse()
assert(not busy.runtime.status().running and busy.runtime.status().error and busy.clicks == 1)
assert(busy.messages[1]:match("no longer matches"))

local attune = fixture()
attune.confirmAttune = true
assert(attune.runtime.start(attune.plan()))
attune.pulse(3)
assert(attune.clicks == 2 and attune.windows.ConfirmationDialogBox and attune.gear["i:33"].name == "New Helmet")
assert(attune.messages[1]:match("confirmation"))

local ammo = fixture()
ammo.gear["i:23:1"] = item(7, "Arrows", {count = 100, type = 27, stackable = true, equipSlots = 1 << 22})
assert(ammo.runtime.start(ammo.plan({[22] = Plan.capture(ammo.gear["i:23:1"])})))
ammo.pulse(3)
assert(ammo.gear["i:22"].count == 100 and not ammo.windows.QuantityWnd and not ammo.runtime.status().error)

local zone = fixture()
assert(zone.runtime.start(zone.plan()))
zone.pulse()
zone.player = {name = "Tester", zone_id = 2, spawn_id = 99, cur_hp = 100, in_zone = true}
zone.pulse()
assert(zone.runtime.status().error and zone.clicks == 1 and zone.messages[1]:match("zone or character changed"))

local canceled = fixture()
assert(canceled.runtime.start(canceled.plan()))
canceled.pulse()
canceled.runtime.cancel("Character changed.")
assert(canceled.runtime.status().error and canceled.messages[1]:match("Character changed"))

local configured = fixture()
configured.configurations = {[1] = "10:0:0:0:0:0", [2] = "20:0:0:0:0:0"}
local augmented = configured.runtime.snapshot()
assert(augmented.worn[2].configuration == "10:0:0:0:0:0")
assert(augmented.places["i:23:0"].item.configuration == "20:0:0:0:0:0")
assert(configured.runtime.start(configured.plan()))
configured.configurations[2] = "30:0:0:0:0:0"
configured.revision = configured.revision + 1
configured.pulse()
assert(configured.runtime.status().error and configured.clicks == 0)

print("Suitcase runtime tests passed")
