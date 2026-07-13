local settings = require("src/settings")
local utils = require("src/utils")

local network = {}
local oldNamecall
local isActive = false
local initialized = false
local recordingEnabled = true
local onPacket = nil
local decoder = nil
local callDepth = 0

-- Unblocked calls are processed in batches outside __namecall. Using indices
-- avoids table.remove(1), which would shift the entire queue on every packet.
local pendingPackets = {}
local queueHead = 1
local queueTail = 0
local drainScheduled = false

function network.setDecoder(callback)
    assert(callback == nil or type(callback) == "function", "decoder must be a function or nil")
    decoder = callback
end

function network.setRecording(value)
    recordingEnabled = value ~= false
end

local function captureCallMetadata()
    local callingScript
    if settings.captureCallingScript and type(getcallingscript) == "function" then
        local ok, scriptValue = pcall(getcallingscript)
        if ok and scriptValue ~= nil then
            if typeof(scriptValue) == "Instance" then
                local pathOk, fullName = pcall(function()
                    return scriptValue:GetFullName()
                end)
                callingScript = pathOk and fullName or tostring(scriptValue)
            else
                callingScript = tostring(scriptValue)
            end
        end
    end

    local traceback
    if settings.captureTraceback and debug and type(debug.traceback) == "function" then
        local ok, trace = pcall(function()
            return debug.traceback(nil, 3)
        end)
        if ok and trace ~= nil then
            traceback = tostring(trace)
        end
    end

    return callingScript, traceback
end

local function makePacket(remote, method, rawArgs, blocked, callingScript, traceback)
    local okPath, path = pcall(function() return remote:GetFullName() end)
    local okName, name = pcall(function() return remote.Name end)
    local okExp, exp = pcall(function() return utils.instanceExpression(remote, true) end)
    local argsOk, snapshot = pcall(utils.snapshotArgs, rawArgs, decoder)

    return {
        method = method,
        name = okName and name or "Unknown",
        path = okPath and path or tostring(remote),
        remoteExpression = okExp and exp or "game",
        instance = remote,
        rawArgs = rawArgs,
        args = argsOk and snapshot or {},
        argCount = rawArgs.n,
        returns = nil,
        returnCount = 0,
        timestamp = os.clock(),
        callingScript = callingScript,
        traceback = traceback,
        blocked = blocked == true,
    }
end

local function dispatchPacket(remote, method, rawArgs, blocked, callingScript, traceback)
    if not isActive or type(onPacket) ~= "function" then
        return
    end

    callDepth = callDepth + 1
    local ok, err = pcall(function()
        onPacket(makePacket(remote, method, rawArgs, blocked, callingScript, traceback))
    end)
    callDepth = callDepth - 1

    if not ok then
        warn("[Network] Failed to capture packet:", err)
    end
end

local function drainPacketQueue()
    while queueHead <= queueTail do
        local item = pendingPackets[queueHead]
        pendingPackets[queueHead] = nil
        queueHead = queueHead + 1

        if item then
            dispatchPacket(
                item.remote,
                item.method,
                item.args,
                false,
                item.callingScript,
                item.traceback
            )
        end
    end

    queueHead = 1
    queueTail = 0
    drainScheduled = false
end

local function enqueuePacket(remote, method, rawArgs, callingScript, traceback)
    local maxPending = settings.maxPendingPackets or settings.maxPackets or 500
    if queueTail - queueHead + 1 >= maxPending then
        return
    end

    queueTail = queueTail + 1
    pendingPackets[queueTail] = {
        remote = remote,
        method = method,
        args = rawArgs,
        callingScript = callingScript,
        traceback = traceback,
    }

    if not drainScheduled then
        drainScheduled = true
        task.defer(drainPacketQueue)
    end
end

function network.init(packetCallback)
    if initialized then return false, "network hook is already initialized" end
    if type(packetCallback) ~= "function" then return false, "packet callback is required" end
    if not hookmetamethod or not getnamecallmethod or not setnamecallmethod then
        return false, "required hook functions are unavailable"
    end

    onPacket = packetCallback
    isActive = true

    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", function(self, ...)
            if not isActive or callDepth > 0 then
                return oldNamecall(self, ...)
            end

            local method = getnamecallmethod()

            if checkcaller and checkcaller() then
                return oldNamecall(self, ...)
            end

            -- Do not allocate table.pack for unrelated namecalls. This is the
            -- hottest path and should forward with the original varargs.
            local isRemoteCall = false
            if typeof(self) == "Instance" then
                local className = self.ClassName
                isRemoteCall = (method == "FireServer" and className == "RemoteEvent")
                    or (method == "InvokeServer" and className == "RemoteFunction")
            end

            if isRemoteCall then
                -- Resolve the path once for exclusions and blocking.
                local ignored, blocked = settings.getRemoteState(self)
                if not ignored then
                    if blocked then
                        if recordingEnabled then
                            local packedArgs = table.pack(...)
                            local callingScript, traceback = captureCallMetadata()
                            dispatchPacket(
                                self,
                                method,
                                packedArgs,
                                true,
                                callingScript,
                                traceback
                            )
                        end

                        setnamecallmethod(method)
                        return nil
                    elseif recordingEnabled then
                        -- Only captured calls pay for argument copying and metadata.
                        local packedArgs = table.pack(...)
                        local callingScript, traceback = captureCallMetadata()
                        enqueuePacket(self, method, packedArgs, callingScript, traceback)
                    end
                end
            end

            setnamecallmethod(method)
            return oldNamecall(self, ...)
        end)
    end)

    if not ok then
        isActive = false
        onPacket = nil
        return false, result
    end

    oldNamecall = result
    initialized = true
    print("[Network] Batched async hook installed successfully.")
    return true
end

function network.shutdown()
    isActive = false
    recordingEnabled = false
    onPacket = nil
    table.clear(pendingPackets)
    queueHead = 1
    queueTail = 0
    drainScheduled = false
    print("[Network] Capture disabled.")
end

function network.isActive()
    return isActive
end

return network
