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

local Config = require("Config")
local Recorder = require("Macro.Recorder")
local Player = require("Macro.Player")
local Storage = require("Macro.Storage")
local GameAdapter = require("Macro.GameAdapter")
local Interface = require("UI.Interface")

local function GetWave()
    local ok, text = pcall(function()
        return LocalPlayer.PlayerGui.GameUI.HUD.Upper.WaveInformations.Container.Wave.Text
    end)
    if not ok or type(text) ~= "string" then return nil end
    return tonumber(text:match("Wave%s*(%d+)"))
end

local function getHotbarSlots()
    local ok, folder = pcall(function()
        return LocalPlayer.PlayerGui.GameUI.HUD.Bottom.Hotbar.Units
    end)
    if not ok or not folder then return {} end

    local slots = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("GuiObject") then slots[#slots + 1] = child end
    end
    table.sort(slots, function(a, b)
        local pa, pb = a.AbsolutePosition, b.AbsolutePosition
        if math.abs(pa.Y - pb.Y) > 1 then return pa.Y < pb.Y end
        return pa.X < pb.X
    end)
    return slots
end

local function getHotbar()
    local names = {}
    for index, slot in ipairs(getHotbarSlots()) do
        local name = false
        if slot.Name == "ContainerBig" then
            local ok, text = pcall(function()
                return slot.Unit.UnitInfomation.RightInfos.UnitName.Text
            end)
            if ok and type(text) == "string" and text ~= "" then name = text end
        end
        names[index] = name
    end
    return names
end

local function GetHotbarUnitName(slot)
    local name = getHotbar()[slot]
    return type(name) == "string" and name or nil
end

local function GetSlotByUnitName(unitName)
    for slot, name in ipairs(getHotbar()) do
        if name == unitName then return slot end
    end
    return nil
end

local function getUnitsFolder()
    local ignore = workspace:FindFirstChild("Ignore")
    return ignore and ignore:FindFirstChild("Units") or nil
end

local function ListPlacedUnitIds()
    local folder, ids = getUnitsFolder(), {}
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if tonumber(child.Name) == nil then ids[#ids + 1] = child.Name end
        end
    end
    return ids
end

local adapter = GameAdapter.new({
    GetHotbarUnitName = GetHotbarUnitName,
    GetSlotByUnitName = GetSlotByUnitName,
    ListPlacedUnitIds = ListPlacedUnitIds,
})

local recorder = Recorder.new({ GetWave = GetWave })
local player = Player.new({
    GetWave = GetWave,
    Dispatch = function(action, ctx) return adapter:Dispatch(action, ctx) end,
    OnStart = function() adapter:ResetRegistry() end,
})
adapter:InstallHooks(recorder)

local function getMissionResult()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local gameUI = pg and pg:FindFirstChild("GameUI")
    return gameUI and gameUI:FindFirstChild("MissionResultFrameNew") or nil
end

local function isActuallyVisible(gui)
    if not gui:IsA("GuiObject") or not gui.Visible then return false end
    if gui.AbsoluteSize.X <= 0 or gui.AbsoluteSize.Y <= 0 then return false end
    local parent = gui.Parent
    while parent and parent ~= LocalPlayer.PlayerGui do
        if parent:IsA("GuiObject") and not parent.Visible then return false end
        parent = parent.Parent
    end
    return true
end

local function visiblePage3Buttons()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local finished = pg and pg:FindFirstChild("Finished")
    local page3 = finished and finished:FindFirstChild("Page3")
    local buttons = {}
    if not page3 then return buttons end
    for _, item in ipairs(page3:GetDescendants()) do
        if item:IsA("ImageLabel") and isActuallyVisible(item) then
            buttons[#buttons + 1] = item
        end
    end
    return buttons
end

local automation = {}
function automation.VoteReplay() return adapter:VoteReplay() end
function automation.VoteNext() return adapter:VoteNext() end
function automation.AutoStart() return adapter:AutoStart() end
function automation.Leave() return adapter:ToLobby() end
function automation.ResetPlayback() adapter:ResetRegistry() end

function automation.WaitForResultButtons(actionName, timeout)
    local deadline = os.clock() + (timeout or Config.ReadyTimeout)
    local wanted = actionName and string.lower(actionName) or nil
    repeat
        local buttons = visiblePage3Buttons()
        for _, button in ipairs(buttons) do
            local lowerName = string.lower(button.Name)
            if not wanted or string.find(lowerName, wanted, 1, true) then
                return true, button.Name
            end
        end
        -- Page3 is ready even if the game renamed the individual ImageLabels.
        if #buttons > 0 then return true, buttons[1].Name end
        task.wait(0.1)
    until os.clock() >= deadline
    return false, "Visible ImageLabel buttons were not found in Finished.Page3"
end

function automation.WaitForMissionClosed(timeout)
    local deadline = os.clock() + (timeout or Config.ReadyTimeout)
    repeat
        local result = getMissionResult()
        if result and not result.Enabled then return true end
        task.wait(0.2)
    until os.clock() >= deadline
    return false, "MissionResultFrameNew did not close"
end

function automation.OnFinishedChanged(callback)
    task.spawn(function()
        local pg = LocalPlayer:WaitForChild("PlayerGui", 30)
        local gameUI = pg and pg:WaitForChild("GameUI", 60)
        local result = gameUI and gameUI:WaitForChild("MissionResultFrameNew", 60)
        if not result then
            warn("[MacroRecorder] GameUI.MissionResultFrameNew not found")
            return
        end
        result:GetPropertyChangedSignal("Enabled"):Connect(function()
            callback(result.Enabled)
        end)
        if result.Enabled then callback(true) end
    end)
end

Interface.new({
    PoloskaLib = PoloskaLib,
    Config = Config,
    Storage = Storage,
    Recorder = recorder,
    Player = player,
    Automation = automation,
})

end)
__bundle_register("UI.Interface", function(require, _LOADED, __bundle_register, __bundle_modules)
local Interface = {}

function Interface.new(deps)
    local lib, Config, Storage = deps.PoloskaLib, deps.Config, deps.Storage
    local recorder, player, automation = deps.Recorder, deps.Player, deps.Automation

    local selectedName = nil
    local selectedSpeed = Config.DefaultGameSpeed
    local endAction = nil
    local autoToggles = {}
    local handlingFinish = false
    local playEnabled = false
    local overwriteConfirmUntil = 0
    local waitForResultAfterRecord = false

    local window = lib:Create({
        Name = "Poloska Macro Recorder",
        Size = UDim2.fromOffset(660, 480),
        ToggleKey = Config.ToggleKey,
    })

    local function notify(title, text, duration)
        window:Notification({ Title = title, Text = text, Duration = duration or 3 })
    end

    local function countActions(macro)
        return #Storage.ToOrderedList(macro)
    end

    local mainTab = window:Tab({ Name = "Main" })
    mainTab:Section("AFK playback: persistent while Play Macro is enabled")
    mainTab:Section("End of game")

    local function makeAuto(name, key)
        local toggle
        toggle = mainTab:Toggle({
            Name = name,
            StartingState = false,
            Callback = function(state)
                if state then
                    endAction = key
                    for otherKey, other in pairs(autoToggles) do
                        if otherKey ~= key then other:Set(false) end
                    end
                    notify("AFK", name .. " enabled", 2)
                elseif endAction == key then
                    endAction = nil
                end
            end,
        })
        autoToggles[key] = toggle
    end

    makeAuto("Auto Replay", "replay")
    makeAuto("Auto Vote Next", "next")
    makeAuto("Auto Leave", "leave")
    mainTab:Credit({ Name = "polosa__", Description = "PoloskaLib Macro Recorder v2.3" })

    local macroTab = window:Tab({ Name = "Macro" })
    local status = macroTab:Section("AFK: select or create a macro")
    local dropdown

    local function refresh()
        dropdown:Clear()
        dropdown:AddItems(Storage.List())
    end

    local function startArmedPlayback()
        if not playEnabled then return false end
        if not selectedName or recorder:IsRecording() then return false end
        if player:IsPlaying() then return true end

        local macro, loadError = Storage.Load(selectedName)
        if not macro then
            status.Text = "Load failed: " .. tostring(loadError)
            return false
        end

        if countActions(macro) == 0 then
            status.Text = "Selected empty macro: " .. selectedName
            return false
        end

        local ok, playError = player:Play(macro, {
            PlaybackSpeed = selectedSpeed,
            OnWaiting = function(firstWave, currentWave)
                status.Text = ("AFK armed: waiting for wave %d (current %s)"):format(
                    firstWave,
                    tostring(currentWave)
                )
            end,
            OnFinished = function(success, message)
                if success then
                    status.Text = "Macro completed; waiting for mission result"
                elseif message ~= "Stopped" then
                    status.Text = "Playback stopped: " .. tostring(message)
                    notify("Playback", tostring(message), 5)
                end
            end,
        })

        if not ok then
            status.Text = "Cannot arm: " .. tostring(playError)
            return false
        end
        return true
    end

    dropdown = macroTab:Dropdown({
        Name = "Select macro",
        Items = Storage.List(),
        StartingText = "Select a macro...",
        Callback = function(item)
            local name = typeof(item) == "table" and item[1] or item
            if not name or name == "" then return end

            local macro, loadError = Storage.Load(name)
            if not macro then
                notify("Storage", tostring(loadError))
                return
            end

            player:Stop()
            automation.ResetPlayback()
            selectedName = name
            waitForResultAfterRecord = false

            if countActions(macro) == 0 then
                status.Text = "Selected empty macro: " .. name
            else
                status.Text = ("Selected: %s (%d actions); AFK armed"):format(
                    name,
                    countActions(macro)
                )
                startArmedPlayback()
            end
        end,
    })

    macroTab:Button({ Name = "Refresh list", Callback = refresh })

    macroTab:Textbox({
        Name = "New macro",
        Placeholder = "macro name",
        Callback = function(text)
            local ok, result = Storage.CreateEmpty(text, selectedSpeed)
            if not ok then
                notify("Storage", tostring(result))
                return
            end

            player:Stop()
            automation.ResetPlayback()
            selectedName = result
            waitForResultAfterRecord = false
            refresh()
            status.Text = "Created and selected empty macro: " .. selectedName
            notify("Storage", selectedName .. " added to dropdown", 2)
        end,
    })

    macroTab:Dropdown({
        Name = "Current game speed",
        Items = { "x1", "x1.5" },
        StartingText = "x" .. tostring(selectedSpeed),
        Callback = function(item)
            local value = typeof(item) == "table" and item[1] or item
            selectedSpeed = value == "x1.5" and 1.5 or 1
            if not recorder:IsRecording() then recorder:SetGameSpeed(selectedSpeed) end

            if selectedName and player:IsPlaying() then
                player:Stop()
                startArmedPlayback()
            end
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
            if suppressRecordCallback then return end

            if state then
                if not selectedName then
                    notify("Macro", "Select or create a macro")
                    setRecordToggle(false)
                    return
                end

                local oldMacro, loadError = Storage.Load(selectedName)
                if not oldMacro then
                    notify("Storage", tostring(loadError))
                    setRecordToggle(false)
                    return
                end

                local oldCount = countActions(oldMacro)
                if oldCount > 0 and os.clock() > overwriteConfirmUntil then
                    overwriteConfirmUntil = os.clock() + 8
                    notify(
                        "Overwrite warning",
                        ("%s already contains %d actions. Enable Record again within 8 seconds to overwrite it."):format(
                            selectedName,
                            oldCount
                        ),
                        8
                    )
                    status.Text = "Recording cancelled: confirmation required"
                    setRecordToggle(false)
                    return
                end

                overwriteConfirmUntil = 0
                player:Stop()
                automation.ResetPlayback()
                recorder:SetGameSpeed(selectedSpeed)
                local ok, recordError = recorder:Start()
                if not ok then
                    notify("Macro", tostring(recordError))
                    setRecordToggle(false)
                    return
                end

                waitForResultAfterRecord = false
                status.Text = ("Recording %s at x%s"):format(selectedName, selectedSpeed)
            elseif recorder:IsRecording() then
                local macro = recorder:Stop()
                local ok, saveError = Storage.Save(selectedName, macro)
                if not ok then
                    notify("Storage", tostring(saveError))
                    status.Text = "Save failed"
                    return
                end

                refresh()
                waitForResultAfterRecord = true
                status.Text = ("Saved %d actions; AFK armed for the next match"):format(
                    countActions(macro)
                )
                notify("AFK", "Recording saved. You can leave it running.", 3)
            end
        end,
    })

    macroTab:Keybind({
        Name = "Toggle recording",
        Keybind = Config.RecordKey,
        Callback = function()
            setRecordToggle(not recorder:IsRecording())
            if not recorder:IsRecording() then
                -- Set() was suppressed above, so invoke the intended transition.
                recordToggle:Set(true)
            else
                recordToggle:Set(false)
            end
        end,
    })

    macroTab:Section("Persistent playback")

    local playToggle
    playToggle = macroTab:Toggle({
        Name = "Play macro",
        StartingState = false,
        Callback = function(state)
            playEnabled = state

            if state then
                if not selectedName then
                    status.Text = "Play enabled: select or create a macro"
                    notify("Macro", "Play is enabled; select a macro", 3)
                    return
                end

                local macro, loadError = Storage.Load(selectedName)
                if not macro then
                    status.Text = "Load failed: " .. tostring(loadError)
                    notify("Storage", tostring(loadError), 4)
                    return
                end

                if countActions(macro) == 0 then
                    status.Text = "Play enabled; selected macro is empty"
                    return
                end

                status.Text = "Play enabled; persistent AFK playback armed"
                startArmedPlayback()
            else
                player:Stop()
                automation.ResetPlayback()
                status.Text = "Play disabled; macro remote events are stopped"
            end
        end,
    })

    macroTab:Keybind({
        Name = "Toggle persistent playback",
        Keybind = Config.PlayKey,
        Callback = function()
            playToggle:Set(not playEnabled)
        end,
    })

    automation.OnFinishedChanged(function(enabled)
        if not enabled then
            handlingFinish = false
            return
        end
        if handlingFinish then return end
        handlingFinish = true

        player:Stop()
        automation.ResetPlayback()
        waitForResultAfterRecord = false
        status.Text = "Mission result detected; playback reset"

        task.spawn(function()
            local wantedButton = nil
            if endAction == "replay" then wantedButton = "replay" end
            if endAction == "next" then wantedButton = "next" end
            if endAction == "leave" then wantedButton = "lobby" end

            if endAction then
                local buttonsReady, buttonInfo = automation.WaitForResultButtons(
                    wantedButton,
                    Config.ReadyTimeout
                )
                if not buttonsReady then
                    notify("Automation", tostring(buttonInfo), 5)
                else
                    local actionOk, actionError
                    if endAction == "replay" then
                        actionOk, actionError = automation.VoteReplay()
                    elseif endAction == "next" then
                        actionOk, actionError = automation.VoteNext()
                    elseif endAction == "leave" then
                        actionOk, actionError = automation.Leave()
                    end
                    if actionOk == false then
                        notify("Automation", tostring(actionError), 5)
                    end
                end
            end

            -- PlayMacro is permanently armed. It now waits through the old wave,
            -- the reset, and the first wave stored in the macro.
            startArmedPlayback()

            if endAction == "replay" or endAction == "next" then
                local closed = automation.WaitForMissionClosed(Config.ReadyTimeout)
                if closed then automation.AutoStart() end
            end
        end)
    end)

    return { window = window, recorder = recorder, player = player }
end

return Interface

end)
__bundle_register("Macro.GameAdapter", function(require, _LOADED, __bundle_register, __bundle_modules)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require("Config")
local UnitRegistry = require("Macro.UnitRegistry")

local GameAdapter = {}
GameAdapter.__index = GameAdapter

local knitFolder
local function getKnitFolder()
    if knitFolder and knitFolder.Parent then return knitFolder end
    local packages = ReplicatedStorage:WaitForChild("Packages", 10)
    local index = packages and packages:WaitForChild("_Index", 10)
    if not index then return nil end
    for _, item in ipairs(index:GetDescendants()) do
        if item.Name == "knit" and item:FindFirstChild("Services") then knitFolder = item; return item end
    end
    return nil
end

local function findRemote(kind, serviceName, remoteName)
    local knit = getKnitFolder()
    local services = knit and knit:FindFirstChild("Services")
    local service = services and services:FindFirstChild(serviceName)
    local folder = service and service:FindFirstChild(kind)
    local remote = folder and folder:FindFirstChild(remoteName)
    if not remote then warn(("[MacroRecorder] missing remote %s.%s.%s"):format(serviceName, kind, remoteName)) end
    return remote
end

local function invoke(remote, ...)
    if not remote then return false, "Remote is unavailable" end
    local packed = table.pack(pcall(remote.InvokeServer, remote, ...))
    if not packed[1] then return false, tostring(packed[2]) end
    return true, table.unpack(packed, 2, packed.n)
end

function GameAdapter.new(opts)
    opts = opts or {}
    local self = setmetatable({}, GameAdapter)
    self.registry = UnitRegistry.new()
    self.GetHotbarUnitName = opts.GetHotbarUnitName or function() return nil end
    self.GetSlotByUnitName = opts.GetSlotByUnitName or function() return nil end
    self.ListPlacedUnitIds = opts.ListPlacedUnitIds or function() return {} end
    self.UnitCaptureTimeout = Config.UnitCaptureTimeout
    self.PendingResolveTimeout = Config.PendingResolveTimeout
    self._claimedUuids = {}
    self.remotes = {
        Vote = findRemote("RF", "WaveService", "Vote"),
        PlaceUnit = findRemote("RF", "TowerService", "PlaceUnit"),
        UpgradeUnit = findRemote("RF", "TowerService", "UpgradeUnit"),
        SellUnit = findRemote("RF", "TowerService", "SellUnit"),
        ChangePriority = findRemote("RF", "TowerService", "ChangePriority"),
        VoteReplay = findRemote("RE", "WaveService", "VoteReplay"),
        VoteNext = findRemote("RE", "WaveService", "NextMap"),
        ToLobby = findRemote("RE", "WaveService", "ToLobby"),
    }
    return self
end

function GameAdapter:_snapshotIds()
    local result = {}
    for _, id in ipairs(self.ListPlacedUnitIds()) do result[id] = true end
    return result
end

function GameAdapter:_findNewId(before)
    local deadline = os.clock() + self.UnitCaptureTimeout
    repeat
        for _, id in ipairs(self.ListPlacedUnitIds()) do
            if not before[id] and not self._claimedUuids[id] then
                self._claimedUuids[id] = true
                return id
            end
        end
        RunService.Heartbeat:Wait()
    until os.clock() >= deadline
    return nil
end

function GameAdapter:_recordUnitAction(uuid, createAction)
    local label = self.registry:Resolve(uuid)
    local action = createAction(label or ("UNRESOLVED:" .. tostring(uuid)))
    if label or not action then return action end
    task.spawn(function()
        local resolved = self.registry:WaitForLabel(uuid, self.PendingResolveTimeout)
        if resolved then action.Pos = resolved
        else warn("[MacroRecorder] unresolved unit UUID: " .. tostring(uuid)) end
    end)
    return action
end

function GameAdapter:InstallHooks(recorder)
    if not (hookmetamethod and getnamecallmethod and setnamecallmethod) then
        warn("[MacroRecorder] required hook functions are unavailable")
        return false
    end

    local remotes, registry, depth = self.remotes, self.registry, 0
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(instance, ...)
        if depth > 0 then return oldNamecall(instance, ...) end
        local method = getnamecallmethod()
        if (checkcaller and checkcaller()) or method ~= "InvokeServer" then return oldNamecall(instance, ...) end
        local args = table.pack(...)

        if instance == remotes.PlaceUnit then
            local unitName, label, before
            depth = depth + 1
            pcall(function()
                unitName = self.GetHotbarUnitName(args[1])
                before = self:_snapshotIds()
                if recorder:IsRecording() then
                    if unitName then
                        label = registry:Reserve(unitName)
                        recorder:PlaceUnit(unitName, args[2], label)
                    else
                        warn("[MacroRecorder] cannot resolve hotbar slot " .. tostring(args[1]))
                    end
                end
            end)
            depth = depth - 1
            setnamecallmethod(method)
            local result = oldNamecall(instance, table.unpack(args, 1, args.n))
            task.spawn(function()
                local uuid
                if typeof(result) == "string" and result ~= "" then uuid = result; self._claimedUuids[uuid] = true
                elseif before then uuid = self:_findNewId(before) end
                if label and uuid then
                    local ok, err = registry:Bind(label, uuid)
                    if not ok then warn("[MacroRecorder] " .. err) end
                elseif label then warn("[MacroRecorder] UUID not found for " .. label) end
            end)
            return result
        end

        depth = depth + 1
        pcall(function()
            if instance == remotes.UpgradeUnit and recorder:IsRecording() then
                self:_recordUnitAction(args[1], function(label) return recorder:UpgradeUnit(label) end)
            elseif instance == remotes.SellUnit and recorder:IsRecording() then
                self:_recordUnitAction(args[1], function(label) return recorder:SellUnit(label) end)
            elseif instance == remotes.ChangePriority and recorder:IsRecording() then
                self:_recordUnitAction(args[1], function(label) return recorder:ChangePriority(label, args[2]) end)
            elseif instance == remotes.Vote and recorder:IsRecording() then recorder:VoteSkip() end
        end)
        depth = depth - 1
        setnamecallmethod(method)
        return oldNamecall(instance, table.unpack(args, 1, args.n))
    end)
    return true
end

function GameAdapter:Dispatch(action, ctx)
    local t, remotes, registry = action.Type, self.remotes, self.registry
    if t == "PlaceUnit" then
        local slot = self.GetSlotByUnitName(action.Unit)
        if not slot then return false, "Unit is absent from hotbar: " .. tostring(action.Unit) end
        local before = self:_snapshotIds()
        local label = action.Label or registry:Reserve(action.Unit)
        local ok, result = invoke(remotes.PlaceUnit, slot, ctx.cframe)
        if not ok then return false, "PlaceUnit: " .. tostring(result) end
        local uuid
        if typeof(result) == "string" and result ~= "" then uuid = result; self._claimedUuids[uuid] = true
        else uuid = self:_findNewId(before) end
        if not uuid then return false, "PlaceUnit succeeded but UUID was not found" end
        return registry:Bind(label, uuid)
    elseif t == "VoteSkip" then
        return invoke(remotes.Vote, true)
    end

    local uuid = registry:ResolveLabel(action.Pos)
    if not uuid then return false, "Unit label not found: " .. tostring(action.Pos) end
    if t == "UpgradeUnit" then return invoke(remotes.UpgradeUnit, uuid) end
    if t == "SellUnit" then return invoke(remotes.SellUnit, uuid) end
    if t == "ChangePriority" then return invoke(remotes.ChangePriority, uuid, action.Prio) end
    return false, "Unsupported action: " .. tostring(t)
end

local function fire(remote)
    if not remote then return false, "Remote is unavailable" end
    local ok, err = pcall(remote.FireServer, remote)
    return ok, ok and nil or tostring(err)
end

function GameAdapter:VoteReplay() return fire(self.remotes.VoteReplay) end
function GameAdapter:VoteNext() return fire(self.remotes.VoteNext) end
function GameAdapter:ToLobby() return fire(self.remotes.ToLobby) end
function GameAdapter:AutoStart() return invoke(self.remotes.Vote, true) end
function GameAdapter:ResetRegistry() self.registry:Reset(); table.clear(self._claimedUuids) end
return GameAdapter

end)
__bundle_register("Macro.UnitRegistry", function(require, _LOADED, __bundle_register, __bundle_modules)
local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
    return setmetatable({
        _counts = {},
        _byUuid = {},
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

function UnitRegistry:Bind(label, uuid)
    if type(label) ~= "string" or label == "" then
        return false, "Invalid unit label"
    end
    if type(uuid) ~= "string" or uuid == "" then
        return false, "Invalid unit UUID"
    end

    local oldLabel = self._byUuid[uuid]
    if oldLabel and oldLabel ~= label then
        return false, "UUID is already bound to " .. oldLabel
    end

    local oldUuid = self._byLabel[label]
    if oldUuid and oldUuid ~= uuid then
        return false, "Label is already bound to another UUID"
    end

    self._pending[label] = nil
    self._byUuid[uuid] = label
    self._byLabel[label] = uuid
    return true
end

function UnitRegistry:Resolve(uuid)
    return self._byUuid[uuid]
end

function UnitRegistry:ResolveLabel(label)
    return self._byLabel[label]
end

function UnitRegistry:WaitForLabel(uuid, timeout)
    local deadline = os.clock() + (timeout or 2)
    repeat
        local label = self:Resolve(uuid)
        if label then return label end
        task.wait()
    until os.clock() >= deadline
    return nil
end

function UnitRegistry:Reset()
    table.clear(self._counts)
    table.clear(self._byUuid)
    table.clear(self._byLabel)
    table.clear(self._pending)
end

return UnitRegistry

end)
__bundle_register("Config", function(require, _LOADED, __bundle_register, __bundle_modules)
local Config = {
    ToggleKey = Enum.KeyCode.RightControl,
    RecordKey = Enum.KeyCode.F6,
    PlayKey = Enum.KeyCode.F7,
    FolderName = "PoloskaMacros",

    DefaultGameSpeed = 1.5,
    SupportedSpeeds = { 1, 1.5 },
    FormatVersion = 2,
    TimeBasis = "game_seconds",

    UnitCaptureTimeout = 2,
    PendingResolveTimeout = 3,
    WaveWaitTimeout = 300,
    ReadyTimeout = 60,
    DispatchRetries = 3,
    DispatchRetryDelay = 0.25,
}

return Config

end)
__bundle_register("Macro.Storage", function(require, _LOADED, __bundle_register, __bundle_modules)
local HttpService = game:GetService("HttpService")
local Config = require("Config")
local Actions = require("Macro.Actions")

local Storage = {}

local SUPPORTED = {
    PlaceUnit = true,
    UpgradeUnit = true,
    SellUnit = true,
    ChangePriority = true,
    VoteSkip = true,
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
            local cf, cfError = Actions.decodeCFrame(action.Pos)
            if not cf then return false, ("Action #%d: %s"):format(entry.index, cfError) end
        elseif action.Type ~= "VoteSkip" then
            if type(action.Pos) ~= "string" or action.Pos == "" then
                return false, ("Action #%d: missing unit label"):format(entry.index)
            end
            if action.Pos:sub(1, 11) == "UNRESOLVED:" then
                return false, ("Action #%d: unit UUID was not resolved"):format(entry.index)
            end
        end

        if action.Type == "ChangePriority" and type(action.Prio) ~= "number" then
            return false, ("Action #%d: invalid priority"):format(entry.index)
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

local function ensureFolder()
    if typeof(makefolder) == "function" and typeof(isfolder) == "function"
        and not isfolder(Config.FolderName) then
        local ok, err = pcall(makefolder, Config.FolderName)
        if not ok then return false, tostring(err) end
    end
    return true
end

function Storage.Exists(name)
    local safeName = Storage.SanitizeName(name)
    if not safeName or typeof(isfile) ~= "function" then return false end
    return isfile(Config.FolderName .. "/" .. safeName .. ".json")
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
    local writeOk, writeError = pcall(writefile, Config.FolderName .. "/" .. safeName .. ".json", json)
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
    local path = Config.FolderName .. "/" .. safeName .. ".json"
    if typeof(isfile) == "function" and not isfile(path) then return nil, "File not found" end
    local ok, text = pcall(readfile, path)
    if not ok then return nil, "Read failed: " .. tostring(text) end
    return Storage.Deserialize(text)
end

function Storage.List()
    if typeof(listfiles) ~= "function" then return {} end
    ensureFolder()
    local ok, paths = pcall(listfiles, Config.FolderName)
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
__bundle_register("Macro.Actions", function(require, _LOADED, __bundle_register, __bundle_modules)
local Actions = {}

function Actions.encodeCFrame(cf)
    assert(typeof(cf) == "CFrame", "Expected CFrame")
    local values = { cf:GetComponents() }
    for i, value in ipairs(values) do
        values[i] = string.format("%.9g", value)
    end
    return table.concat(values, ", ")
end

function Actions.decodeCFrame(pos)
    if type(pos) ~= "string" then
        return nil, "Pos must be a string"
    end

    local values = {}
    for token in pos:gmatch("[^,%s]+") do
        local value = tonumber(token)
        if not value then
            return nil, "Pos contains a non-number: " .. token
        end
        values[#values + 1] = value
    end

    if #values ~= 12 then
        return nil, ("CFrame must contain 12 numbers, received %d"):format(#values)
    end

    return CFrame.new(table.unpack(values))
end

function Actions.PlaceUnit(unitName, cframe, label)
    return {
        Type = "PlaceUnit",
        Unit = unitName,
        Label = label,
        Pos = Actions.encodeCFrame(cframe),
    }
end

function Actions.UpgradeUnit(label)
    return { Type = "UpgradeUnit", Pos = label }
end

function Actions.ChangePriority(label, priority)
    return { Type = "ChangePriority", Prio = priority, Pos = label }
end

function Actions.UseAbility(label, abilityIndex)
    return { Type = "UseAbility", Abi = abilityIndex, Pos = label }
end

function Actions.ConfirmTowerLink(label)
    return { Type = "ConfirmTowerLink", Pos = label }
end

function Actions.SellUnit(label)
    return { Type = "SellUnit", Pos = label }
end

function Actions.VoteSkip()
    return { Type = "VoteSkip" }
end

return Actions

end)
__bundle_register("Macro.Player", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")
local Config = require("Config")
local Storage = require("Macro.Storage")
local Actions = require("Macro.Actions")

local Player = {}
Player.__index = Player

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
    if playbackSpeed ~= 1 and playbackSpeed ~= 1.5 then
        return false, "Unsupported playback speed"
    end

    local firstWave = Storage.ParseTime(list[1].action.Time)
    if type(firstWave) ~= "number" then return false, "Invalid first action time" end

    self.Playing = true
    self.Waiting = true
    self._session = self._session + 1
    local session = self._session
    local onFinished = options.OnFinished
    local onWaiting = options.OnWaiting

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
        self._onStart()

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

                if currentWave > targetWave then
                    finish(false, ("Action #%d missed wave %d"):format(entry.index, targetWave))
                    return
                end

                local elapsedLogical = (os.clock() - waveClock) * playbackSpeed
                if currentWave == targetWave and elapsedLogical >= targetLogical then break end

                if os.clock() - actionWaitStarted > Config.WaveWaitTimeout then
                    finish(false, ("Action #%d: wave wait timeout"):format(entry.index))
                    return
                end
                RunService.Heartbeat:Wait()
            end

            local ctx = {}
            if action.Type == "PlaceUnit" then
                local cf, cfError = Actions.decodeCFrame(action.Pos)
                if not cf then
                    finish(false, ("Action #%d: %s"):format(entry.index, cfError))
                    return
                end
                ctx.cframe = cf
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
__bundle_register("Macro.Recorder", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")
local Config = require("Config")
local Actions = require("Macro.Actions")

local Recorder = {}
Recorder.__index = Recorder

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
    if speed ~= 1 and speed ~= 1.5 then return false, "Unsupported speed" end
    if self.Recording then return false, "Cannot change speed while recording" end
    self.GameSpeed = speed
    return true
end

-- V2 stores logical game seconds. At x1.5, 10 real seconds become 15 game seconds.
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

function Recorder:PlaceUnit(name, cf, label) return self:Record(Actions.PlaceUnit(name, cf, label)) end
function Recorder:UpgradeUnit(label) return self:Record(Actions.UpgradeUnit(label)) end
function Recorder:ChangePriority(label, priority) return self:Record(Actions.ChangePriority(label, priority)) end
function Recorder:SellUnit(label) return self:Record(Actions.SellUnit(label)) end
function Recorder:VoteSkip() return self:Record(Actions.VoteSkip()) end

function Recorder:Stop()
    if not self.Recording then return nil, "Not recording" end
    self.Recording = false
    if self._conn then self._conn:Disconnect(); self._conn = nil end
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