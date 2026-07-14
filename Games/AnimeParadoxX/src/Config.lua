local Config = {
    ToggleKey = Enum.KeyCode.RightControl,
    FolderName = "PoloskaMacros",
    GameFolderName = "AnimeParadoxX",

    DefaultGameSpeed = 1,
    SupportedSpeeds = { 1, 2 },
    DropdownChevronIcon = "rbxassetid://10709790948",
    FormatVersion = 4,
    TimeBasis = "game_seconds",

    EntityCaptureTimeout = 3,
    MatchEndPollInterval = 0.25,
    WaveWaitTimeout = 300,
    DispatchRetries = 3,
    DispatchRetryDelay = 0.25,
    PositionRandomOffsetMin = 0.001,
    PositionRandomOffsetMax = 0.01,
}

return Config
