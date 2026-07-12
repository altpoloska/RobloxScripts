local settings = require("src/settings")

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

function network.init(packetCallback)
    if initialized then
        return false, "network hook is already initialized"
    end

    if type(packetCallback) ~= "function" then
        return false, "packet callback is required"
    end

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
                callDepth = callDepth + 1

                local captureOk, captureError = pcall(function()
                    local decodedArgs = { n = packedArgs.n }
                    for i = 1, packedArgs.n do
                        local arg = packedArgs[i]
                        if typeof(arg) == "buffer" and decoder then
                            local decodeOk, decoded = pcall(decoder, arg)
                            decodedArgs[i] = decodeOk and decoded or arg
                        else
                            decodedArgs[i] = arg
                        end
                    end

                    onPacket({
                        method = method,
                        name = self.Name,
                        path = self:GetFullName(),
                        args = decodedArgs,
                        argCount = packedArgs.n,
                        timestamp = os.clock(),
                        instance = self,
                    })
                end)

                callDepth = callDepth - 1
                if not captureOk then
                    warn("[Network] Failed to capture packet:", captureError)
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
    print("[Network] Hook installed successfully.")
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
