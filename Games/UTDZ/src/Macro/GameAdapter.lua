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
