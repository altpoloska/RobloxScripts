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
