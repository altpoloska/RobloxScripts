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
