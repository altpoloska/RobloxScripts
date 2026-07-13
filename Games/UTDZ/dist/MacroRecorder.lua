-- Bundled by luabundle {"version":"1.7.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
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

end)
__bundle_register("UI.Interface", function(require, _LOADED, __bundle_register, __bundle_modules)
local Interface = {}

-- deps = { PoloskaLib, Config, Storage, Recorder, Player, Automation }
function Interface.new(deps)
	local PoloskaLib = deps.PoloskaLib
	local Config = deps.Config
	local Storage = deps.Storage
	local recorder = deps.Recorder
	local player = deps.Player
	local Automation = deps.Automation

	-- общий стейт
	local selectedName = nil  -- выбранный в дропдауне файл макроса
	local lastMacro = nil     -- последняя запись в памяти
	local isPlaying = false
	local endAction = nil     -- "replay" | "next" | "leave" | nil
	local autoToggles = {}
	local handlingFinish = false

	local window = PoloskaLib:Create({
		Name = "Poloska Macro Recorder",
		Size = UDim2.fromOffset(660, 480),
		ToggleKey = Config.ToggleKey,
	})

	local function notify(title, text, dur)
		window:Notification({ Title = title, Text = text, Duration = dur or 3 })
	end

	local function countActions(macro)
		local n = 0
		if type(macro) == "table" then
			for k in pairs(macro) do
				if tonumber(k) then n = n + 1 end
			end
		end
		return n
	end

	----------------------------------------------------------------
	-- ОСНОВНОЙ ТАБ: автоматизация конца игры
	----------------------------------------------------------------
	local mainTab = window:Tab({ Name = "Main" })
	mainTab:Section("End of game (окно Finished)")

	-- взаимоисключающие тумблеры: активен только один
	local function makeAuto(name, key)
		local t
		t = mainTab:Toggle({
			Name = name,
			StartingState = false,
			Callback = function(state)
				if state then
					endAction = key
					for k, other in pairs(autoToggles) do
						if k ~= key then other:Set(false) end
					end
					notify("Auto", name .. " активен", 2)
				else
					if endAction == key then endAction = nil end
				end
			end,
		})
		autoToggles[key] = t
	end

	makeAuto("Auto Replay", "replay")
	makeAuto("Auto Vote Next", "next")
	makeAuto("Auto Leave", "leave")

	mainTab:Credit({ Name = "polosa__", Description = "PoloskaLib Macro Recorder" })

	----------------------------------------------------------------
	-- ТАБ MACRO
	----------------------------------------------------------------
	local macroTab = window:Tab({ Name = "Macro" })

	macroTab:Section("Macro file")
	local statusLabel = macroTab:Section("Status: idle")

	local macroDropdown
	local function refreshDropdown()
		macroDropdown:Clear()
		macroDropdown:AddItems(Storage.List())
	end

	-- СВЕРХУ: выбор существующего макроса
	macroDropdown = macroTab:Dropdown({
		Name = "Select macro",
		Items = Storage.List(),
		StartingText = "Select a macro...",
		Callback = function(item)
			local name = typeof(item) == "table" and item[1] or item
			if not name or name == "" then return end
			selectedName = name
			local macro, err = Storage.Load(name)
			if macro then
				lastMacro = macro
				statusLabel.Text = ("Selected: %s (%d actions)"):format(name, countActions(macro))
				notify("Storage", "Выбран " .. name, 2)
			else
				statusLabel.Text = "Selected: " .. name
				notify("Storage", "Загрузка не удалась: " .. tostring(err))
			end
		end,
	})

	macroTab:Button({ Name = "Refresh list", Callback = refreshDropdown })

	-- ПОД ДРОПДАУНОМ: создание по Enter
	macroTab:Textbox({
		Name = "New macro (Enter = create)",
		Placeholder = "macro name",
		Callback = function(text)
			if not text or text == "" then return end
			local empty = { ["Game Speed"] = recorder.GameSpeed or Config.GameSpeed }
			local ok, err = Storage.Save(text, empty)
			if not ok then
				notify("Storage", "Не удалось создать: " .. tostring(err))
				return
			end
			selectedName = text
			lastMacro = empty
			refreshDropdown()
			statusLabel.Text = "Selected: " .. selectedName
			notify("Storage", "Создан и выбран: " .. text, 2)
		end,
	})

	----------------------------------------------------------------
	-- Запись (пишет в выбранный файл при остановке)
	----------------------------------------------------------------
	macroTab:Section("Record")

	local recordToggle
	recordToggle = macroTab:Toggle({
		Name = "Record macro",
		StartingState = false,
		Callback = function(state)
			if state then
				if not selectedName then
					notify("Macro", "Сначала выбери/создай файл макроса")
					recordToggle:Set(false)
					return
				end
				local ok, err = recorder:Start()
				if not ok then
					notify("Error", tostring(err))
					recordToggle:Set(false)
					return
				end
				statusLabel.Text = "Status: recording -> " .. selectedName
				notify("Macro", "Запись началась", 2)
			else
				lastMacro = recorder:Stop()
				local n = countActions(lastMacro)
				if selectedName then
					local ok, err = Storage.Save(selectedName, lastMacro)
					if ok then
						statusLabel.Text = ("Saved %d actions -> %s"):format(n, selectedName)
						notify("Macro", ("Записано %d действий в %s"):format(n, selectedName), 2)
					else
						statusLabel.Text = "Save failed: " .. tostring(err)
						notify("Storage", "Не удалось сохранить: " .. tostring(err))
					end
				else
					statusLabel.Text = ("Recorded %d actions (not saved)"):format(n)
				end
			end
		end,
	})

	-- Скорость: дропдаун вместо слайдера
	macroTab:Dropdown({
		Name = "Speed",
		Items = { "x1", "x1.5" },
		StartingText = "x" .. tostring(Config.GameSpeed),
		Callback = function(item)
			local v = typeof(item) == "table" and item[1] or item
			local speed = (v == "x1.5") and 1.5 or 1
			recorder.GameSpeed = speed
		end,
	})

	macroTab:Keybind({
		Name = "Toggle recording",
		Keybind = Config.RecordKey,
		Callback = function() recordToggle:Set(not recorder:IsRecording()) end,
	})

	----------------------------------------------------------------
	-- Проигрывание (тумблер; НЕ выключается по окончанию)
	----------------------------------------------------------------
	macroTab:Section("Playback")

	local playToggle

	local function startPlay()
		if not selectedName then
			notify("Macro", "Сначала выбери макрос в дропдауне")
			return false
		end
		local macro, err = Storage.Load(selectedName)
		if not macro then
			notify("Macro", "Загрузка не удалась: " .. tostring(err))
			return false
		end
		if countActions(macro) == 0 then
			notify("Macro", "Макрос пуст -- нечего проигрывать")
			return false
		end
		lastMacro = macro
		statusLabel.Text = "Playing: " .. selectedName
		local ok, playErr = player:Play(macro, {
			OnFinished = function()
				-- НЕ выключаем тумблер: держим Play включённым и ждём конца игры
				if isPlaying then
					statusLabel.Text = "Macro done -- жду конца игры"
				else
					statusLabel.Text = "Stopped: " .. tostring(selectedName)
				end
			end,
		})
		if not ok then
			notify("Macro", tostring(playErr))
			return false
		end
		return true
	end

	playToggle = macroTab:Toggle({
		Name = "Play macro",
		StartingState = false,
		Callback = function(state)
			if state then
				isPlaying = true
				if not startPlay() then
					isPlaying = false
					playToggle:Set(false)
				end
			else
				isPlaying = false
				player:Stop()
			end
		end,
	})

	macroTab:Keybind({
		Name = "Play macro",
		Keybind = Config.PlayKey,
		Callback = function() playToggle:Set(not isPlaying) end,
	})

	----------------------------------------------------------------
	-- Автоматизация конца игры: реагируем на окно Finished
	----------------------------------------------------------------
	local function restartPlay()
		if isPlaying and selectedName then
			player:Stop()
			task.wait(Config.RestartPlayDelay or 2)
			if isPlaying then startPlay() end
		end
	end

	local function runEndAction()
		if endAction == "leave" then
			if Automation and Automation.Leave then Automation.Leave() end
			return
		end
		if endAction ~= "replay" and endAction ~= "next" then return end
		task.spawn(function()
			if endAction == "replay" then
				if Automation and Automation.VoteReplay then Automation.VoteReplay() end
			else
				if Automation and Automation.VoteNext then Automation.VoteNext() end
			end
			task.wait(Config.RestartVoteDelay or 1)
			-- авто-старт новой игры (Vote true) -- встроено после autoreplay
			if Automation and Automation.AutoStart then Automation.AutoStart() end
			-- перезапуск макроса на новую игру
			restartPlay()
		end)
	end

	if Automation and Automation.OnFinishedChanged then
		Automation.OnFinishedChanged(function(enabled)
			if enabled then
				if handlingFinish or not endAction then return end
				handlingFinish = true
				statusLabel.Text = "Finished -> " .. tostring(endAction)
				runEndAction()
			else
				handlingFinish = false
			end
		end)
	end

	return { window = window, recorder = recorder, player = player }
end

return Interface

end)
__bundle_register("Macro.GameAdapter", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Всё гейм-специфичное в одном месте: ремоуты, реестр юнитов,
-- автозапись через hookmetamethod и воспроизведение (Dispatch).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UnitRegistry = require("Macro.UnitRegistry")

local GameAdapter = {}
GameAdapter.__index = GameAdapter

-- Находит папку knit внутри Packages._Index.
-- Имя версии (напр. sleitnick_knit@1.7.0) меняется между играми/версиями,
-- поэтому ищем по имени "knit", а не хардкодим версию.
local _knitFolder
local function getKnitFolder()
	if _knitFolder and _knitFolder.Parent then return _knitFolder end
	local packages = ReplicatedStorage:WaitForChild("Packages", 10)
	local index = packages and packages:WaitForChild("_Index", 10)
	if not index then return nil end
	for _, d in ipairs(index:GetDescendants()) do
		if d.Name == "knit" and d:FindFirstChild("Services") then
			_knitFolder = d
			return d
		end
	end
	return nil
end

-- Достаёт RemoteFunction сервиса: knit.Services.<service>.RF.<name>
local function knitRF(service, name)
	local knit = getKnitFolder()
	if not knit then
		warn("[MacroRecorder] не найдена папка knit в ReplicatedStorage.Packages._Index")
		return nil
	end
	local services = knit:WaitForChild("Services", 10)
	local svc = services and services:WaitForChild(service, 10)
	local rf = svc and svc:WaitForChild("RF", 10)
	local remote = rf and rf:WaitForChild(name, 10)
	if not remote then
		warn(("[MacroRecorder] не найден ремоут: %s.RF.%s"):format(service, name))
	end
	return remote
end

-- Достаёт RemoteEvent сервиса: knit.Services.<service>.RE.<name>
local function knitRE(service, name)
	local knit = getKnitFolder()
	if not knit then
		warn("[MacroRecorder] не найдена папка knit в ReplicatedStorage.Packages._Index")
		return nil
	end
	local services = knit:WaitForChild("Services", 10)
	local svc = services and services:WaitForChild(service, 10)
	local re = svc and svc:WaitForChild("RE", 10)
	local remote = re and re:WaitForChild(name, 10)
	if not remote then
		warn(("[MacroRecorder] не найден ремоут: %s.RE.%s"):format(service, name))
	end
	return remote
end

function GameAdapter.new(opts)
	opts = opts or {}
	local self = setmetatable({}, GameAdapter)
	self.registry = UnitRegistry.new()

	self.remotes = {
		Vote        = knitRF("WaveService", "Vote"),
		PlaceUnit   = knitRF("TowerService", "PlaceUnit"),
		UpgradeUnit = knitRF("TowerService", "UpgradeUnit"),
		SellUnit    = knitRF("TowerService", "SellUnit"),
		ChangePriority = knitRF("TowerService", "ChangePriority"),
		VoteReplay  = knitRE("WaveService", "VoteReplay"),
		VoteNext    = knitRE("WaveService", "NextMap"),
		ToLobby     = knitRE("WaveService", "ToLobby"),
	}

	-- slot (число из PlaceUnit) -> имя юнита из хотбара. ЗАПОЛНИ под игру.
	self.GetHotbarUnitName = opts.GetHotbarUnitName or function(slot) return "Unit " .. tostring(slot) end
	-- имя юнита -> slot в хотбаре (для воспроизведения). ЗАПОЛНИ под игру.
	self.GetSlotByUnitName = opts.GetSlotByUnitName or function(name) return 1 end
	-- () -> { uuid, uuid, ... } : список id всех поставленных юнитов в workspace. ЗАПОЛНИ.
	self.ListPlacedUnitIds = opts.ListPlacedUnitIds or function() return {} end
	-- сколько ждать появления нового юнита в workspace (сек)
	self.UnitCaptureTimeout = opts.UnitCaptureTimeout or 0.5

	self._recorder = nil
	self._oldNamecall = nil
	return self
end

-- Множество текущих id юнитов
function GameAdapter:_snapshotIds()
	local set = {}
	for _, id in ipairs(self.ListPlacedUnitIds()) do
		set[id] = true
	end
	return set
end

-- Ищем id, которого не было до постановки (с коротким поллингом на случай репликации)
function GameAdapter:_findNewId(before)
	local deadline = os.clock() + self.UnitCaptureTimeout
	repeat
		for _, id in ipairs(self.ListPlacedUnitIds()) do
			if not before[id] then return id end
		end
		RunService.Heartbeat:Wait()
	until os.clock() >= deadline
	return nil
end

----------------------------------------------------------------------
-- ЗАПИСЬ: перехват InvokeServer через __namecall
----------------------------------------------------------------------
function GameAdapter:InstallHooks(recorder)
	self._recorder = recorder
	local remotes = self.remotes
	local registry = self.registry

	if not (hookmetamethod and getnamecallmethod and setnamecallmethod) then
		warn("[MacroRecorder] hook-функции недоступны в этом executor'е")
		return
	end

	local depth = 0
	local oldNamecall
	oldNamecall = hookmetamethod(game, "__namecall", function(inst, ...)
		-- Наш код записи сам дёргает namecall'ы -> защита от рекурсии.
		if depth > 0 then
			return oldNamecall(inst, ...)
		end

		local method = getnamecallmethod()

		-- Интересует только клиентский InvokeServer.
		if (checkcaller and checkcaller()) or method ~= "InvokeServer" then
			return oldNamecall(inst, ...)
		end

		local args = table.pack(...)

		if inst == remotes.PlaceUnit then
			local unitName, before
			depth = depth + 1
			pcall(function()
				unitName = self.GetHotbarUnitName(args[1])
				if recorder:IsRecording() then
					recorder:PlaceUnit(unitName, args[2]) -- Time фиксируется в момент отправки
				end
				before = self:_snapshotIds()
			end)
			depth = depth - 1

			-- ВАЖНО: восстановить метод перед реальным вызовом.
			setnamecallmethod(method)
			local result = oldNamecall(inst, table.unpack(args, 1, args.n))

			-- захват UUID в отдельном потоке, чтобы не морозить хук.
			task.spawn(function()
				depth = depth + 1
				pcall(function()
					local uuid = (typeof(result) == "string" and result)
						or (before and self:_findNewId(before))
					if unitName then registry:Register(unitName, uuid) end
				end)
				depth = depth - 1
			end)
			return result
		end

		-- Остальные действия: пишем и пробрасываем без изменений.
		depth = depth + 1
		pcall(function()
			if inst == remotes.UpgradeUnit then
				if recorder:IsRecording() then
					recorder:UpgradeUnit(registry:Resolve(args[1]) or tostring(args[1]))
				end
			elseif inst == remotes.SellUnit then
				if recorder:IsRecording() then
					recorder:SellUnit(registry:Resolve(args[1]) or tostring(args[1]))
				end
			elseif inst == remotes.ChangePriority then
				-- args[1] = uuid, args[2] = приоритет (число)
				if recorder:IsRecording() then
					recorder:ChangePriority(registry:Resolve(args[1]) or tostring(args[1]), args[2])
				end
			elseif inst == remotes.Vote then
				if recorder:IsRecording() then
					recorder:VoteSkip()
				end
			end
		end)
		depth = depth - 1

		setnamecallmethod(method)
		return oldNamecall(inst, table.unpack(args, 1, args.n))
	end)

	self._oldNamecall = oldNamecall
end

----------------------------------------------------------------------
-- ВОСПРОИЗВЕДЕНИЕ: выполнить действие в игре
----------------------------------------------------------------------
function GameAdapter:Dispatch(action, ctx)
	local remotes = self.remotes
	local registry = self.registry
	local t = action.Type

	if t == "PlaceUnit" then
		local slot = self.GetSlotByUnitName(action.Unit)
		local before = self:_snapshotIds()
		local result = remotes.PlaceUnit:InvokeServer(slot, ctx.cframe)
		-- тот же порядок регистрации -> label совпадёт с записанным "Имя - N"
		local uuid = (typeof(result) == "string" and result) or self:_findNewId(before)
		registry:Register(action.Unit, uuid)

	elseif t == "UpgradeUnit" then
		local uuid = registry:ResolveLabel(action.Pos)
		if uuid then remotes.UpgradeUnit:InvokeServer(uuid) end

	elseif t == "SellUnit" then
		local uuid = registry:ResolveLabel(action.Pos)
		if uuid then remotes.SellUnit:InvokeServer(uuid) end

	elseif t == "ChangePriority" then
		local uuid = registry:ResolveLabel(action.Pos)
		if uuid then remotes.ChangePriority:InvokeServer(uuid, action.Prio) end

	elseif t == "VoteSkip" then
		remotes.Vote:InvokeServer(true)

	elseif t == "UseAbility" or t == "ConfirmTowerLink" then
		-- ремоуты пока не известны -- добавь позже
	end
end

-- Действия в конце игры (окно Finished)
function GameAdapter:VoteReplay()
	if self.remotes.VoteReplay then
		self.remotes.VoteReplay:FireServer()
	else
		warn("[MacroRecorder] VoteReplay недоступен")
	end
end

function GameAdapter:VoteNext()
	if self.remotes.VoteNext then
		self.remotes.VoteNext:FireServer()
	else
		warn("[MacroRecorder] VoteNext недоступен -- проверь имя ремоута")
	end
end

function GameAdapter:AutoStart()
	if self.remotes.Vote then
		self.remotes.Vote:InvokeServer(true)
	else
		warn("[MacroRecorder] Vote (auto start) недоступен")
	end
end

function GameAdapter:ToLobby()
	if self.remotes.ToLobby then
		self.remotes.ToLobby:FireServer()
	else
		warn("[MacroRecorder] ToLobby недоступен")
	end
end

function GameAdapter:ResetRegistry()
	self.registry:Reset()
end

return GameAdapter

end)
__bundle_register("Macro.UnitRegistry", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Сопоставляет живые UUID юнитов (меняются каждый забег) с портативным
-- идентификатором вида "Имя - N" (N -- какой по счёту юнит этого имени).
local UnitRegistry = {}
UnitRegistry.__index = UnitRegistry

function UnitRegistry.new()
	local self = setmetatable({}, UnitRegistry)
	self._counts = {} -- [unitName] = сколько поставлено
	self._byUuid = {} -- [uuid]  = "Имя - N"
	self._byLabel = {} -- ["Имя - N"] = uuid
	return self
end

-- Регистрирует поставленный юнит, возвращает его label "Имя - N".
function UnitRegistry:Register(unitName, uuid)
	local n = (self._counts[unitName] or 0) + 1
	self._counts[unitName] = n
	local label = string.format("%s - %d", unitName, n)
	self._byLabel[label] = uuid
	if uuid ~= nil then
		self._byUuid[uuid] = label
	end
	return label, n
end

-- uuid -> "Имя - N" (при записи)
function UnitRegistry:Resolve(uuid)
	return self._byUuid[uuid]
end

-- "Имя - N" -> актуальный uuid (при воспроизведении)
function UnitRegistry:ResolveLabel(label)
	return self._byLabel[label]
end

function UnitRegistry:Reset()
	self._counts = {}
	self._byUuid = {}
	self._byLabel = {}
end

return UnitRegistry

end)
__bundle_register("Macro.Storage", function(require, _LOADED, __bundle_register, __bundle_modules)
local HttpService = game:GetService("HttpService")

local Config = require("Config")

local Storage = {}

function Storage.Serialize(macro)
	return HttpService:JSONEncode(macro)
end

function Storage.Deserialize(str)
	return HttpService:JSONDecode(str)
end

-- Ключи-числа идут в произвольном порядке в JSON -- сортируем по номеру.
function Storage.ToOrderedList(macro)
	local list = {}
	for key, value in pairs(macro) do
		local n = tonumber(key)
		if n and type(value) == "table" then
			table.insert(list, { index = n, action = value })
		end
	end
	table.sort(list, function(a, b) return a.index < b.index end)
	return list
end

local function hasFiles()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
end

function Storage.Save(name, macro)
	if not hasFiles() then return false, "File API unavailable" end
	if typeof(makefolder) == "function" and typeof(isfolder) == "function"
		and not isfolder(Config.FolderName) then
		makefolder(Config.FolderName)
	end
	writefile(Config.FolderName .. "/" .. name .. ".json", Storage.Serialize(macro))
	return true
end

function Storage.Load(name)
	if not hasFiles() then return nil, "File API unavailable" end
	local path = Config.FolderName .. "/" .. name .. ".json"
	if typeof(isfile) == "function" and not isfile(path) then
		return nil, "File not found"
	end
	return Storage.Deserialize(readfile(path))
end

function Storage.List()
	if typeof(listfiles) ~= "function" then return {} end
	local ok, files = pcall(listfiles, Config.FolderName)
	if not ok then return {} end
	local out = {}
	for _, path in ipairs(files) do
		local name = path:match("([^/\\]+)%.json$")
		if name then table.insert(out, name) end
	end
	return out
end

return Storage

end)
__bundle_register("Config", function(require, _LOADED, __bundle_register, __bundle_modules)
local Config = {
	GameSpeed = 1.5,                       -- записывается в макрос как "Game Speed"
	ToggleKey = Enum.KeyCode.RightControl, -- показать/скрыть окно
	RecordKey = Enum.KeyCode.F6,           -- быстрый старт/стоп записи
	PlayKey = Enum.KeyCode.F7,             -- быстрый старт воспроизведения
	FolderName = "PoloskaMacros",          -- папка для сохранённых макросов
	RestartVoteDelay = 1,                  -- пауза (сек) после vote replay/next перед авто-стартом
	RestartPlayDelay = 2,                  -- пауза (сек) перед перезапуском play macro
}

return Config

end)
__bundle_register("Macro.Player", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")

local Storage = require("Macro.Storage")
local Actions = require("Macro.Actions")

local Player = {}
Player.__index = Player

-- opts.GetWave  : () -> number
-- opts.Dispatch : (action, ctx) -> ()  выполняет действие в игре
-- opts.OnStart  : () -> ()  вызывается перед воспроизведением (напр. сброс реестра)
function Player.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Player)
	self.Playing = false
	self._getWave = opts.GetWave or function() return 0 end
	self._dispatch = opts.Dispatch or function() end
	self._onStart = opts.OnStart or function() end
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
		self._onStart()

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

end)
__bundle_register("Macro.Actions", function(require, _LOADED, __bundle_register, __bundle_modules)
-- Конструкторы действий макроса в целевом формате.
-- Каждый билдер возвращает таблицу без поля Time -- Time добавляет Recorder.

local Actions = {}

-- CFrame -> "x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22"
function Actions.encodeCFrame(cf)
	local c = { cf:GetComponents() }
	for i, v in ipairs(c) do
		c[i] = tostring(v)
	end
	return table.concat(c, ", ")
end

-- Строка Pos -> CFrame
function Actions.decodeCFrame(pos)
	local nums = {}
	for token in string.gmatch(pos, "[^,%s]+") do
		table.insert(nums, tonumber(token))
	end
	return CFrame.new(table.unpack(nums))
end

function Actions.PlaceUnit(unitName, cframe)
	return { Type = "PlaceUnit", Unit = unitName, Pos = Actions.encodeCFrame(cframe) }
end

function Actions.UpgradeUnit(unitLabel) -- unitLabel = "Bulmo - 1"
	return { Type = "UpgradeUnit", Pos = unitLabel }
end

function Actions.ChangePriority(unitLabel, prio)
	return { Type = "ChangePriority", Prio = prio, Pos = unitLabel }
end

function Actions.UseAbility(unitLabel, abilityIndex)
	return { Type = "UseAbility", Abi = abilityIndex, Pos = unitLabel }
end

function Actions.ConfirmTowerLink(unitLabel)
	return { Type = "ConfirmTowerLink", Pos = unitLabel }
end

-- Расширение сверх example.json: в игре есть SellUnit.
function Actions.SellUnit(unitLabel)
	return { Type = "SellUnit", Pos = unitLabel }
end

function Actions.VoteSkip()
	return { Type = "VoteSkip" }
end

return Actions

end)
__bundle_register("Macro.Recorder", function(require, _LOADED, __bundle_register, __bundle_modules)
local RunService = game:GetService("RunService")

local Config = require("Config")
local Actions = require("Macro.Actions")

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

-- "<волна> <секунды с начала волны>"
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

-- Удобные обёртки -- вызываются из GameAdapter при перехвате
function Recorder:PlaceUnit(unitName, cframe) return self:Record(Actions.PlaceUnit(unitName, cframe)) end
function Recorder:UpgradeUnit(label) return self:Record(Actions.UpgradeUnit(label)) end
function Recorder:ChangePriority(label, prio) return self:Record(Actions.ChangePriority(label, prio)) end
function Recorder:UseAbility(label, abi) return self:Record(Actions.UseAbility(label, abi)) end
function Recorder:ConfirmTowerLink(label) return self:Record(Actions.ConfirmTowerLink(label)) end
function Recorder:SellUnit(label) return self:Record(Actions.SellUnit(label)) end
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

end)
return __bundle_require("__root")