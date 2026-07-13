--!nocheck
-- Точка входа. Связывает макро-движок с конкретной игрой через GameAdapter.

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

------------------------------------------------------------------
-- 1. Номер текущей волны из GUI
--    Text вида: Wave 10<font color="#939393">/15</font>
------------------------------------------------------------------
local function GetWave()
	local ok, text = pcall(function()
		return LocalPlayer.PlayerGui.GameUI.HUD.Upper
			.WaveInformations.Container.Wave.Text
	end)
	if not ok or type(text) ~= "string" then
		return 0
	end
	-- берём первое число после "Wave " (маркап <font> игнорируется)
	return tonumber(string.match(text, "Wave%s*(%d+)")) or 0
end

------------------------------------------------------------------
-- 2a. Хотбар: slot (из PlaceUnit) <-> имя юнита
--   Папка:  PlayerGui.GameUI.HUD.Bottom.Hotbar.Units
--   Слоты:  ContainerBig (доступный) / Locked (заблокирован)
--   Имя:    ContainerBig.Unit.UnitInfomation.RightInfos.UnitName.Text
--   UIListLayout может менять порядок GetChildren, поэтому
--   сортируем по AbsolutePosition (сверху вниз, как на экране).
--   Locked включаем в нумерацию, чтобы индекс совпадал со slot.
------------------------------------------------------------------
local function getHotbarSlots()
	local ok, folder = pcall(function()
		return LocalPlayer.PlayerGui.GameUI.HUD.Bottom.Hotbar.Units
	end)
	if not ok or not folder then return {} end

	local slots = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("GuiObject") then -- пропускаем UIListLayout и проч.
			table.insert(slots, child)
		end
	end

	table.sort(slots, function(a, b)
		local pa, pb = a.AbsolutePosition, b.AbsolutePosition
		if math.abs(pa.Y - pb.Y) > 1 then
			return pa.Y < pb.Y -- вертикальный хотбар
		end
		return pa.X < pb.X   -- горизонтальный fallback
	end)
	return slots
end

-- массив: [slot] = имя юнита (false для Locked/пустых)
local function getHotbar()
	local names = {}
	for i, slot in ipairs(getHotbarSlots()) do
		local name = false
		if slot.Name == "ContainerBig" then
			local ok, txt = pcall(function()
				return slot.Unit.UnitInfomation.RightInfos.UnitName.Text
			end)
			if ok and type(txt) == "string" and txt ~= "" then
				name = txt
			end
		end
		names[i] = name
	end
	return names
end

local function GetHotbarUnitName(slot)
	local names = getHotbar()
	local name = names[slot]
	if type(name) == "string" then return name end
	return "Unit " .. tostring(slot) -- fallback, если не прочитали
end

local function GetSlotByUnitName(unitName)
	local names = getHotbar()
	for slot = 1, #names do
		if names[slot] == unitName then return slot end
	end
	return 1
end

------------------------------------------------------------------
-- 2b. Поставленные юниты: workspace.Ignore.Units
--   В папке лежат и юниты (имя = UUID), и враги (имя = число).
--   Исключаем всё числовое (враги), остальное считаем юнитами.
------------------------------------------------------------------
local function isEnemyName(name)
	-- враги имеют чисто числовые имена
	return tonumber(name) ~= nil
end

local function getUnitsFolder()
	local ignore = workspace:FindFirstChild("Ignore")
	return ignore and ignore:FindFirstChild("Units") or nil
end

local function ListPlacedUnitIds()
	local folder = getUnitsFolder()
	local ids = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if not isEnemyName(child.Name) then
				table.insert(ids, child.Name)
			end
		end
	end
	return ids
end

------------------------------------------------------------------
-- 3. Адаптер и движок
------------------------------------------------------------------
local adapter = GameAdapter.new({
	GetHotbarUnitName = GetHotbarUnitName,
	GetSlotByUnitName = GetSlotByUnitName,
	ListPlacedUnitIds = ListPlacedUnitIds,
})

local recorder = Recorder.new({ GetWave = GetWave })
local player = Player.new({
	GetWave = GetWave,
	Dispatch = function(action, ctx) adapter:Dispatch(action, ctx) end,
	OnStart = function() adapter:ResetRegistry() end, -- лейблы пересчитываются с нуля
})

-- Автозапись: перехват InvokeServer
adapter:InstallHooks(recorder)

------------------------------------------------------------------
-- 4. UI
------------------------------------------------------------------
------------------------------------------------------------------
-- 3b. Автоматизация конца игры (окно PlayerGui.Finished)
------------------------------------------------------------------
local automation = {}

function automation.VoteReplay() adapter:VoteReplay() end
function automation.VoteNext() adapter:VoteNext() end
function automation.AutoStart() adapter:AutoStart() end

function automation.Leave() adapter:ToLobby() end

-- Подписка на окно результата: cb(enabled) при изменении Finished.Enabled
function automation.OnFinishedChanged(cb)
	task.spawn(function()
		local pg = LocalPlayer:WaitForChild("PlayerGui", 30)
		local finished = pg and pg:WaitForChild("Finished", 60)
		if not finished then
			warn("[MacroRecorder] PlayerGui.Finished не найден")
			return
		end
		finished:GetPropertyChangedSignal("Enabled"):Connect(function()
			cb(finished.Enabled)
		end)
		if finished.Enabled then cb(true) end
	end)
end

------------------------------------------------------------------
-- 4. UI
------------------------------------------------------------------
Interface.new({
	PoloskaLib = PoloskaLib,
	Config = Config,
	Storage = Storage,
	Recorder = recorder,
	Player = player,
	Automation = automation,
})
