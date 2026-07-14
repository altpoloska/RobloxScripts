local RunService = game:GetService("RunService")
local Config = require("src.Config")
local Storage = require("src.Macro.Storage")
local Actions = require("src.Macro.Actions")

local Player = {}
Player.__index = Player

local positionRng = Random.new()

local function addPositionRandomOffset(cf)
    local minOffset = tonumber(Config.PositionRandomOffsetMin) or 0.001
    local maxOffset = tonumber(Config.PositionRandomOffsetMax) or 0.01
    if minOffset < 0 or maxOffset < minOffset then return cf end

    -- Random direction plus a guaranteed non-zero distance from the saved point.
    local angle = positionRng:NextNumber(0, math.pi * 2)
    local distance = positionRng:NextNumber(minOffset, maxOffset)
    return cf + Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )
end

function Player.new(opts)
    opts = opts or {}
    return setmetatable({
        Playing = false,
        Waiting = false,
        _getWave = opts.GetWave or function() return nil end,
        _dispatch = opts.Dispatch or function() return false, "No dispatcher" end,
        _onStart = opts.OnStart or function() end,
        _session = 0,
    }, Player)
end

local function logicalTargetSeconds(macro, storedSeconds)
    if macro["Time Basis"] == "game_seconds" then
        return storedSeconds
    end
    return storedSeconds * (tonumber(macro["Game Speed"]) or 1)
end

function Player:Play(macro, options)
    if self.Playing then return true, "Already armed" end

    local valid, validationError = Storage.Validate(macro, false)
    if not valid then return false, validationError end

    local list = Storage.ToOrderedList(macro)
    if #list == 0 then return false, "Macro contains no actions" end

    options = options or {}
    local playbackSpeed = tonumber(options.PlaybackSpeed) or tonumber(macro["Game Speed"]) or 1
    local waitForReset = options.WaitForReset == true
    local supported = false
    for _, value in ipairs(Config.SupportedSpeeds) do
        if playbackSpeed == value then
            supported = true
            break
        end
    end
    if not supported then return false, "Unsupported playback speed" end

    local firstWave = Storage.ParseTime(list[1].action.Time)
    if type(firstWave) ~= "number" then return false, "Invalid first action time" end

    self.Playing = true
    self.Waiting = true
    self._session = self._session + 1
    local session = self._session
    local onFinished = options.OnFinished
    local onWaiting = options.OnWaiting
    local onStarted = options.OnStarted
    local onActionPlayed = options.OnActionPlayed

    task.spawn(function()
        local done = false
        local function finish(success, message)
            if done then return end
            done = true
            if self._session == session then
                self.Playing = false
                self.Waiting = false
            end
            if onFinished then onFinished(success, message) end
        end

        if onWaiting then onWaiting(firstWave, self._getWave()) end

        -- AFK mode: if the current match has already passed the macro start wave,
        -- wait for the wave counter to reset, then wait for firstWave.
        local waitStarted = os.clock()
        local currentWave = self._getWave()

        if waitForReset then
            local resetBaseline = currentWave

            while self.Playing and self._session == session do
                currentWave = self._getWave()

                if type(resetBaseline) ~= "number"
                    and type(currentWave) == "number" then
                    resetBaseline = currentWave
                elseif type(resetBaseline) == "number"
                    and type(currentWave) == "number"
                    and currentWave < resetBaseline then
                    break
                end

                if os.clock() - waitStarted > Config.WaveWaitTimeout then
                    finish(false, "Timeout waiting for wave reset")
                    return
                end

                RunService.Heartbeat:Wait()
            end
        end

        while self.Playing and self._session == session do
            currentWave = self._getWave()
            if type(currentWave) == "number" and currentWave <= firstWave then break end
            if os.clock() - waitStarted > Config.WaveWaitTimeout then
                finish(false, "Timeout waiting for the next match")
                return
            end
            RunService.Heartbeat:Wait()
        end

        while self.Playing and self._session == session do
            currentWave = self._getWave()
            if type(currentWave) == "number" and currentWave == firstWave then break end
            if type(currentWave) == "number" and currentWave > firstWave then
                -- The counter jumped over the start wave. Wait for another reset.
                repeat
                    RunService.Heartbeat:Wait()
                    currentWave = self._getWave()
                until not self.Playing or self._session ~= session
                    or (type(currentWave) == "number" and currentWave <= firstWave)
            end
            if os.clock() - waitStarted > Config.WaveWaitTimeout then
                finish(false, "Timeout waiting for macro start wave")
                return
            end
            RunService.Heartbeat:Wait()
        end

        if not self.Playing or self._session ~= session then
            finish(false, "Stopped")
            return
        end

        self.Waiting = false
        self._onStart(playbackSpeed)

        if onStarted then
            local callbackOk, callbackError = pcall(onStarted)
            if not callbackOk then
                warn("[MacroPlayer] start status callback failed:", callbackError)
            end
        end

        currentWave = firstWave
        local waveClock = os.clock()

        for _, entry in ipairs(list) do
            if not self.Playing or self._session ~= session then
                finish(false, "Stopped")
                return
            end

            local action = entry.action
            local targetWave, storedSeconds = Storage.ParseTime(action.Time)
            local targetLogical = logicalTargetSeconds(macro, storedSeconds)
            local actionWaitStarted = os.clock()

            while self.Playing and self._session == session do
                local wave = self._getWave()
                if type(wave) == "number" and wave ~= currentWave then
                    currentWave = wave
                    waveClock = os.clock()
                end

                local elapsedLogical = (os.clock() - waveClock) * playbackSpeed
                local actionIsDue = currentWave > targetWave
                    or (
                        currentWave == targetWave
                        and elapsedLogical >= targetLogical
                    )

                if actionIsDue then
                    break
                end

                if os.clock() - actionWaitStarted > Config.WaveWaitTimeout then
                    finish(false, ("Action #%d: wave wait timeout"):format(entry.index))
                    return
                end
                RunService.Heartbeat:Wait()
            end

            local ctx = {}
            if action.Type == "PlaceUnit" then
                local position, positionError = Actions.decodePosition(action.Pos)
                if not position then
                    finish(false, ("Action #%d: %s"):format(entry.index, positionError))
                    return
                end
                -- Keep the saved macro unchanged, but slightly vary X/Z on playback.
                ctx.position = addPositionRandomOffset(CFrame.new(position)).Position
            end

            local success, dispatchError = false, nil
            for attempt = 1, Config.DispatchRetries do
                local callOk, result, message = pcall(self._dispatch, action, ctx)
                if callOk and result then
                    success = true
                    break
                end
                dispatchError = callOk and message or result
                if attempt < Config.DispatchRetries then
                    task.wait(Config.DispatchRetryDelay * attempt)
                end
            end

            if not success then
                finish(false, ("Action #%d (%s) failed: %s"):format(
                    entry.index,
                    tostring(action.Type),
                    tostring(dispatchError)
                ))
                return
            end

            if onActionPlayed then
                local callbackOk, callbackError = pcall(
                    onActionPlayed,
                    action,
                    entry.index
                )

                if not callbackOk then
                    warn(
                        "[MacroPlayer] action status callback failed:",
                        callbackError
                    )
                end
            end
        end

        finish(true, "Completed")
    end)

    return true
end

function Player:Stop()
    self.Playing = false
    self.Waiting = false
    self._session = self._session + 1
end

function Player:IsPlaying() return self.Playing end
function Player:IsWaiting() return self.Waiting end

return Player
