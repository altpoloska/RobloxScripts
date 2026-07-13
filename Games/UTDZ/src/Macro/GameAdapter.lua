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
