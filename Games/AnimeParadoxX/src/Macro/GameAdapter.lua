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
