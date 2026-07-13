local Interface = {}

function Interface.new(deps)
    local lib, Config, Storage = deps.PoloskaLib, deps.Config, deps.Storage
    local recorder, player, automation = deps.Recorder, deps.Player, deps.Automation

    local selectedName = nil
    local selectedSpeed = Config.DefaultGameSpeed
    local endAction = nil
    local autoToggles = {}
    local handlingFinish = false
    local playEnabled = false
    local overwriteConfirmUntil = 0
    local waitForResultAfterRecord = false

    local window = lib:Create({
        Name = "Poloska Macro Recorder",
        Size = UDim2.fromOffset(660, 480),
        ToggleKey = Config.ToggleKey,
    })

    local function notify(title, text, duration)
        window:Notification({ Title = title, Text = text, Duration = duration or 3 })
    end

    local function countActions(macro)
        return #Storage.ToOrderedList(macro)
    end

    local mainTab = window:Tab({ Name = "Main" })
    mainTab:Section("AFK playback: persistent while Play Macro is enabled")
    mainTab:Section("End of game")

    local function makeAuto(name, key)
        local toggle
        toggle = mainTab:Toggle({
            Name = name,
            StartingState = false,
            Callback = function(state)
                if state then
                    endAction = key
                    for otherKey, other in pairs(autoToggles) do
                        if otherKey ~= key then other:Set(false) end
                    end
                    notify("AFK", name .. " enabled", 2)
                elseif endAction == key then
                    endAction = nil
                end
            end,
        })
        autoToggles[key] = toggle
    end

    makeAuto("Auto Replay", "replay")
    makeAuto("Auto Vote Next", "next")
    makeAuto("Auto Leave", "leave")
    mainTab:Credit({ Name = "polosa__", Description = "PoloskaLib Macro Recorder v2.3" })

    local macroTab = window:Tab({ Name = "Macro" })
    local status = macroTab:Section("AFK: select or create a macro")
    local dropdown

    local function refresh()
        dropdown:Clear()
        dropdown:AddItems(Storage.List())
    end

    local function startArmedPlayback()
        if not playEnabled then return false end
        if not selectedName or recorder:IsRecording() then return false end
        if player:IsPlaying() then return true end

        local macro, loadError = Storage.Load(selectedName)
        if not macro then
            status.Text = "Load failed: " .. tostring(loadError)
            return false
        end

        if countActions(macro) == 0 then
            status.Text = "Selected empty macro: " .. selectedName
            return false
        end

        local ok, playError = player:Play(macro, {
            PlaybackSpeed = selectedSpeed,
            OnWaiting = function(firstWave, currentWave)
                status.Text = ("AFK armed: waiting for wave %d (current %s)"):format(
                    firstWave,
                    tostring(currentWave)
                )
            end,
            OnFinished = function(success, message)
                if success then
                    status.Text = "Macro completed; waiting for mission result"
                elseif message ~= "Stopped" then
                    status.Text = "Playback stopped: " .. tostring(message)
                    notify("Playback", tostring(message), 5)
                end
            end,
        })

        if not ok then
            status.Text = "Cannot arm: " .. tostring(playError)
            return false
        end
        return true
    end

    dropdown = macroTab:Dropdown({
        Name = "Select macro",
        Items = Storage.List(),
        StartingText = "Select a macro...",
        Callback = function(item)
            local name = typeof(item) == "table" and item[1] or item
            if not name or name == "" then return end

            local macro, loadError = Storage.Load(name)
            if not macro then
                notify("Storage", tostring(loadError))
                return
            end

            player:Stop()
            automation.ResetPlayback()
            selectedName = name
            waitForResultAfterRecord = false

            if countActions(macro) == 0 then
                status.Text = "Selected empty macro: " .. name
            else
                status.Text = ("Selected: %s (%d actions); AFK armed"):format(
                    name,
                    countActions(macro)
                )
                startArmedPlayback()
            end
        end,
    })

    macroTab:Button({ Name = "Refresh list", Callback = refresh })

    macroTab:Textbox({
        Name = "New macro",
        Placeholder = "macro name",
        Callback = function(text)
            local ok, result = Storage.CreateEmpty(text, selectedSpeed)
            if not ok then
                notify("Storage", tostring(result))
                return
            end

            player:Stop()
            automation.ResetPlayback()
            selectedName = result
            waitForResultAfterRecord = false
            refresh()
            status.Text = "Created and selected empty macro: " .. selectedName
            notify("Storage", selectedName .. " added to dropdown", 2)
        end,
    })

    macroTab:Dropdown({
        Name = "Current game speed",
        Items = { "x1", "x1.5" },
        StartingText = "x" .. tostring(selectedSpeed),
        Callback = function(item)
            local value = typeof(item) == "table" and item[1] or item
            selectedSpeed = value == "x1.5" and 1.5 or 1
            if not recorder:IsRecording() then recorder:SetGameSpeed(selectedSpeed) end

            if selectedName and player:IsPlaying() then
                player:Stop()
                startArmedPlayback()
            end
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
            if suppressRecordCallback then return end

            if state then
                if not selectedName then
                    notify("Macro", "Select or create a macro")
                    setRecordToggle(false)
                    return
                end

                local oldMacro, loadError = Storage.Load(selectedName)
                if not oldMacro then
                    notify("Storage", tostring(loadError))
                    setRecordToggle(false)
                    return
                end

                local oldCount = countActions(oldMacro)
                if oldCount > 0 and os.clock() > overwriteConfirmUntil then
                    overwriteConfirmUntil = os.clock() + 8
                    notify(
                        "Overwrite warning",
                        ("%s already contains %d actions. Enable Record again within 8 seconds to overwrite it."):format(
                            selectedName,
                            oldCount
                        ),
                        8
                    )
                    status.Text = "Recording cancelled: confirmation required"
                    setRecordToggle(false)
                    return
                end

                overwriteConfirmUntil = 0
                player:Stop()
                automation.ResetPlayback()
                recorder:SetGameSpeed(selectedSpeed)
                local ok, recordError = recorder:Start()
                if not ok then
                    notify("Macro", tostring(recordError))
                    setRecordToggle(false)
                    return
                end

                waitForResultAfterRecord = false
                status.Text = ("Recording %s at x%s"):format(selectedName, selectedSpeed)
            elseif recorder:IsRecording() then
                local macro = recorder:Stop()
                local ok, saveError = Storage.Save(selectedName, macro)
                if not ok then
                    notify("Storage", tostring(saveError))
                    status.Text = "Save failed"
                    return
                end

                refresh()
                waitForResultAfterRecord = true
                status.Text = ("Saved %d actions; AFK armed for the next match"):format(
                    countActions(macro)
                )
                notify("AFK", "Recording saved. You can leave it running.", 3)
            end
        end,
    })

    macroTab:Keybind({
        Name = "Toggle recording",
        Keybind = Config.RecordKey,
        Callback = function()
            setRecordToggle(not recorder:IsRecording())
            if not recorder:IsRecording() then
                -- Set() was suppressed above, so invoke the intended transition.
                recordToggle:Set(true)
            else
                recordToggle:Set(false)
            end
        end,
    })

    macroTab:Section("Persistent playback")

    local playToggle
    playToggle = macroTab:Toggle({
        Name = "Play macro",
        StartingState = false,
        Callback = function(state)
            playEnabled = state

            if state then
                if not selectedName then
                    status.Text = "Play enabled: select or create a macro"
                    notify("Macro", "Play is enabled; select a macro", 3)
                    return
                end

                local macro, loadError = Storage.Load(selectedName)
                if not macro then
                    status.Text = "Load failed: " .. tostring(loadError)
                    notify("Storage", tostring(loadError), 4)
                    return
                end

                if countActions(macro) == 0 then
                    status.Text = "Play enabled; selected macro is empty"
                    return
                end

                status.Text = "Play enabled; persistent AFK playback armed"
                startArmedPlayback()
            else
                player:Stop()
                automation.ResetPlayback()
                status.Text = "Play disabled; macro remote events are stopped"
            end
        end,
    })

    macroTab:Keybind({
        Name = "Toggle persistent playback",
        Keybind = Config.PlayKey,
        Callback = function()
            playToggle:Set(not playEnabled)
        end,
    })

    automation.OnFinishedChanged(function(enabled)
        if not enabled then
            handlingFinish = false
            return
        end
        if handlingFinish then return end
        handlingFinish = true

        player:Stop()
        automation.ResetPlayback()
        waitForResultAfterRecord = false
        status.Text = "Mission result detected; playback reset"

        task.spawn(function()
            local wantedButton = nil
            if endAction == "replay" then wantedButton = "replay" end
            if endAction == "next" then wantedButton = "next" end
            if endAction == "leave" then wantedButton = "lobby" end

            if endAction then
                local buttonsReady, buttonInfo = automation.WaitForResultButtons(
                    wantedButton,
                    Config.ReadyTimeout
                )
                if not buttonsReady then
                    notify("Automation", tostring(buttonInfo), 5)
                else
                    local actionOk, actionError
                    if endAction == "replay" then
                        actionOk, actionError = automation.VoteReplay()
                    elseif endAction == "next" then
                        actionOk, actionError = automation.VoteNext()
                    elseif endAction == "leave" then
                        actionOk, actionError = automation.Leave()
                    end
                    if actionOk == false then
                        notify("Automation", tostring(actionError), 5)
                    end
                end
            end

            -- PlayMacro is permanently armed. It now waits through the old wave,
            -- the reset, and the first wave stored in the macro.
            startArmedPlayback()

            if endAction == "replay" or endAction == "next" then
                local closed = automation.WaitForMissionClosed(Config.ReadyTimeout)
                if closed then automation.AutoStart() end
            end
        end)
    end)

    return { window = window, recorder = recorder, player = player }
end

return Interface
