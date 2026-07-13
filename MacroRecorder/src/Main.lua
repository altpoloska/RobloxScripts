--!nocheck
-- Точка входа. Здесь вы связываете макро-движок с логикой конкретной игры.

local PoloskaLib = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/altpoloska/PoloskaLib/refs/heads/main/PoloskaLib.lua"
))()

local Config = require("./Config")
local Recorder = require("./Macro/Recorder")
local Player = require("./Macro/Player")
local Storage = require("./Macro/Storage")
local Interface = require("./UI/Interface")

------------------------------------------------------------------
-- 1. Адаптер под вашу игру (заполните под конкретный TD)
------------------------------------------------------------------

-- Должна возвращать номер текущей волны.
local function GetWave()
	-- пример: return workspace.Wave.Value
	return 0
end

-- Выполняет одно действие макроса при воспроизведении.
local function Dispatch(action, ctx)
	if action.Type == "PlaceUnit" then
		-- ctx.cframe -- CFrame для постановки, action.Unit -- имя юнита
		-- YourGame.PlaceUnit(action.Unit, ctx.cframe)
	elseif action.Type == "UpgradeUnit" then
		-- action.Pos = "Имя - индекс"
		-- YourGame.UpgradeUnit(action.Pos)
	elseif action.Type == "ChangePriority" then
		-- YourGame.SetPriority(action.Pos, action.Prio)
	elseif action.Type == "UseAbility" then
		-- YourGame.UseAbility(action.Pos, action.Abi)
	elseif action.Type == "ConfirmTowerLink" then
		-- YourGame.ConfirmTowerLink(action.Pos)
	elseif action.Type == "VoteSkip" then
		-- YourGame.VoteSkip()
	end
end

------------------------------------------------------------------
-- 2. Создаём движок
------------------------------------------------------------------

local recorder = Recorder.new({ GetWave = GetWave })
local player = Player.new({ GetWave = GetWave, Dispatch = Dispatch })

------------------------------------------------------------------
-- 3. Хуки записи -- вызывайте из своих перехватов игры
------------------------------------------------------------------
-- recorder:PlaceUnit("Bulmo", placementCFrame)
-- recorder:UpgradeUnit("Bulmo - 1")
-- recorder:ChangePriority("Ultimate Fused Warrior - 1", 1)
-- recorder:UseAbility("Prodigy Mage (Apprentice) - 1", 1)
-- recorder:ConfirmTowerLink("Fastcart - 1")
-- recorder:VoteSkip()

------------------------------------------------------------------
-- 4. UI
------------------------------------------------------------------

Interface.new({
	PoloskaLib = PoloskaLib,
	Config = Config,
	Storage = Storage,
	Recorder = recorder,
	Player = player,
})
