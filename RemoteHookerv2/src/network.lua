local settings = require("src/settings")
local utils = require("src/utils")

local network = {}
local oldNamecall
local isActive = false
local initialized = false
local onPacket = nil
local decoder = nil
local callDepth = 0

function network.setDecoder(callback)
    assert(callback == nil or type(callback) == "function", "decoder must be a function or nil")
    decoder = callback
end

local function captureCallMetadata()
    local callingScript
    if type(getcallingscript) == "function" then
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
    if debug and type(debug.traceback) == "function" then
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
            local packedArgs = table.pack(...)

            if checkcaller and checkcaller() then
                return oldNamecall(self, ...)
            end

            local shouldCapture = false
            if typeof(self) == "Instance" then
                local className = self.ClassName
                local isRemoteEvent = method == "FireServer"
                and className == "RemoteEvent"
                local isRemoteFunction = method == "InvokeServer"
                and className == "RemoteFunction"

                shouldCapture = (isRemoteEvent or isRemoteFunction)
                and not settings.shouldIgnore(self)
            end

            if shouldCapture then
                -- These must be collected on the intercepted thread before task.defer,
                -- otherwise both APIs would describe the deferred callback instead.
                local callingScript, traceback = captureCallMetadata()
                local blocked = settings.isBlocked and settings.isBlocked(self)
                
                -- Если пакет НЕ заблокирован, мы отдаем его UI асинхронно, 
                -- чтобы не тормозить игру и обмануть замеры таймингов (Timing Checks)
                if not blocked then
                    -- Делаем мгновенную легкую копию аргументов
                    local argsFastCopy = { n = packedArgs.n }
                    for i = 1, packedArgs.n do argsFastCopy[i] = packedArgs[i] end

                    task.defer(function()
                        callDepth = callDepth + 1
                        local captureOk, captureError = pcall(function()
                            onPacket(makePacket(
                                self,
                                method,
                                argsFastCopy,
                                false,
                                callingScript,
                                traceback
                            ))
                        end)
                        callDepth = callDepth - 1
                        if not captureOk then
                            warn("[Network] Failed to capture packet:", captureError)
                        end
                    end)
                else
                    -- Если пакет заблокирован, обрабатываем его сразу и убиваем
                    callDepth = callDepth + 1
                    pcall(function()
                        onPacket(makePacket(
                            self,
                            method,
                            packedArgs,
                            true,
                            callingScript,
                            traceback
                        ))
                    end)
                    callDepth = callDepth - 1
                    
                    setnamecallmethod(method)
                    return nil
                end
            end

            setnamecallmethod(method)
            return oldNamecall(self, table.unpack(packedArgs, 1, packedArgs.n))
        end)
    end)

    if not ok then
        isActive = false
        onPacket = nil
        return false, result
    end

    oldNamecall = result
    initialized = true
    print("[Network] Async Hook installed successfully.")
    return true
end

function network.shutdown()
    isActive = false
    onPacket = nil
    print("[Network] Capture disabled.")
end

function network.isActive()
    return isActive
end

return network
