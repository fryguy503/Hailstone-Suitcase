local functions, binds, files = {}, {}, {}
local player = {name = "Adventurer", in_zone = true, zone_id = 2, spawn_id = 50}
local server = {host = "localhost", world = "Preview", port = 5999}
local lastChat, inspection
local hs = {
  player = function() return player end,
  server = function() return server end,
  chat = function(message) lastChat = message end,
  inspect_item = function(id, augments) inspection = {id = id, augments = augments} end,
  ui_function = function(name, fn) functions[name] = fn end,
  menu = function(label, command) assert(label == "Suitcase" and command == "/suitcase") end,
}
local mq = {
  configDir = "config",
  bind = function(command, fn) binds[command] = fn end,
  pickle = function(path, data) files[path] = data end,
}
local env = setmetatable({
  require = function(name) return name == "mq" and mq or hs end,
  loadfile = function(path)
    if not files[path] then return nil, "cannot open " .. path end
    if files[path] == "broken" then return nil, "malformed file" end
    return function() return files[path] end
  end,
}, {__index = _G})
assert(loadfile("init.lua", "t", env))()

local key = functions.profile_state().key
assert(key and not functions.profile_state().invalid)
assert(functions.save_profile(key, {sets = {{name = "Tank"}}}))
assert(functions.profile_state().data.sets[1].name == "Tank")
assert(functions.profile_state(key).data == nil)

assert(functions.inspect_saved(100, "12:0:34:0:0:0"))
assert(inspection.id == 100 and #inspection.augments == 6 and inspection.augments[3] == 34)
assert(functions.inspect_saved(101, "bad profile data"))
assert(inspection.id == 101 and #inspection.augments == 0)
assert(not functions.inspect_saved(0xffffffff + 1))

binds["/suitcase"]()
binds["/equipset"]("Resist", "Gear")
binds["/suit"]("@1")
local requests = functions.take_requests(key)
assert(#requests == 3 and requests[1] == "" and requests[2] == "Resist Gear" and requests[3] == "@1")
assert(#functions.take_requests(key) == 0)

binds["/suit"]("Tank")
player.zone_id = 3
assert(#functions.take_requests(key) == 0, "queued swap must expire on zone change")
player.zone_id = 2
assert(#functions.take_requests(key) == 0)
player.name = "Another"
assert(functions.profile_state().key ~= key and not functions.profile_state().data)
assert(not functions.save_profile(key, {sets = {}}))
player.name = "Adventurer"
assert(functions.profile_state().data.sets[1].name == "Tank")

local path = next(files)
files[path] = "broken"
assert(functions.profile_state().invalid)
player.in_zone = false
assert(not functions.profile_state())
assert(not functions.inspect_saved(100))
binds["/suitcase"]()
assert(lastChat:find("Enter the world", 1, true))
print("Suitcase character profiles and all three slash aliases passed.")
