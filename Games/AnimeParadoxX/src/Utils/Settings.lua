local HttpService = game:GetService("HttpService")

local Settings = {}

local ROOT_FOLDER = "PoloskaMacros"
local GAME_FOLDER = ROOT_FOLDER .. "/AnimeParadoxX"
local FILE_PATH = GAME_FOLDER .. "/settings.json"

local BOOLEAN_KEYS = {
    Auto2x = true,
    AutoNext = true,
    AutoReplay = true,
    PlayMacro = true,
    WebhookEnabled = true,
}

local data = {}

local function resetData()
    data = {
        Auto2x = false,
        AutoNext = false,
        AutoReplay = false,
        PlayMacro = false,
        WebhookEnabled = false,
    }
end

local function ensureFolder(path)
    if typeof(isfolder) == "function" and isfolder(path) then
        return true
    end

    if typeof(makefolder) ~= "function" then
        return false, "Folder API is unavailable"
    end

    local ok, err = pcall(makefolder, path)
    if not ok and not (
        typeof(isfolder) == "function" and isfolder(path)
    ) then
        return false, tostring(err)
    end

    return true
end

local function ensureFolders()
    local rootOk, rootError = ensureFolder(ROOT_FOLDER)
    if not rootOk then
        return false, rootError
    end

    return ensureFolder(GAME_FOLDER)
end

function Settings.Load()
    resetData()

    if typeof(readfile) ~= "function"
        or typeof(isfile) ~= "function"
        or not isfile(FILE_PATH) then
        return data
    end

    local readOk, contents = pcall(readfile, FILE_PATH)
    if not readOk then
        warn("[Settings] Read failed:", contents)
        return data
    end

    local decodeOk, saved = pcall(
        HttpService.JSONDecode,
        HttpService,
        contents
    )

    if not decodeOk or type(saved) ~= "table" then
        warn("[Settings] Invalid settings file")
        return data
    end

    for key in pairs(BOOLEAN_KEYS) do
        if type(saved[key]) == "boolean" then
            data[key] = saved[key]
        end
    end

    if type(saved.SelectedMacro) == "string"
        and saved.SelectedMacro ~= "" then
        data.SelectedMacro = saved.SelectedMacro
    end

    if type(saved.WebhookUrl) == "string" then
        data.WebhookUrl = saved.WebhookUrl
    end

    return data
end

function Settings.Save()
    if typeof(writefile) ~= "function" then
        return false, "File API is unavailable"
    end

    local folderOk, folderError = ensureFolders()
    if not folderOk then
        return false, folderError
    end

    local encodeOk, contents = pcall(
        HttpService.JSONEncode,
        HttpService,
        data
    )

    if not encodeOk then
        return false, tostring(contents)
    end

    local writeOk, writeError = pcall(writefile, FILE_PATH, contents)
    if not writeOk then
        return false, tostring(writeError)
    end

    return true
end

function Settings.Get(key)
    return data[key]
end

function Settings.Set(key, value)
    if BOOLEAN_KEYS[key] then
        if type(value) ~= "boolean" then
            return false, "Invalid boolean setting: " .. tostring(key)
        end
    elseif key == "SelectedMacro" then
        if value ~= nil and type(value) ~= "string" then
            return false, "Invalid SelectedMacro value"
        end
    elseif key == "WebhookUrl" then
        if value ~= nil and type(value) ~= "string" then
            return false, "Invalid WebhookUrl value"
        end
    else
        return false, "Unknown setting: " .. tostring(key)
    end

    data[key] = value
    return Settings.Save()
end

Settings.Load()

return Settings
