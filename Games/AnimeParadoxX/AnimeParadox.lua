-- Bundled by luabundle {"version":"1.7.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
--!nocheck
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local PoloskaLib = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/altpoloska/PoloskaLib/refs/heads/main/PoloskaLib.lua"
))()

local Config = require("src.Config")
local Recorder = require("src.Macro.Recorder")
local Player = require("src.Macro.Player")
local Storage = require("src.Macro.Storage")
local GameAdapter = require("src.Macro.GameAdapter")
local Interface = require("src.UI.Interface")
local AntiAfk = require("src.Utils.AntiAfk")
local Settings = require("src.Utils.Settings")

AntiAfk.Start()

local function GetWave()
    local ok, currentWave = pcall(function()
        return LocalPlayer.PlayerGui.GameHUD.WaveFrame.WaveInfo.Waves.CurrentWave
    end)

    if not ok or not currentWave then
        return nil
    end

    local wave = tonumber(currentWave.Text)
    if wave == nil then
        warn(
            "[MacroRecorder] Cannot parse CurrentWave.Text:",
            currentWave.Text
        )
        return nil
    end

    return math.max(wave, 1)
end

local adapter = GameAdapter.new()
local recorder = Recorder.new({ GetWave = GetWave })
local player = Player.new({
    GetWave = GetWave,
    Dispatch = function(action, ctx) return adapter:Dispatch(action, ctx) end,
    OnStart = function()
        adapter:ResetRegistry()
    end,
})
adapter:InstallHooks(recorder)

Interface.new({
    PoloskaLib = PoloskaLib,
    Config = Config,
    Storage = Storage,
    Recorder = recorder,
    Player = player,
    Adapter = adapter,
    Settings = Settings,
})

end)
__bundle_register("src.Utils.Settings", function(require, _LOADED, __bundle_register, __bundle_modules)
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
}

local data = {}

local function resetData()
    data = {
        Auto2x = false,
        AutoNext = false,
        AutoReplay = false,
        PlayMacro = false,
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
    else
        return false, "Unknown setting: " .. tostring(key)
    end

    data[key] = value
    return Settings.Save()
end

Settings.Load()

return Settings

end)
__bundle_register("src.Utils.AntiAfk", function(require, _LOADED, __bundle_register, __bundle_modules)
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local AntiAfk = {}

local LocalPlayer = Players.LocalPlayer
local CONNECTION_KEY = "__AnimeParadoxXAntiAfkConnection"

local function getSharedEnvironment()
    if typeof(getgenv) == "function" then
        local ok, environment = pcall(getgenv)
        if ok and type(environment) == "table" then
            return environment
        end
    end

    return _G
end

local function isConnectionActive(connection)
    if typeof(connection) ~= "RBXScriptConnection" then
        return false
    end

    local ok, connected = pcall(function()
        return connection.Connected
    end)

    return ok and connected == true
end

function AntiAfk.Start()
    local environment = getSharedEnvironment()
    local existingConnection = environment[CONNECTION_KEY]

    if isConnectionActive(existingConnection) then
        return true, "Already active"
    end

    local connection = LocalPlayer.Idled:Connect(function()
        local camera = workspace.CurrentCamera
        local cameraCFrame = camera and camera.CFrame or CFrame.new()

        local ok, err = pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.new(0, 0), cameraCFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), cameraCFrame)
        end)

        if not ok then
            warn("[Anti-AFK] VirtualUser input failed:", err)
        end
    end)

    environment[CONNECTION_KEY] = connection
    print("[Anti-AFK] Enabled for the current session")

    return true
end

function AntiAfk.IsActive()
    local environment = getSharedEnvironment()
    return isConnectionActive(environment[CONNECTION_KEY])
end

return AntiAfk

end)
__bundle_register("src.UI.Interface", function(require, _LOADED, __bundle_register, __bundle_modules)
local Interface = {}

function Interface.new(deps)
    local lib = deps.PoloskaLib
    local Config = deps.Config
    local Storage = deps.Storage
    local recorder = deps.Recorder
    local player = deps.Player
    local adapter = deps.Adapter
    local settings = deps.Settings

    local selectedName = settings.Get("SelectedMacro")
    local auto2xEnabled = settings.Get("Auto2x") == true
    local selectedSpeed = auto2xEnabled and 2 or 1
    local playEnabled = settings.Get("PlayMacro") == true
    local autoNextEnabled = settings.Get("AutoNext") == true
    local autoReplayEnabled = settings.Get("AutoReplay") == true
    local matchEndLatched = false
    local nextRewardClickAt = 0
    local overwriteConfirmUntil = 0
    local arm

    if selectedName and not Storage.Exists(selectedName) then
        selectedName = nil
        settings.Set("SelectedMacro", nil)
    end

    if autoNextEnabled and autoReplayEnabled then
        autoNextEnabled = false
        settings.Set("AutoNext", false)
    end

    local window = lib:Create({
        Name = "Anime Paradox X Macro Recorder",
        Size = UDim2.fromOffset(660, 480),
        ToggleKey = Config.ToggleKey,
    })

    local function notify(title, text, duration)
        window:Notification({
            Title = title,
            Text = text,
            Duration = duration or 3,
        })
    end

    local function countActions(macro)
        return #Storage.ToOrderedList(macro)
    end

    local function styleDropdownArrows()
        for _, arrow in ipairs(window.Gui:GetDescendants()) do
            local isArrow = arrow:IsA("TextLabel")
                and (arrow.Text == "▾" or arrow.Text == "▴")

            if isArrow and not arrow:FindFirstChild("DropdownChevron") then
                local icon = Instance.new("ImageLabel")
                icon.Name = "DropdownChevron"
                icon.Size = UDim2.fromOffset(14, 14)
                icon.Position = UDim2.fromScale(0.5, 0.5)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1
                icon.Image = Config.DropdownChevronIcon
                icon.ImageColor3 = Color3.fromRGB(140, 140, 150)
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = arrow

                local function syncRotation()
                    icon.Rotation = arrow.Text == "▴" and 180 or 0
                end

                syncRotation()
                arrow.TextTransparency = 1
                arrow:GetPropertyChangedSignal("Text"):Connect(syncRotation)
            end
        end
    end

    local mainTab = window:Tab({ Name = "Main" })

    mainTab:Toggle({
        Name = "Auto 2x speed",
        StartingState = auto2xEnabled,
        Callback = function(state)
            auto2xEnabled = state
            selectedSpeed = state and 2 or 1
            settings.Set("Auto2x", state)

            if not recorder:IsRecording() then
                recorder:SetGameSpeed(selectedSpeed)
            end

            local ok, err = adapter:SetGameSpeed(selectedSpeed)
            if not ok then
                notify("Speed", err)
            end

            if player:IsPlaying() then
                player:Stop()
                adapter:ResetRegistry()

                task.defer(function()
                    if arm then
                        arm()
                    end
                end)
            end
        end,
    })

    local autoNextToggle
    local autoReplayToggle

    autoNextToggle = mainTab:Toggle({
        Name = "Auto Next",
        StartingState = autoNextEnabled,
        Callback = function(state)
            autoNextEnabled = state
            settings.Set("AutoNext", state)

            if state and autoReplayToggle then
                autoReplayEnabled = false
                settings.Set("AutoReplay", false)
                autoReplayToggle:Set(false)
            end
        end,
    })

    autoReplayToggle = mainTab:Toggle({
        Name = "Auto Replay",
        StartingState = autoReplayEnabled,
        Callback = function(state)
            autoReplayEnabled = state
            settings.Set("AutoReplay", state)

            if state and autoNextToggle then
                autoNextEnabled = false
                settings.Set("AutoNext", false)
                autoNextToggle:Set(false)
            end
        end,
    })

    mainTab:Button({
        Name = "Dismiss reward popup",
        Callback = function()
            local ok, err = adapter:DismissRewardPopup()
            if not ok then
                notify("Reward popup", err)
            end
        end,
    })

    mainTab:Credit({
        Name = "polosa__",
        Description = "Anime Paradox X (v3.23)",
    })

    local macroTab = window:Tab({ Name = "Macro" })
    local status = macroTab:Section("Select or create a macro")
    local dropdown

    local recordedActionNames = {
        PlaceUnit = "Place",
        UpgradeUnit = "Upgrade",
        SellUnit = "Sell",
    }

    local recordingName = nil
    local latestRecordedAction = nil
    local playingName = nil
    local latestPlayedAction = nil

    local function describeRecordedAction(action)
        local actionName = recordedActionNames[action.Type]
            or tostring(action.Type)
        local details = nil

        if action.Type == "PlaceUnit" then
            details = action.Label or action.Unit
        elseif type(action.Pos) == "string"
            and not string.find(action.Pos, "UNRESOLVED:", 1, true) then
            details = action.Pos
        end

        if details then
            return actionName .. " " .. details
        end

        return actionName
    end

    local function renderRecordingStatus()
        if not recordingName then
            return
        end

        local text = "Recording " .. recordingName
        if latestRecordedAction then
            text = text .. "\n\n" .. describeRecordedAction(
                latestRecordedAction
            )
        end

        status.Text = text
    end

    local function renderPlayingStatus()
        if not playingName then
            return
        end

        local text = "Playing macro " .. playingName
        if latestPlayedAction then
            text = text .. "\n\n" .. describeRecordedAction(
                latestPlayedAction
            )
        end

        status.Text = text
    end

    local function refreshMacroList()
        dropdown:Clear()
        dropdown:AddItems(Storage.List())
    end

    arm = function(waitForReset)
        if not playEnabled
            or not selectedName
            or recorder:IsRecording()
            or player:IsPlaying() then
            return
        end

        local macro, loadError = Storage.Load(selectedName)
        if not macro or countActions(macro) == 0 then
            status.Text = "Cannot play: " .. tostring(loadError or "empty macro")
            return
        end

        local macroName = selectedName
        local ok, playError = player:Play(macro, {
            PlaybackSpeed = selectedSpeed,
            WaitForReset = waitForReset == true,
            OnWaiting = function(wave)
                playingName = nil
                latestPlayedAction = nil
                status.Text = "Armed; waiting for wave " .. tostring(wave)
            end,
            OnStarted = function()
                playingName = macroName
                latestPlayedAction = nil
                renderPlayingStatus()
            end,
            OnActionPlayed = function(action)
                latestPlayedAction = action
                renderPlayingStatus()
            end,
            OnFinished = function(success, message)
                playingName = nil
                latestPlayedAction = nil

                if not success then
                    status.Text = "Stopped: " .. tostring(message)
                    return
                end

                status.Text = "Macro completed; waiting for Replay or Next"
            end,
        })

        if not ok then
            status.Text = "Cannot arm: " .. tostring(playError)
        end
    end

    dropdown = macroTab:Dropdown({
        Name = "Select macro",
        Items = Storage.List(),
        StartingText = selectedName or "Select a macro...",
        Callback = function(item)
            local name = typeof(item) == "table" and item[1] or item
            if not name or name == "" then
                return
            end

            player:Stop()
            adapter:ResetRegistry()
            selectedName = name
            settings.Set("SelectedMacro", name)

            local macro, loadError = Storage.Load(name)
            if macro then
                status.Text = ("Selected: %s (%d actions)"):format(
                    name,
                    countActions(macro)
                )
            else
                status.Text = tostring(loadError)
            end

            arm()
        end,
    })

    macroTab:Button({
        Name = "Refresh list",
        Callback = refreshMacroList,
    })

    macroTab:Textbox({
        Name = "New macro",
        Placeholder = "macro name",
        Callback = function(text)
            local ok, result = Storage.CreateEmpty(text, selectedSpeed)
            if not ok then
                notify("Storage", result)
                return
            end

            selectedName = result
            settings.Set("SelectedMacro", result)
            refreshMacroList()
            status.Text = "Created: " .. result
        end,
    })

    local recordToggle
    local suppressRecordCallback = false

    local function setRecordToggle(value)
        suppressRecordCallback = true
        recordToggle:Set(value)
        suppressRecordCallback = false
    end

    recordToggle = macroTab:Toggle({
        Name = "Record macro",
        StartingState = false,
        Callback = function(state)
            if suppressRecordCallback then
                return
            end

            if state then
                if not selectedName then
                    notify("Macro", "Select or create a macro")
                    setRecordToggle(false)
                    return
                end

                local oldMacro = Storage.Load(selectedName)
                if oldMacro
                    and countActions(oldMacro) > 0
                    and os.clock() > overwriteConfirmUntil then
                    overwriteConfirmUntil = os.clock() + 8
                    notify(
                        "Overwrite",
                        "Enable Record again within 8 seconds",
                        8
                    )
                    setRecordToggle(false)
                    return
                end

                player:Stop()
                adapter:ResetRegistry()
                recorder:SetGameSpeed(selectedSpeed)
                adapter:SetGameSpeed(selectedSpeed)

                local ok, recordError = recorder:Start()
                if not ok then
                    notify("Macro", recordError)
                    setRecordToggle(false)
                    return
                end

                recordingName = selectedName
                latestRecordedAction = nil
                renderRecordingStatus()

                task.spawn(function()
                    while recorder:IsRecording()
                        and recordingName == selectedName do
                        local actions = recorder.Actions
                        latestRecordedAction = actions[#actions]
                        renderRecordingStatus()
                        task.wait(0.1)
                    end
                end)

                return
            end

            if recorder:IsRecording() then
                local macro = recorder:Stop()
                recordingName = nil
                latestRecordedAction = nil

                local resolved, resolveError = adapter:WaitForPendingActions(
                    Config.EntityCaptureTimeout
                )

                if not resolved then
                    status.Text = "Save failed: " .. tostring(resolveError)
                    notify("Macro", resolveError, 5)
                    return
                end

                local ok, saveError = Storage.Save(selectedName, macro)

                if ok then
                    status.Text = ("Saved %d actions"):format(countActions(macro))
                else
                    status.Text = "Save failed: " .. tostring(saveError)
                end

                refreshMacroList()
            end
        end,
    })

    local playToggle

    playToggle = macroTab:Toggle({
        Name = "Play macro",
        StartingState = playEnabled,
        Callback = function(state)
            playEnabled = state
            settings.Set("PlayMacro", state)

            if state then
                if arm then
                    arm()
                end
                return
            end

            player:Stop()
            adapter:ResetRegistry()
            playingName = nil
            latestPlayedAction = nil
            status.Text = "Playback disabled"
        end,
    })

    if auto2xEnabled then
        recorder:SetGameSpeed(2)
        adapter:SetGameSpeed(2)
    end

    if playEnabled and selectedName then
        task.defer(function()
            arm()
        end)
    end

    task.spawn(function()
        while window.Gui and window.Gui.Parent do
            local autoActionEnabled = autoNextEnabled or autoReplayEnabled
            local rewardPopupVisible = adapter:IsRewardPopupVisible()

            if autoActionEnabled
                and rewardPopupVisible
                and os.clock() >= nextRewardClickAt then
                nextRewardClickAt = os.clock() + 0.5

                local dismissed, dismissError = adapter:DismissRewardPopup()
                if not dismissed then
                    notify("Reward popup", dismissError, 5)
                end
            elseif not rewardPopupVisible then
                local finished, evidence = adapter:IsMatchFinished()

                if finished and not matchEndLatched then
                    matchEndLatched = true
                    player:Stop()
                    adapter:ResetRegistry()

                    local actionOk = true
                    local actionError = nil
                    local actionName = nil

                    if autoReplayEnabled then
                        actionName = "Replay"
                        actionOk, actionError = adapter:Replay()
                    elseif autoNextEnabled then
                        actionName = "Next"
                        actionOk, actionError = adapter:NextStage()
                    end

                    if actionName and not actionOk then
                        notify("Auto " .. actionName, actionError, 5)
                    elseif actionName then
                        status.Text = actionName .. " sent; waiting for next match"

                        if playEnabled then
                            task.defer(function()
                                arm(true)
                            end)
                        end
                    else
                        status.Text = "Match finished: "
                            .. tostring(evidence or "result GUI")
                    end
                elseif not finished then
                    matchEndLatched = false
                end
            end

            task.wait(Config.MatchEndPollInterval)
        end
    end)

    task.defer(styleDropdownArrows)

    return {
        window = window,
        recorder = recorder,
        player = player,
    }
end

return Interface

end)
__bundle_register("src.Macro.GameAdapter", function(require, _LOADED, __bundle_register, __bundle_modules)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Config = require("src.Config")
local UnitRegistry = require("src.Macro.UnitRegistry")

local LocalPlayer = Players.LocalPlayer
local GameAdapter = {}
GameAdapter.__index = GameAdapter

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function getUnitAction()
    local playersFolder = workspace:FindFirstChild("Players")
    local playerFolder = playersFolder and playersFolder:FindFirstChild(LocalPlayer.Name)
    local handler = playerFolder and playerFolder:FindFirstChild("CharacterHandler")
    local remotes = handler and handler:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("UnitAction") or nil
end

local function getGlobalRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name) or nil
end

local function getInventoryList()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local inventory = pg and pg:FindFirstChild("UnitInventory")
    local root = inventory and inventory:FindFirstChild("Inventory")
    local content = root and root:FindFirstChild("Content")
    local units = content and content:FindFirstChild("Units")
    local listFrame = units and units:FindFirstChild("UnitsListFrame")
    return listFrame and listFrame:FindFirstChild("List") or nil
end

local function readInventoryName(entry)
    local attributeName = trim(entry:GetAttribute("UnitName"))
    if attributeName then return attributeName end

    -- Fallback for older UI versions that do not expose UnitName as an attribute.
    local ok, text = pcall(function()
        return entry.Frame.UnitFrame.Content.NameLabel.Text
    end)
    return ok and trim(text) or nil
end

local function isInventoryEntryEquipped(entry)
    local frame = entry and entry:FindFirstChild("Frame")
    local checkmark = frame and frame:FindFirstChild("Checkmark")
    return checkmark ~= nil
        and checkmark:IsA("GuiObject")
        and checkmark.Visible == true
end

local function getEntities()
    return workspace:FindFirstChild("Entities")
end

local function isActuallyVisible(guiObject, playerGui)
    if not guiObject:IsA("GuiObject") or not guiObject.Visible then
        return false
    end

    if guiObject.AbsoluteSize.X <= 0 or guiObject.AbsoluteSize.Y <= 0 then
        return false
    end

    local parent = guiObject.Parent
    while parent and parent ~= playerGui do
        if parent:IsA("GuiObject") and not parent.Visible then
            return false
        end

        if parent:IsA("ScreenGui") and not parent.Enabled then
            return false
        end

        parent = parent.Parent
    end

    return parent == playerGui
end

local function fire(remote, ...)
    if not remote then return false, "Remote is unavailable" end
    local packed = table.pack(pcall(remote.FireServer, remote, ...))
    if not packed[1] then return false, tostring(packed[2]) end
    return true, table.unpack(packed, 2, packed.n)
end

function GameAdapter.new()
    return setmetatable({
        registry = UnitRegistry.new(),
        EntityCaptureTimeout = Config.EntityCaptureTimeout,
        UnitActionRemote = getUnitAction(),
        _claimedEntities = {},
        _inventoryNames = {},
        _pendingEntityActions = {},
    }, GameAdapter)
end

function GameAdapter:GetUnitNameByUuid(uuid)
    if type(uuid) ~= "string" or uuid == "" then return nil end
    local cached = self._inventoryNames[uuid]
    if cached then return cached end
    local list = getInventoryList()
    local entry = list and list:FindFirstChild(uuid)
    local name = entry and readInventoryName(entry) or nil
    if name then self._inventoryNames[uuid] = name end
    return name
end

function GameAdapter:IsUuidEquipped(uuid)
    if type(uuid) ~= "string" or uuid == "" then return false end
    local list = getInventoryList()
    local entry = list and list:FindFirstChild(uuid)
    return entry ~= nil and isInventoryEntryEquipped(entry)
end

function GameAdapter:GetUuidByUnitName(unitName)
    local list = getInventoryList()
    if not list then return nil, "Inventory list is unavailable" end

    -- UUID is player-specific and is intentionally resolved at playback time.
    local equippedUuid = nil
    for _, entry in ipairs(list:GetChildren()) do
        local name = readInventoryName(entry)
        if name then self._inventoryNames[entry.Name] = name end
        if name == unitName and isInventoryEntryEquipped(entry) then
            if equippedUuid then
                return nil, "Multiple equipped copies found: " .. tostring(unitName)
            end
            equippedUuid = entry.Name
        end
    end

    if not equippedUuid then
        return nil, "Unit is not equipped: " .. tostring(unitName)
    end
    return equippedUuid
end

local function entityMatches(entity, unitName)
    if not entity:IsA("Model") or type(unitName) ~= "string" or unitName == "" then
        return false
    end

    local entityName = string.lower(entity.Name)
    local wantedName = string.lower(unitName)
    if string.find(entityName, wantedName, 1, true) then return true end

    local normalizedEntity = entityName:gsub("[^%w]", "")
    local normalizedWanted = wantedName:gsub("[^%w]", "")
    return normalizedWanted ~= ""
        and string.find(normalizedEntity, normalizedWanted, 1, true) ~= nil
end

local function hasHumanoidRootPart(entity)
    return entity:IsA("Model")
        and entity:FindFirstChild("HumanoidRootPart", true) ~= nil
end

function GameAdapter:_snapshotActiveEntities(unitName)
    local result, folder = {}, getEntities()
    if folder then
        for _, entity in ipairs(folder:GetChildren()) do
            if entityMatches(entity, unitName) and hasHumanoidRootPart(entity) then
                result[entity] = true
            end
        end
    end
    return result
end

function GameAdapter:_findActivatedEntity(before, unitName)
    local deadline = os.clock() + self.EntityCaptureTimeout
    repeat
        local folder = getEntities()
        if folder then
            for _, entity in ipairs(folder:GetChildren()) do
                if not before[entity]
                    and not self._claimedEntities[entity]
                    and entityMatches(entity, unitName)
                    and hasHumanoidRootPart(entity) then
                    self._claimedEntities[entity] = true
                    return entity
                end
            end
        end
        RunService.Heartbeat:Wait()
    until os.clock() >= deadline
    return nil
end

function GameAdapter:_bindEntity(label, entity)
    local ok, err = self.registry:Bind(label, entity)
    if not ok then
        return false, err
    end

    local pending = self._pendingEntityActions[entity]
    if pending then
        for _, action in ipairs(pending) do
            action.Pos = label
        end

        self._pendingEntityActions[entity] = nil
    end

    return true
end

function GameAdapter:_recordEntityAction(entity, createAction)
    local label = self.registry:Resolve(entity)
    if label then
        return createAction(label)
    end

    local action = createAction("UNRESOLVED:" .. tostring(entity))
    if not action then
        return nil
    end

    local pending = self._pendingEntityActions[entity]
    if not pending then
        pending = {}
        self._pendingEntityActions[entity] = pending
    end

    pending[#pending + 1] = action
    return action
end

function GameAdapter:InstallHooks(recorder)
    if not (hookmetamethod and getnamecallmethod and setnamecallmethod) then
        warn("[MacroRecorder] required hook functions are unavailable")
        return false
    end

    -- Resolve the remote before installing the hook. Calling FindFirstChild from
    -- inside __namecall would recursively enter this hook while depth is still 0.
    local unitActionRemote = self.UnitActionRemote or getUnitAction()
    if not unitActionRemote then
        warn("[MacroRecorder] UnitAction remote is unavailable")
        return false
    end
    self.UnitActionRemote = unitActionRemote

    local depth = 0
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(instance, ...)
        if depth > 0 then return oldNamecall(instance, ...) end
        local method = getnamecallmethod()
        if (checkcaller and checkcaller()) or method ~= "FireServer" then return oldNamecall(instance, ...) end
        if instance ~= unitActionRemote then return oldNamecall(instance, ...) end
        local args = table.pack(...)
        local command = args[1]

        if command == "Place" then
            local label, before, unitName
            depth = depth + 1
            pcall(function()
                if recorder:IsRecording() then
                    unitName = self:GetUnitNameByUuid(args[2])
                    if unitName and typeof(args[3]) == "Vector3" then
                        label = self.registry:Reserve(unitName)
                        before = self:_snapshotActiveEntities(unitName)
                        recorder:PlaceUnit(unitName, args[3], args[4], label)
                    else
                        warn("[MacroRecorder] cannot resolve inventory UUID " .. tostring(args[2]))
                    end
                end
            end)
            depth = depth - 1
            setnamecallmethod(method)
            local result = oldNamecall(instance, table.unpack(args, 1, args.n))
            if label and before then
                task.spawn(function()
                    local entity = self:_findActivatedEntity(before, unitName)
                    if entity then
                        local ok, err = self:_bindEntity(label, entity)
                        if not ok then warn("[MacroRecorder] " .. err) end
                    else
                        warn("[MacroRecorder] placed entity not found for " .. label)
                    end
                end)
            end
            return result
        end

        local soldEntity = nil
        depth = depth + 1
        pcall(function()
            if command == "Upgrade" and recorder:IsRecording() and typeof(args[2]) == "Instance" then
                self:_recordEntityAction(args[2], function(label) return recorder:UpgradeUnit(label) end)
            elseif command == "Sell" and typeof(args[2]) == "Instance" then
                soldEntity = args[2]
                if recorder:IsRecording() then
                    self:_recordEntityAction(args[2], function(label) return recorder:SellUnit(label) end)
                end
            end
        end)
        depth = depth - 1
        setnamecallmethod(method)
        local result = oldNamecall(instance, table.unpack(args, 1, args.n))
        if soldEntity then
            self.registry:ReleaseEntity(soldEntity)
            self._claimedEntities[soldEntity] = nil
        end
        return result
    end)
    return true
end

function GameAdapter:Dispatch(action, ctx)
    local remote = self.UnitActionRemote
    if not remote or not remote.Parent then
        remote = getUnitAction()
        self.UnitActionRemote = remote
    end
    if action.Type == "PlaceUnit" then
        local uuid, uuidError = self:GetUuidByUnitName(action.Unit)
        if not uuid then return false, uuidError end
        local before = self:_snapshotActiveEntities(action.Unit)
        local label = action.Label or self.registry:Reserve(action.Unit)
        local ok, err = fire(remote, "Place", uuid, ctx.position, tonumber(action.Rotation) or 0)
        if not ok then return false, "Place: " .. tostring(err) end
        local entity = self:_findActivatedEntity(before, action.Unit)
        if not entity then
            return false, "Place succeeded but no matching HumanoidRootPart appeared"
        end
        return self:_bindEntity(label, entity)
    end

    local entity = self.registry:ResolveLabel(action.Pos)
    if not entity then return false, "Unit label not found: " .. tostring(action.Pos) end
    if action.Type == "UpgradeUnit" then return fire(remote, "Upgrade", entity, false) end
    if action.Type == "SellUnit" then
        local ok, err = fire(remote, "Sell", entity)
        if ok then
            self.registry:ReleaseEntity(entity)
            self._claimedEntities[entity] = nil
        end
        return ok, err
    end
    return false, "Unsupported action: " .. tostring(action.Type)
end

function GameAdapter:SetGameSpeed(speed)
    speed = tonumber(speed)
    if speed ~= 1 and speed ~= 2 then return false, "Only x1 and x2 are supported" end
    return fire(getGlobalRemote("GameSpeed"), speed)
end

function GameAdapter:GetRewardPopup()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local viewUnitHud = playerGui and playerGui:FindFirstChild("ViewUnitHud")
    return viewUnitHud and viewUnitHud:FindFirstChild("viewitem") or nil
end

function GameAdapter:IsRewardPopupVisible()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local popup = self:GetRewardPopup()

    return playerGui ~= nil
        and popup ~= nil
        and popup:IsA("GuiObject")
        and isActuallyVisible(popup, playerGui)
end

function GameAdapter:DismissRewardPopup()
    local popup = self:GetRewardPopup()
    if not popup or not popup:IsA("GuiObject") then
        return true
    end

    if not self:IsRewardPopupVisible() then
        return true
    end

    local center = popup.AbsolutePosition + (popup.AbsoluteSize / 2)
    local ok, err = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(
            center.X,
            center.Y,
            0,
            true,
            game,
            0
        )
        RunService.Heartbeat:Wait()
        VirtualInputManager:SendMouseButtonEvent(
            center.X,
            center.Y,
            0,
            false,
            game,
            0
        )
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

function GameAdapter:Replay()
    return fire(getGlobalRemote("StageEnd"), "Replay")
end

function GameAdapter:NextStage()
    return fire(getGlobalRemote("StageEnd"), "Next")
end

function GameAdapter:IsMatchFinished()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return false
    end

    local stageEndGui = playerGui:FindFirstChild("StageEnd")
    local stageEndWindow = stageEndGui
        and stageEndGui:FindFirstChild("StageEnd")

    if not stageEndWindow then
        return false
    end

    if stageEndWindow:IsA("GuiObject") then
        return isActuallyVisible(stageEndWindow, playerGui),
            stageEndWindow:GetFullName()
    end

    if stageEndWindow:IsA("ScreenGui") then
        return stageEndWindow.Enabled, stageEndWindow:GetFullName()
    end

    return false
end

function GameAdapter:WaitForPendingActions(timeout)
    local deadline = os.clock() + (timeout or self.EntityCaptureTimeout)

    while next(self._pendingEntityActions) ~= nil do
        if os.clock() >= deadline then
            return false, "Timed out while resolving rapid unit actions"
        end

        RunService.Heartbeat:Wait()
    end

    return true
end

function GameAdapter:ResetRegistry()
    self.registry:Reset()
    table.clear(self._claimedEntities)
    table.clear(self._pendingEntityActions)
end

return GameAdapter

end)
__bundle_register("src.Macro.UnitRegistry", function(require, _LOADED, __bundle_register, __bundle_modules)
local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
    return setmetatable({
        _counts = {},
        _byEntity = {},
        _byLabel = {},
        _pending = {},
    }, UnitRegistry)
end

function UnitRegistry:Reserve(unitName)
    assert(type(unitName) == "string" and unitName ~= "", "Invalid unit name")
    local number = (self._counts[unitName] or 0) + 1
    self._counts[unitName] = number
    local label = string.format("%s - %d", unitName, number)
    self._pending[label] = true
    return label
end

function UnitRegistry:Bind(label, entity)
    if type(label) ~= "string" or label == "" then return false, "Invalid unit label" end
    if typeof(entity) ~= "Instance" then return false, "Invalid unit entity" end

    local oldLabel = self._byEntity[entity]
    if oldLabel and oldLabel ~= label then return false, "Entity is already bound to " .. oldLabel end
    local oldEntity = self._byLabel[label]
    if oldEntity and oldEntity ~= entity then return false, "Label is already bound to another entity" end

    self._pending[label] = nil
    self._byEntity[entity] = label
    self._byLabel[label] = entity
    return true
end

function UnitRegistry:Resolve(entity) return self._byEntity[entity] end

function UnitRegistry:ResolveLabel(label)
    local entity = self._byLabel[label]
    if entity and entity.Parent then return entity end
    return nil
end

function UnitRegistry:WaitForLabel(entity, timeout)
    local deadline = os.clock() + (timeout or 2)
    repeat
        local label = self:Resolve(entity)
        if label then return label end
        task.wait()
    until os.clock() >= deadline
    return nil
end

function UnitRegistry:ReleaseEntity(entity)
    local label = self._byEntity[entity]
    if not label then return nil end
    self._byEntity[entity] = nil
    self._byLabel[label] = nil
    self._pending[label] = nil
    return label
end

function UnitRegistry:Reset()
    table.clear(self._counts)
    table.clear(self._byEntity)
    table.clear(self._byLabel)
    table.clear(self._pending)
end

return UnitRegistry

end)
__bundle_register("src.Config", function(require, _LOADED, __bundle_register, __bundle_modules)
local Config = {
    ToggleKey = Enum.KeyCode.RightControl,
    FolderName = "PoloskaMacros",
    GameFolderName = "AnimeParadoxX",

    DefaultGameSpeed = 1,
    SupportedSpeeds = { 1, 2 },
    DropdownChevronIcon = "rbxassetid://10709790948",
    FormatVersion = 4,
    TimeBasis = "game_seconds",

    EntityCaptureTimeout = 3,
    MatchEndPollInterval = 0.25,
    WaveWaitTimeout = 300,
    DispatchRetries = 3,
    DispatchRetryDelay = 0.25,
    PositionRandomOffsetMin = 0.001,
    PositionRandomOffsetMax = 0.01,
}

return Config

end)
__bundle_register("src.Macro.Storage", function(require, _LOADED, __bundle_register, __bundle_modules)
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

end)
__bundle_register("src.Macro.Actions", function(require, _LOADED, __bundle_register, __bundle_modules)
local Actions = {}

function Actions.encodePosition(position)
    assert(typeof(position) == "Vector3", "Expected Vector3")
    return string.format("%.9g, %.9g, %.9g", position.X, position.Y, position.Z)
end

function Actions.decodePosition(pos)
    if type(pos) ~= "string" then return nil, "Pos must be a string" end
    local values = {}
    for token in pos:gmatch("[^,%s]+") do
        local value = tonumber(token)
        if not value then return nil, "Pos contains a non-number: " .. token end
        values[#values + 1] = value
    end
    if #values ~= 3 then return nil, ("Vector3 must contain 3 numbers, received %d"):format(#values) end
    return Vector3.new(values[1], values[2], values[3])
end

function Actions.PlaceUnit(unitName, position, rotation, label)
    return {
        Type = "PlaceUnit",
        Unit = unitName,
        Label = label,
        Pos = Actions.encodePosition(position),
        Rotation = tonumber(rotation) or 0,
    }
end

function Actions.UpgradeUnit(label)
    return { Type = "UpgradeUnit", Pos = label }
end

function Actions.SellUnit(label)
    return { Type = "SellUnit", Pos = label }
end

return Actions

end)
__bundle_register("src.Macro.Player", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")
local Config = require("src.Config")
local Storage = require("src.Macro.Storage")
local Actions = require("src.Macro.Actions")

local Player = {}
Player.__index = Player

local positionRng = Random.new()

local function addPositionRandomOffset(cf)
    local minOffset = tonumber(Config.PositionRandomOffsetMin) or 0.001
    local maxOffset = tonumber(Config.PositionRandomOffsetMax) or 0.01
    if minOffset < 0 or maxOffset < minOffset then return cf end

    -- Random direction plus a guaranteed non-zero distance from the saved point.
    local angle = positionRng:NextNumber(0, math.pi * 2)
    local distance = positionRng:NextNumber(minOffset, maxOffset)
    return cf + Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )
end

function Player.new(opts)
    opts = opts or {}
    return setmetatable({
        Playing = false,
        Waiting = false,
        _getWave = opts.GetWave or function() return nil end,
        _dispatch = opts.Dispatch or function() return false, "No dispatcher" end,
        _onStart = opts.OnStart or function() end,
        _session = 0,
    }, Player)
end

local function logicalTargetSeconds(macro, storedSeconds)
    if macro["Time Basis"] == "game_seconds" then
        return storedSeconds
    end
    return storedSeconds * (tonumber(macro["Game Speed"]) or 1)
end

function Player:Play(macro, options)
    if self.Playing then return true, "Already armed" end

    local valid, validationError = Storage.Validate(macro, false)
    if not valid then return false, validationError end

    local list = Storage.ToOrderedList(macro)
    if #list == 0 then return false, "Macro contains no actions" end

    options = options or {}
    local playbackSpeed = tonumber(options.PlaybackSpeed) or tonumber(macro["Game Speed"]) or 1
    local waitForReset = options.WaitForReset == true
    local supported = false
    for _, value in ipairs(Config.SupportedSpeeds) do
        if playbackSpeed == value then
            supported = true
            break
        end
    end
    if not supported then return false, "Unsupported playback speed" end

    local firstWave = Storage.ParseTime(list[1].action.Time)
    if type(firstWave) ~= "number" then return false, "Invalid first action time" end

    self.Playing = true
    self.Waiting = true
    self._session = self._session + 1
    local session = self._session
    local onFinished = options.OnFinished
    local onWaiting = options.OnWaiting
    local onStarted = options.OnStarted
    local onActionPlayed = options.OnActionPlayed

    task.spawn(function()
        local done = false
        local function finish(success, message)
            if done then return end
            done = true
            if self._session == session then
                self.Playing = false
                self.Waiting = false
            end
            if onFinished then onFinished(success, message) end
        end

        if onWaiting then onWaiting(firstWave, self._getWave()) end

        -- AFK mode: if the current match has already passed the macro start wave,
        -- wait for the wave counter to reset, then wait for firstWave.
        local waitStarted = os.clock()
        local currentWave = self._getWave()

        if waitForReset then
            local resetBaseline = currentWave

            while self.Playing and self._session == session do
                currentWave = self._getWave()

                if type(resetBaseline) ~= "number"
                    and type(currentWave) == "number" then
                    resetBaseline = currentWave
                elseif type(resetBaseline) == "number"
                    and type(currentWave) == "number"
                    and currentWave < resetBaseline then
                    break
                end

                if os.clock() - waitStarted > Config.WaveWaitTimeout then
                    finish(false, "Timeout waiting for wave reset")
                    return
                end

                RunService.Heartbeat:Wait()
            end
        end

        while self.Playing and self._session == session do
            currentWave = self._getWave()
            if type(currentWave) == "number" and currentWave <= firstWave then break end
            if os.clock() - waitStarted > Config.WaveWaitTimeout then
                finish(false, "Timeout waiting for the next match")
                return
            end
            RunService.Heartbeat:Wait()
        end

        while self.Playing and self._session == session do
            currentWave = self._getWave()
            if type(currentWave) == "number" and currentWave == firstWave then break end
            if type(currentWave) == "number" and currentWave > firstWave then
                -- The counter jumped over the start wave. Wait for another reset.
                repeat
                    RunService.Heartbeat:Wait()
                    currentWave = self._getWave()
                until not self.Playing or self._session ~= session
                    or (type(currentWave) == "number" and currentWave <= firstWave)
            end
            if os.clock() - waitStarted > Config.WaveWaitTimeout then
                finish(false, "Timeout waiting for macro start wave")
                return
            end
            RunService.Heartbeat:Wait()
        end

        if not self.Playing or self._session ~= session then
            finish(false, "Stopped")
            return
        end

        self.Waiting = false
        self._onStart(playbackSpeed)

        if onStarted then
            local callbackOk, callbackError = pcall(onStarted)
            if not callbackOk then
                warn("[MacroPlayer] start status callback failed:", callbackError)
            end
        end

        currentWave = firstWave
        local waveClock = os.clock()

        for _, entry in ipairs(list) do
            if not self.Playing or self._session ~= session then
                finish(false, "Stopped")
                return
            end

            local action = entry.action
            local targetWave, storedSeconds = Storage.ParseTime(action.Time)
            local targetLogical = logicalTargetSeconds(macro, storedSeconds)
            local actionWaitStarted = os.clock()

            while self.Playing and self._session == session do
                local wave = self._getWave()
                if type(wave) == "number" and wave ~= currentWave then
                    currentWave = wave
                    waveClock = os.clock()
                end

                local elapsedLogical = (os.clock() - waveClock) * playbackSpeed
                local actionIsDue = currentWave > targetWave
                    or (
                        currentWave == targetWave
                        and elapsedLogical >= targetLogical
                    )

                if actionIsDue then
                    break
                end

                if os.clock() - actionWaitStarted > Config.WaveWaitTimeout then
                    finish(false, ("Action #%d: wave wait timeout"):format(entry.index))
                    return
                end
                RunService.Heartbeat:Wait()
            end

            local ctx = {}
            if action.Type == "PlaceUnit" then
                local position, positionError = Actions.decodePosition(action.Pos)
                if not position then
                    finish(false, ("Action #%d: %s"):format(entry.index, positionError))
                    return
                end
                -- Keep the saved macro unchanged, but slightly vary X/Z on playback.
                ctx.position = addPositionRandomOffset(CFrame.new(position)).Position
            end

            local success, dispatchError = false, nil
            for attempt = 1, Config.DispatchRetries do
                local callOk, result, message = pcall(self._dispatch, action, ctx)
                if callOk and result then
                    success = true
                    break
                end
                dispatchError = callOk and message or result
                if attempt < Config.DispatchRetries then
                    task.wait(Config.DispatchRetryDelay * attempt)
                end
            end

            if not success then
                finish(false, ("Action #%d (%s) failed: %s"):format(
                    entry.index,
                    tostring(action.Type),
                    tostring(dispatchError)
                ))
                return
            end

            if onActionPlayed then
                local callbackOk, callbackError = pcall(
                    onActionPlayed,
                    action,
                    entry.index
                )

                if not callbackOk then
                    warn(
                        "[MacroPlayer] action status callback failed:",
                        callbackError
                    )
                end
            end
        end

        finish(true, "Completed")
    end)

    return true
end

function Player:Stop()
    self.Playing = false
    self.Waiting = false
    self._session = self._session + 1
end

function Player:IsPlaying() return self.Playing end
function Player:IsWaiting() return self.Waiting end

return Player

end)
__bundle_register("src.Macro.Recorder", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")
local Config = require("src.Config")
local Actions = require("src.Macro.Actions")

local Recorder = {}
Recorder.__index = Recorder

local function isSupportedSpeed(speed)
    for _, value in ipairs(Config.SupportedSpeeds) do
        if speed == value then return true end
    end
    return false
end

function Recorder.new(opts)
    opts = opts or {}
    return setmetatable({
        Recording = false,
        Actions = {},
        GameSpeed = Config.DefaultGameSpeed,
        _getWave = opts.GetWave or function() return nil end,
        _wave = nil,
        _waveClock = 0,
        _conn = nil,
    }, Recorder)
end

function Recorder:SetGameSpeed(speed)
    speed = tonumber(speed)
    if not isSupportedSpeed(speed) then return false, "Unsupported speed" end
    if self.Recording then return false, "Cannot change speed while recording" end
    self.GameSpeed = speed
    return true
end

function Recorder:_timeString()
    local logicalSeconds = (os.clock() - self._waveClock) * self.GameSpeed
    return string.format("%d %.6f", self._wave, logicalSeconds)
end

function Recorder:Start()
    if self.Recording then return false, "Already recording" end
    local wave = self._getWave()
    if type(wave) ~= "number" then return false, "Current wave is unavailable" end
    self.Recording = true
    self.Actions = {}
    self._wave = wave
    self._waveClock = os.clock()
    self._conn = RunService.Heartbeat:Connect(function()
        local current = self._getWave()
        if type(current) == "number" and current ~= self._wave then
            self._wave = current
            self._waveClock = os.clock()
        end
    end)
    return true
end

function Recorder:Record(action)
    if not self.Recording then return nil end

    action.Time = self:_timeString()
    self.Actions[#self.Actions + 1] = action
    return action
end

function Recorder:PlaceUnit(name, position, rotation, label)
    return self:Record(Actions.PlaceUnit(name, position, rotation, label))
end
function Recorder:UpgradeUnit(label) return self:Record(Actions.UpgradeUnit(label)) end
function Recorder:SellUnit(label) return self:Record(Actions.SellUnit(label)) end

function Recorder:Stop()
    if not self.Recording then return nil, "Not recording" end
    self.Recording = false
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
    return self:GetMacro()
end

function Recorder:GetMacro()
    local macro = {
        ["Format Version"] = Config.FormatVersion,
        ["Time Basis"] = Config.TimeBasis,
        ["Game Speed"] = self.GameSpeed,
    }
    for index, action in ipairs(self.Actions) do macro[tostring(index)] = action end
    return macro
end

function Recorder:IsRecording() return self.Recording end
return Recorder

end)
return __bundle_require("__root")