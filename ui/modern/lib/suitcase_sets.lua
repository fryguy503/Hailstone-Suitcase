local M = {}

function M.name(value)
  local name = value:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if name == "" or #name > 48 or not utf8.len(name) or name:find('[%c";]') or name:sub(1, 1) == "@" then return nil end
  return name
end

function M.find(profile, query)
  local id = tonumber(query:match("^@(%d+)$"))
  for index, set in ipairs(profile.sets) do
    if (id and set.id == id) or set.name:lower() == query:lower() then return set, index end
  end
end

function M.selected(profile)
  return M.find(profile, "@" .. tostring(profile.selected or 0))
end

function M.read(value)
  local profile = {sets = {}, next_id = 1, layout = "inventory"}
  if type(value) ~= "table" then return profile end
  if value.layout == "list" then profile.layout = "list" end
  local ids, names = {}, {}
  for _, saved in ipairs(type(value.sets) == "table" and value.sets or {}) do
    if type(saved) == "table" and type(saved.name) == "string" and type(saved.id) == "number" then
      local name, id = M.name(saved.name), math.tointeger(saved.id)
      if name and id and id > 0 and id < math.maxinteger and not ids[id] and not names[name:lower()] then
        local targets = {}
        for rawSlot, target in pairs(type(saved.targets) == "table" and saved.targets or {}) do
          local slot = tonumber(rawSlot)
          if slot and slot >= 0 and slot <= 22 and slot % 1 == 0 then
            if target == false or (type(target) == "table" and type(target.id) == "number") then targets[slot] = target end
          end
        end
        profile.sets[#profile.sets + 1] = {name = name, id = id, targets = targets}
        ids[id], names[name:lower()] = true, true
        profile.next_id = math.max(profile.next_id, id + 1)
      end
    end
  end
  local nextId = type(value.next_id) == "number" and math.tointeger(value.next_id)
  if nextId and nextId < math.maxinteger then profile.next_id = math.max(profile.next_id, nextId) end
  profile.selected = ids[value.selected] and value.selected or (profile.sets[1] and profile.sets[1].id)
  return profile
end

function M.copy(profile)
  local sets = {}
  for index, set in ipairs(profile.sets) do sets[index] = set end
  return {sets = sets, layout = profile.layout, next_id = profile.next_id, selected = profile.selected}
end

function M.change(set)
  local slots = {}
  for slot, target in pairs(set.targets) do slots[slot] = target end
  return {id = set.id, name = set.name, targets = slots}
end

function M.hotkey_command(set)
  return "/suitcase @" .. set.id
end

function M.make_hotkey(set, API)
  if API.inventory.Item(API.inventory.CursorSlot) or API.cursor.Coin() or API.cursor.HoldingButton() then
    return false, "Clear your cursor before making a hotkey."
  end
  local command = M.hotkey_command(set)
  local api, socials = API.luasocials, API.socials
  for index = 0, 119 do
    local entry = api.Get(index)
    if entry and not entry.lua and entry.lines and entry.lines[1] == command then
      local owned = true
      for line = 2, 5 do
        if (entry.lines[line] or "") ~= "" then owned = false end
      end
      if owned then
        if socials.ToCursor(index) then return true end
        return false, "Hailstone could not put this hotkey on your cursor."
      end
    end
  end
  local index = socials.Free()
  if index == nil then return false, "Free a social slot before making another hotkey." end
  -- Social buttons take a 15-byte name. Avoid splitting a UTF-8 character.
  local cut = #set.name <= 15 and #set.name + 1 or utf8.offset(set.name, 0, 16)
  local name = set.name:sub(1, cut - 1)
  if not api.Set(index, {name = name, color = 0, press = "", face = "", lines = {command}}) then
    return false, "Hailstone could not create this hotkey."
  end
  if not socials.ToCursor(index) then return false, "Hailstone could not put this hotkey on your cursor." end
  return true
end

return M
