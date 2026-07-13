local RunService = game:GetService("RunService")

local Storage = require("./Storage")
local Actions = require("./Actions")

local Player = {}
Player.__index = Player

-- opts.GetWave  : () -> number
-- opts.Dispatch : (action, ctx) -> ()  выполняет действие в игре
function Player.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Player)
	self.Playing = false
	self._getWave = opts.GetWave or function() return 0 end
	self._dispatch = opts.Dispatch or function() end
	self._thread = nil
	return self
end

-- "14 2.1476972103118896" -> 14, 2.1476972103118896
local function parseTime(timeStr)
	local wave, secs = string.match(timeStr, "^(%-?%d+)%s+(.+)$")
	return tonumber(wave), tonumber(secs)
end

function Player:Play(macro, options)
	if self.Playing then return false, "Already playing" end
	local list = Storage.ToOrderedList(macro)
	if #list == 0 then return false, "Empty macro" end

	options = options or {}
	self.Playing = true
	local onFinished = options.OnFinished

	self._thread = task.spawn(function()
		local currentWave = self._getWave()
		local waveClock = os.clock()

		local function sync()
			local w = self._getWave()
			if w ~= currentWave then
				currentWave = w
				waveClock = os.clock()
			end
		end

		for _, entry in ipairs(list) do
			if not self.Playing then break end
			local action = entry.action
			local targetWave, targetSecs = parseTime(action.Time)

			-- ждём нужную волну и момент внутри неё
			while self.Playing do
				sync()
				if currentWave > targetWave then break end
				if currentWave == targetWave and (os.clock() - waveClock) >= targetSecs then break end
				RunService.Heartbeat:Wait()
			end

			if self.Playing then
				local ctx = {}
				if action.Type == "PlaceUnit" then
					ctx.cframe = Actions.decodeCFrame(action.Pos)
				end
				self._dispatch(action, ctx)
			end
		end

		self:Stop()
		if onFinished then onFinished() end
	end)

	return true
end

function Player:Stop()
	if not self.Playing then return end
	self.Playing = false
end

function Player:IsPlaying() return self.Playing end

return Player
