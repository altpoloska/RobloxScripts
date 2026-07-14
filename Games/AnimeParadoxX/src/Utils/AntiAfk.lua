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
