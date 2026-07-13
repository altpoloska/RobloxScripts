local RunService = game:GetService("RunService")

local Config = require("../Config")
local Actions = require("./Actions")

local Recorder = {}
Recorder.__index = Recorder

-- opts.GetWave : () -> number  (возвращает номер текущей волны)
function Recorder.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Recorder)
	self.Recording = false
	self.Actions = {} -- массив действий по порядку
	self.GameSpeed = Config.GameSpeed
	self._getWave = opts.GetWave or function() return 0 end
	self._wave = 0
	self._waveClock = 0
	self._conn = nil
	return self
end

-- "<волна> <секунды внутри волны>"
function Recorder:_timeString()
	return string.format("%d %s", self._wave, tostring(os.clock() - self._waveClock))
end

function Recorder:Start()
	if self.Recording then return false, "Already recording" end
	self.Recording = true
	self.Actions = {}
	self._wave = self._getWave()
	self._waveClock = os.clock()

	-- отслеживаем смену волны, чтобы сбрасывать таймер волны
	self._conn = RunService.Heartbeat:Connect(function()
		local w = self._getWave()
		if w ~= self._wave then
			self._wave = w
			self._waveClock = os.clock()
		end
	end)
	return true
end

-- Записать действие (таблица из Actions.*). Time проставляется здесь.
function Recorder:Record(action)
	if not self.Recording then return end
	action.Time = self:_timeString()
	table.insert(self.Actions, action)
	return action
end

-- Удобные обёртки -- вызывайте из своих хуков игры
function Recorder:PlaceUnit(unitName, cframe) return self:Record(Actions.PlaceUnit(unitName, cframe)) end
function Recorder:UpgradeUnit(label) return self:Record(Actions.UpgradeUnit(label)) end
function Recorder:ChangePriority(label, prio) return self:Record(Actions.ChangePriority(label, prio)) end
function Recorder:UseAbility(label, abi) return self:Record(Actions.UseAbility(label, abi)) end
function Recorder:ConfirmTowerLink(label) return self:Record(Actions.ConfirmTowerLink(label)) end
function Recorder:VoteSkip() return self:Record(Actions.VoteSkip()) end

function Recorder:Stop()
	if not self.Recording then return end
	self.Recording = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	return self:GetMacro()
end

-- Возвращает макрос в целевом формате:
-- { ["Game Speed"] = n, ["1"] = {..}, ["2"] = {..}, ... }
function Recorder:GetMacro()
	local macro = { ["Game Speed"] = self.GameSpeed }
	for i, action in ipairs(self.Actions) do
		macro[tostring(i)] = action
	end
	return macro
end

function Recorder:IsRecording() return self.Recording end

return Recorder
