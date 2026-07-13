local Interface = {}

-- deps = { PoloskaLib, Config, Storage, Recorder(экземпляр), Player(экземпляр) }
function Interface.new(deps)
	local PoloskaLib = deps.PoloskaLib
	local Config = deps.Config
	local Storage = deps.Storage
	local recorder = deps.Recorder
	local player = deps.Player

	local lastMacro = nil
	local savedName = "macro1"

	local window = PoloskaLib:Create({
		Name = "Poloska Macro Recorder",
		Size = UDim2.fromOffset(660, 460),
		ToggleKey = Config.ToggleKey,
	})

	----------------------------------------------------------------
	-- Record
	----------------------------------------------------------------
	local recordTab = window:Tab({ Name = "Record" })
	recordTab:Section("Recording")
	local statusLabel = recordTab:Section("Status: idle")

	local recordToggle
	recordToggle = recordTab:Toggle({
		Name = "Record macro",
		StartingState = false,
		Callback = function(state)
			if state then
				local ok, err = recorder:Start()
				if not ok then
					window:Notification({ Title = "Error", Text = err, Duration = 3 })
					recordToggle:Set(false)
					return
				end
				statusLabel.Text = "Status: recording..."
				window:Notification({ Title = "Macro", Text = "Recording started", Duration = 2 })
			else
				lastMacro = recorder:Stop()
				local n = 0
				for k in pairs(lastMacro) do
					if tonumber(k) then n += 1 end
				end
				statusLabel.Text = ("Status: recorded %d actions"):format(n)
				window:Notification({ Title = "Macro", Text = "Recording stopped", Duration = 2 })
			end
		end,
	})

	recordTab:Slider({
		Name = "Game Speed",
		Min = 1, Max = 3, Default = Config.GameSpeed,
		Callback = function(v) recorder.GameSpeed = v end,
	})

	recordTab:Keybind({
		Name = "Toggle recording",
		Keybind = Config.RecordKey,
		Callback = function() recordToggle:Set(not recorder:IsRecording()) end,
	})

	----------------------------------------------------------------
	-- Playback
	----------------------------------------------------------------
	local playTab = window:Tab({ Name = "Playback" })
	playTab:Section("Playback")

	local function play()
		if not lastMacro then
			window:Notification({ Title = "Macro", Text = "No macro loaded", Duration = 3 })
			return
		end
		local ok, err = player:Play(lastMacro, {
			OnFinished = function()
				window:Notification({ Title = "Macro", Text = "Playback finished", Duration = 2 })
			end,
		})
		if not ok then window:Notification({ Title = "Macro", Text = err, Duration = 3 }) end
	end

	playTab:Button({ Name = "Play macro", Callback = play })
	playTab:Button({ Name = "Stop playback", Callback = function() player:Stop() end })
	playTab:Keybind({ Name = "Play macro", Keybind = Config.PlayKey, Callback = play })

	----------------------------------------------------------------
	-- Storage
	----------------------------------------------------------------
	local storageTab = window:Tab({ Name = "Storage" })
	storageTab:Section("Save / Load")

	storageTab:Textbox({
		Name = "Macro name", Placeholder = "macro1",
		Callback = function(text) if text ~= "" then savedName = text end end,
	})

	storageTab:Button({
		Name = "Save current macro",
		Callback = function()
			if not lastMacro then
				window:Notification({ Title = "Storage", Text = "Nothing to save", Duration = 3 })
				return
			end
			local ok, err = Storage.Save(savedName, lastMacro)
			window:Notification({
				Title = "Storage",
				Text = ok and ("Saved as " .. savedName) or ("Save failed: " .. tostring(err)),
				Duration = 3,
			})
		end,
	})

	local loadDropdown = storageTab:Dropdown({
		Name = "Saved macros",
		Items = Storage.List(),
		StartingText = "Select a macro...",
		Callback = function(item)
			local name = typeof(item) == "table" and item[1] or item
			local macro, err = Storage.Load(name)
			if macro then
				lastMacro = macro
				savedName = name
				window:Notification({ Title = "Storage", Text = "Loaded " .. name, Duration = 2 })
			else
				window:Notification({ Title = "Storage", Text = "Load failed: " .. tostring(err), Duration = 3 })
			end
		end,
	})

	storageTab:Button({
		Name = "Refresh list",
		Callback = function()
			loadDropdown:Clear()
			loadDropdown:AddItems(Storage.List())
		end,
	})

	storageTab:Credit({ Name = "polosa__", Description = "PoloskaLib Macro Recorder" })

	return { window = window, recorder = recorder, player = player }
end

return Interface
