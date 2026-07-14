local HttpService = game:GetService("HttpService")
local Config = require("src.Config")
local Actions = require("src.Macro.Actions")

local Storage = {}

local function getFolderPath()
    local gameFolder = Config.GameFolderName
    if type(gameFolder) ~= "string" or gameFolder == "" then
        return Config.FolderName
    end
    return Config.FolderName .. "/" .. gameFolder
end

local SUPPORTED = {
    PlaceUnit = true,
    UpgradeUnit = true,
    SellUnit = true,

}

function Storage.ParseTime(value)
    if type(value) ~= "string" then return nil, nil end
    local waveText, secondsText = value:match("^(%-?%d+)%s+([%d%.]+)$")
    local wave, seconds = tonumber(waveText), tonumber(secondsText)
    if not wave or not seconds or seconds < 0 then return nil, nil end
    return wave, seconds
end

function Storage.ToOrderedList(macro)
    local list = {}
    if type(macro) ~= "table" then return list end
    for key, value in pairs(macro) do
        local index = tonumber(key)
        if index and type(value) == "table" then
            list[#list + 1] = { index = index, action = value }
        end
    end
    table.sort(list, function(a, b) return a.index < b.index end)
    return list
end

function Storage.NewEmpty(speed)
    return {
        ["Format Version"] = Config.FormatVersion,
        ["Time Basis"] = Config.TimeBasis,
        ["Game Speed"] = tonumber(speed) or Config.DefaultGameSpeed,
    }
end

function Storage.Validate(macro, allowEmpty)
    if type(macro) ~= "table" then return false, "Macro must be a table" end
    local list = Storage.ToOrderedList(macro)
    if #list == 0 then
        if allowEmpty then return true end
        return false, "Macro contains no actions"
    end

    for _, entry in ipairs(list) do
        local action = entry.action
        if type(action.Type) ~= "string" or not SUPPORTED[action.Type] then
            return false, ("Action #%d: unsupported Type '%s'"):format(entry.index, tostring(action.Type))
        end

        local wave = Storage.ParseTime(action.Time)
        if not wave then return false, ("Action #%d: invalid Time"):format(entry.index) end

        if action.Type == "PlaceUnit" then
            if type(action.Unit) ~= "string" or action.Unit == "" then
                return false, ("Action #%d: invalid Unit"):format(entry.index)
            end
            local position, positionError = Actions.decodePosition(action.Pos)
            if not position then return false, ("Action #%d: %s"):format(entry.index, positionError) end
            if type(action.Rotation) ~= "number" then
                return false, ("Action #%d: invalid Rotation"):format(entry.index)
            end
        else
            if type(action.Pos) ~= "string" or action.Pos == "" then
                return false, ("Action #%d: missing unit label"):format(entry.index)
            end
            if action.Pos:sub(1, 11) == "UNRESOLVED:" then
                return false, ("Action #%d: unit UUID was not resolved"):format(entry.index)
            end
        end

    end
    return true
end

function Storage.Serialize(macro)
    return HttpService:JSONEncode(macro)
end

function Storage.Deserialize(text)
    if type(text) ~= "string" or text == "" then return nil, "Empty macro file" end
    local ok, macro = pcall(HttpService.JSONDecode, HttpService, text)
    if not ok then return nil, "Invalid JSON: " .. tostring(macro) end
    local valid, err = Storage.Validate(macro, true)
    if not valid then return nil, err end
    return macro
end

function Storage.SanitizeName(name)
    if type(name) ~= "string" then return nil, "Invalid file name" end
    name = name:match("^%s*(.-)%s*$") or ""
    if name:sub(-5):lower() == ".json" then name = name:sub(1, -6) end
    if name == "" then return nil, "File name is empty" end
    if #name > 64 then return nil, "File name is too long" end
    if name == "." or name == ".." or name:find("..", 1, true)
        or name:find("[/\\:%*%?\"<>|]") or name:find("[%c]") then
        return nil, "File name contains forbidden characters"
    end
    return name
end

local function hasFiles()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
end

local function createFolder(path)
    if typeof(makefolder) == "function" and typeof(isfolder) == "function"
        and not isfolder(path) then
        local ok, err = pcall(makefolder, path)
        if not ok then return false, tostring(err) end
    end
    return true
end

local function ensureFolder()
    local rootOk, rootError = createFolder(Config.FolderName)
    if not rootOk then return false, rootError end

    local folderPath = getFolderPath()
    if folderPath ~= Config.FolderName then
        return createFolder(folderPath)
    end
    return true
end

function Storage.Exists(name)
    local safeName = Storage.SanitizeName(name)
    if not safeName or typeof(isfile) ~= "function" then return false end
    return isfile(getFolderPath() .. "/" .. safeName .. ".json")
end

function Storage.Save(name, macro)
    if not hasFiles() then return false, "File API unavailable" end
    local safeName, nameError = Storage.SanitizeName(name)
    if not safeName then return false, nameError end
    local valid, validationError = Storage.Validate(macro, true)
    if not valid then return false, validationError end
    local folderOk, folderError = ensureFolder()
    if not folderOk then return false, "Folder creation failed: " .. folderError end
    local encodeOk, json = pcall(Storage.Serialize, macro)
    if not encodeOk then return false, "JSON encode failed: " .. tostring(json) end
    local writeOk, writeError = pcall(writefile, getFolderPath() .. "/" .. safeName .. ".json", json)
    if not writeOk then return false, "Write failed: " .. tostring(writeError) end
    return true
end

function Storage.CreateEmpty(name, speed)
    local safeName, nameError = Storage.SanitizeName(name)
    if not safeName then return false, nameError end
    ensureFolder()
    if Storage.Exists(safeName) then return false, "Macro already exists" end
    local ok, err = Storage.Save(safeName, Storage.NewEmpty(speed))
    if not ok then return false, err end
    return true, safeName
end

function Storage.Load(name)
    if not hasFiles() then return nil, "File API unavailable" end
    local safeName, nameError = Storage.SanitizeName(name)
    if not safeName then return nil, nameError end
    local path = getFolderPath() .. "/" .. safeName .. ".json"
    if typeof(isfile) == "function" and not isfile(path) then return nil, "File not found" end
    local ok, text = pcall(readfile, path)
    if not ok then return nil, "Read failed: " .. tostring(text) end
    return Storage.Deserialize(text)
end

function Storage.List()
    if typeof(listfiles) ~= "function" then return {} end
    ensureFolder()
    local ok, paths = pcall(listfiles, getFolderPath())
    if not ok then return {} end
    local names = {}
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)%.json$")
        if name then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

return Storage
