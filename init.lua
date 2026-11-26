local hs = require("hailstone")
local mq = require("mq")

local requests = {}
local requestScope, requestZone

local function scope()
  local player, server = hs.player(), hs.server()
  if not player or not player.in_zone or not player.name or player.name == "" or not server then return nil end
  local key = table.concat({server.host or server.world_host or "", tostring(server.port or ""), server.world or "", player.name}, "|"):lower()
  return key, tostring(player.zone_id) .. ":" .. tostring(player.spawn_id)
end

local function filename(key)
  local hash = 0xcbf29ce484222325
  for index = 1, #key do hash = (hash ~ key:byte(index)) * 0x100000001b3 end
  return string.format("%s/suitcase-%016x.lua", mq.configDir, hash)
end

local function reply(message)
  hs.chat("Suitcase: " .. message, 15)
end

hs.ui_function("player_state", hs.player)
hs.ui_function("report_result", reply)
hs.ui_function("window_state", function(name) return mq.TLO.Window(name).Open() end)

hs.ui_function("item_configurations", function(places)
  local configurations = {}
  for index, at in ipairs(places) do
    local item = mq.TLO.Me.Inventory(at.slot)
    if at.sub >= 0 then item = item.Item(at.sub + 1) end
    -- Earlier Hailstone builds lack Augs/AugSlot. Let the planner use the server's serial there.
    local ok, available = pcall(function() return item.Augs() end)
    if not ok or available == nil then
      if index == 1 then return {} end
      configurations[index] = ""
    else
      local ids = {}
      for socket = 1, 6 do ids[socket] = item.AugSlot(socket).Item.ID() or 0 end
      configurations[index] = table.concat(ids, ":")
    end
  end
  return configurations
end)

hs.ui_function("profile_state", function(previous)
  local key = scope()
  if not key or key == previous then return key and {key = key} end
  local read, errorText = loadfile(filename(key))
  if not read then return {key = key, invalid = not tostring(errorText):match("^cannot open ")} end
  local value = read()
  if type(value) == "table" and value.scope == key and value.version == 1 then return {key = key, data = value} end
  return {key = key, invalid = true}
end)

hs.ui_function("save_profile", function(key, data)
  if not key or key ~= scope() or type(data) ~= "table" then return false end
  data.scope, data.version = key, 1
  return pcall(mq.pickle, filename(key), data)
end)

hs.ui_function("take_requests", function(key)
  local active, zone = scope()
  if key ~= active or key ~= requestScope then return {} end
  if requestZone ~= zone then requests = {}; return {} end
  local pending = requests
  requests = {}
  return pending
end)

local function request(...)
  local key, zone = scope()
  if not key then return reply("Enter the world before using equipment sets.") end
  if key ~= requestScope or zone ~= requestZone then
    requestScope, requestZone, requests = key, zone, {}
  end
  if #requests < 16 then requests[#requests + 1] = table.concat({...}, " ") end
end

for _, cmd in ipairs({"/suitcase", "/equipset", "/suit"}) do
  pcall(mq.bind, cmd, request)
end

pcall(hs.menu, "Suitcase", "/suitcase")
