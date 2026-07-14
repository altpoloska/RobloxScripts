local Interface = {}

function Interface.new(deps)
    local lib = deps.PoloskaLib
    local Config = deps.Config
    local Storage = deps.Storage
    local recorder = deps.Recorder
    local player = deps.Player
    local adapter = deps.Adapter
    local settings = deps.Settings

    local selectedName = settings.Get("SelectedMacro")
    local auto2xEnabled = settings.Get("Auto2x") == true
    local selectedSpeed = auto2xEnabled and 2 or 1
    local playEnabled = settings.Get("PlayMacro") == true
    local autoNextEnabled = settings.Get("AutoNext") == true
    local autoReplayEnabled = settings.Get("AutoReplay") == true
    local matchEndLatched = false
    local nextRewardClickAt = 0
    local overwriteConfirmUntil = 0
    local arm

    if selectedName and not Storage.Exists(selectedName) then
        selectedName = nil
        settings.Set("SelectedMacro", nil)
    end

    if autoNextEnabled and autoReplayEnabled then
        autoNextEnabled = false
        settings.Set("AutoNext", false)
    end

    local window = lib:Create({
        Name = "Anime Paradox X Macro Recorder",
        Size = UDim2.fromOffset(660, 480),
        ToggleKey = Config.ToggleKey,
    })

    local function notify(title, text, duration)
        window:Notification({
            Title = title,
            Text = text,
            Duration = duration or 3,
        })
    end

    local function countActions(macro)
        return #Storage.ToOrderedList(macro)
    end

    local function styleDropdownArrows()
        for _, arrow in ipairs(window.Gui:GetDescendants()) do
            local isArrow = arrow:IsA("TextLabel")
                and (arrow.Text == "▾" or arrow.Text == "▴")

            if isArrow and not arrow:FindFirstChild("DropdownChevron") then
                local icon = Instance.new("ImageLabel")
                icon.Name = "DropdownChevron"
                icon.Size = UDim2.fromOffset(14, 14)
                icon.Position = UDim2.fromScale(0.5, 0.5)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1
                icon.Image = Config.DropdownChevronIcon
                icon.ImageColor3 = Color3.fromRGB(140, 140, 150)
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = arrow

                local function syncRotation()
                    icon.Rotation = arrow.Text == "▴" and 180 or 0
                end

                syncRotation()
                arrow.TextTransparency = 1
                arrow:GetPropertyChangedSignal("Text"):Connect(syncRotation)
            end
        end
    end

    local mainTab = window:Tab({ Name = "Main" })

    mainTab:Toggle({
        Name = "Auto 2x speed",
        StartingState = auto2xEnabled,
        Callback = function(state)
            auto2xEnabled = state
            selectedSpeed = state and 2 or 1
            settings.Set("Auto2x", state)

            if not recorder:IsRecording() then
                recorder:SetGameSpeed(selectedSpeed)
            end

            local ok, err = adapter:SetGameSpeed(selectedSpeed)
            if not ok then
                notify("Speed", err)
            end

            if player:IsPlaying() then
                player:Stop()
                adapter:ResetRegistry()

                task.defer(function()
                    if arm then
                        arm()
                    end
                end)
            end
        end,
    })

    local autoNextToggle
    local autoReplayToggle

    autoNextToggle = mainTab:Toggle({
        Name = "Auto Next",
        StartingState = autoNextEnabled,
        Callback = function(state)
            autoNextEnabled = state
            settings.Set("AutoNext", state)

            if state and autoReplayToggle then
                autoReplayEnabled = false
                settings.Set("AutoReplay", false)
                autoReplayToggle:Set(false)
            end
        end,
    })

    autoReplayToggle = mainTab:Toggle({
        Name = "Auto Replay",
        StartingState = autoReplayEnabled,
        Callback = function(state)
            autoReplayEnabled = state
            settings.Set("AutoReplay", state)

            if state and autoNextToggle then
                autoNextEnabled = false
                settings.Set("AutoNext", false)
                autoNextToggle:Set(false)
            end
        end,
    })

    mainTab:Button({
        Name = "Dismiss reward popup",
        Callback = function()
            local ok, err = adapter:DismissRewardPopup()
            if not ok then
                notify("Reward popup", err)
            end
        end,
    })

    mainTab:Credit({
        Name = "polosa__",
        Description = "Anime Paradox X (v3.23)",
    })

    local macroTab = window:Tab({ Name = "Macro" })
    local status = macroTab:Section("Select or create a macro")
    local dropdown

    local recordedActionNames = {
        PlaceUnit = "Place",
        UpgradeUnit = "Upgrade",
        SellUnit = "Sell",
    }

    local recordingName = nil
    local latestRecordedAction = nil
    local playingName = nil
    local latestPlayedAction = nil

    local function describeRecordedAction(action)
        local actionName = recordedActionNames[action.Type]
            or tostring(action.Type)
        local details = nil

        if action.Type == "PlaceUnit" then
            details = action.Label or action.Unit
        elseif type(action.Pos) == "string"
            and not string.find(action.Pos, "UNRESOLVED:", 1, true) then
            details = action.Pos
        end

        if details then
            return actionName .. " " .. details
        end

        return actionName
    end

    local function renderRecordingStatus()
        if not recordingName then
            return
        end

        local text = "Recording " .. recordingName
        if latestRecordedAction then
            text = text .. "\n\n" .. describeRecordedAction(
                latestRecordedAction
            )
        end

        status.Text = text
    end

    local function renderPlayingStatus()
        if not playingName then
            return
        end

        local text = "Playing macro " .. playingName
        if latestPlayedAction then
            text = text .. "\n\n" .. describeRecordedAction(
                latestPlayedAction
            )
        end

        status.Text = text
    end

    local function refreshMacroList()
        dropdown:Clear()
        dropdown:AddItems(Storage.List())
    end

    arm = function(waitForReset)
        if not playEnabled
            or not selectedName
            or recorder:IsRecording()
            or player:IsPlaying() then
            return
        end

        local macro, loadError = Storage.Load(selectedName)
        if not macro or countActions(macro) == 0 then
            status.Text = "Cannot play: " .. tostring(loadError or "empty macro")
            return
        end

        local macroName = selectedName
        local ok, playError = player:Play(macro, {
            PlaybackSpeed = selectedSpeed,
            WaitForReset = waitForReset == true,
            OnWaiting = function(wave)
                playingName = nil
                latestPlayedAction = nil
                status.Text = "Armed; waiting for wave " .. tostring(wave)
            end,
            OnStarted = function()
                playingName = macroName
                latestPlayedAction = nil
                renderPlayingStatus()
            end,
            OnActionPlayed = function(action)
                latestPlayedAction = action
                renderPlayingStatus()
            end,
            OnFinished = function(success, message)
                playingName = nil
                latestPlayedAction = nil

                if not success then
                    status.Text = "Stopped: " .. tostring(message)
                    return
                end

                status.Text = "Macro completed; waiting for Replay or Next"
            end,
        })

        if not ok then
            status.Text = "Cannot arm: " .. tostring(playError)
        end
    end

    dropdown = macroTab:Dropdown({
        Name = "Select macro",
        Items = Storage.List(),
        StartingText = selectedName or "Select a macro...",
        Callback = function(item)
            local name = typeof(item) == "table" and item[1] or item
            if not name or name == "" then
                return
            end

            player:Stop()
            adapter:ResetRegistry()
            selectedName = name
            settings.Set("SelectedMacro", name)

            local macro, loadError = Storage.Load(name)
            if macro then
                status.Text = ("Selected: %s (%d actions)"):format(
                    name,
                    countActions(macro)
                )
            else
                status.Text = tostring(loadError)
            end

            arm()
        end,
    })

    macroTab:Button({
        Name = "Refresh list",
        Callback = refreshMacroList,
    })

    macroTab:Textbox({
        Name = "New macro",
        Placeholder = "macro name",
        Callback = function(text)
            local ok, result = Storage.CreateEmpty(text, selectedSpeed)
            if not ok then
                notify("Storage", result)
                return
            end

            selectedName = result
            settings.Set("SelectedMacro", result)
            refreshMacroList()
            status.Text = "Created: " .. result
        end,
    })

    local recordToggle
    local suppressRecordCallback = false

    local function setRecordToggle(value)
        suppressRecordCallback = true
        recordToggle:Set(value)
        suppressRecordCallback = false
    end

    recordToggle = macroTab:Toggle({
        Name = "Record macro",
        StartingState = false,
        Callback = function(state)
            if suppressRecordCallback then
                return
            end

            if state then
                if not selectedName then
                    notify("Macro", "Select or create a macro")
                    setRecordToggle(false)
                    return
                end

                local oldMacro = Storage.Load(selectedName)
                if oldMacro
                    and countActions(oldMacro) > 0
                    and os.clock() > overwriteConfirmUntil then
                    overwriteConfirmUntil = os.clock() + 8
                    notify(
                        "Overwrite",
                        "Enable Record again within 8 seconds",
                        8
                    )
                    setRecordToggle(false)
                    return
                end

                player:Stop()
                adapter:ResetRegistry()
                recorder:SetGameSpeed(selectedSpeed)
                adapter:SetGameSpeed(selectedSpeed)

                local ok, recordError = recorder:Start()
                if not ok then
                    notify("Macro", recordError)
                    setRecordToggle(false)
                    return
                end

                recordingName = selectedName
                latestRecordedAction = nil
                renderRecordingStatus()

                task.spawn(function()
                    while recorder:IsRecording()
                        and recordingName == selectedName do
                        local actions = recorder.Actions
                        latestRecordedAction = actions[#actions]
                        renderRecordingStatus()
                        task.wait(0.1)
                    end
                end)

                return
            end

            if recorder:IsRecording() then
                local macro = recorder:Stop()
                recordingName = nil
                latestRecordedAction = nil

                local resolved, resolveError = adapter:WaitForPendingActions(
                    Config.EntityCaptureTimeout
                )

                if not resolved then
                    status.Text = "Save failed: " .. tostring(resolveError)
                    notify("Macro", resolveError, 5)
                    return
                end

                local ok, saveError = Storage.Save(selectedName, macro)

                if ok then
                    status.Text = ("Saved %d actions"):format(countActions(macro))
                else
                    status.Text = "Save failed: " .. tostring(saveError)
                end

                refreshMacroList()
            end
        end,
    })

    local playToggle

    playToggle = macroTab:Toggle({
        Name = "Play macro",
        StartingState = playEnabled,
        Callback = function(state)
            playEnabled = state
            settings.Set("PlayMacro", state)

            if state then
                if arm then
                    arm()
                end
                return
            end

            player:Stop()
            adapter:ResetRegistry()
            playingName = nil
            latestPlayedAction = nil
            status.Text = "Playback disabled"
        end,
    })

    if auto2xEnabled then
        recorder:SetGameSpeed(2)
        adapter:SetGameSpeed(2)
    end

    if playEnabled and selectedName then
        task.defer(function()
            arm()
        end)
    end

    task.spawn(function()
        while window.Gui and window.Gui.Parent do
            local autoActionEnabled = autoNextEnabled or autoReplayEnabled
            local rewardPopupVisible = adapter:IsRewardPopupVisible()

            if autoActionEnabled
                and rewardPopupVisible
                and os.clock() >= nextRewardClickAt then
                nextRewardClickAt = os.clock() + 0.5

                local dismissed, dismissError = adapter:DismissRewardPopup()
                if not dismissed then
                    notify("Reward popup", dismissError, 5)
                end
            elseif not rewardPopupVisible then
                local finished, evidence = adapter:IsMatchFinished()

                if finished and not matchEndLatched then
                    matchEndLatched = true
                    player:Stop()
                    adapter:ResetRegistry()

                    local actionOk = true
                    local actionError = nil
                    local actionName = nil

                    if autoReplayEnabled then
                        actionName = "Replay"
                        actionOk, actionError = adapter:Replay()
                    elseif autoNextEnabled then
                        actionName = "Next"
                        actionOk, actionError = adapter:NextStage()
                    end

                    if actionName and not actionOk then
                        notify("Auto " .. actionName, actionError, 5)
                    elseif actionName then
                        status.Text = actionName .. " sent; waiting for next match"

                        if playEnabled then
                            task.defer(function()
                                arm(true)
                            end)
                        end
                    else
                        status.Text = "Match finished: "
                            .. tostring(evidence or "result GUI")
                    end
                elseif not finished then
                    matchEndLatched = false
                end
            end

            task.wait(Config.MatchEndPollInterval)
        end
    end)

    task.defer(styleDropdownArrows)

    return {
        window = window,
        recorder = recorder,
        player = player,
    }
end

return Interface
