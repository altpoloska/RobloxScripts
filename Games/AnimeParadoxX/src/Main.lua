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
