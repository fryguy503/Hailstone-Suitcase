local Sets = dofile("ui/modern/lib/suitcase_sets.lua")

local profile = Sets.read({layout = "list", selected = 4, next_id = 8, sets = {
  {id = 4, name = "  Resist  Gear ", targets = {[0] = false, ["2"] = {id = 17, name = "Helm", icon = 612}}},
  {id = 5, name = "RESIST GEAR", targets = {}},
  {id = 4, name = "Travel", targets = {}},
}})
assert(profile.layout == "list" and profile.next_id == 8 and #profile.sets == 1)
assert(Sets.find(profile, "resist gear") == Sets.selected(profile))
local set = Sets.find(profile, "@4")
assert(set.targets[0] == false and set.targets[2].icon == 612 and not set.targets[1])
assert(not Sets.name('"Broken"') and not Sets.name('@4') and not Sets.name('A; B'))

local records = {[0] = {name = "Resist Gear", lines = {"/stand", "/sit"}}}
local held, coin, cursor
local API = {
  inventory = {Item = function() return cursor end, CursorSlot = 33},
  cursor = {Coin = function() return coin end, HoldingButton = function() return held ~= nil end},
  luasocials = {
    Get = function(index) return records[index] end,
    Set = function(index, entry)
      assert(not records[index], "user social would be overwritten")
      records[index] = entry
      return true
    end,
  },
  socials = {
    Free = function()
      for index = 0, 119 do if not records[index] then return index end end
    end,
    ToCursor = function(index) held = index; return true end,
  },
}

cursor = {id = 55}
assert(not Sets.make_hotkey(set, API))
cursor, coin = nil, true
assert(not Sets.make_hotkey(set, API))
coin = nil
assert(Sets.make_hotkey(set, API) and held == 1)
assert(records[0].lines[1] == "/stand" and records[1].lines[1] == "/suitcase @4")
local renamed = Sets.change(set)
renamed.name = "Raid Résist Gear"
assert(not Sets.make_hotkey(renamed, API), "already-held hotkey must be preserved")
held = nil
assert(Sets.make_hotkey(renamed, API) and held == 1 and not records[2])
records[1].lines[2] = "/sit"
held = nil
assert(Sets.make_hotkey(renamed, API) and held == 2 and records[1].lines[2] == "/sit")
assert(#records[2].name <= 15 and utf8.len(records[2].name))
print("Suitcase set model and native hotkey tests passed.")
