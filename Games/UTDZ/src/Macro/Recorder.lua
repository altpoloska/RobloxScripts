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
