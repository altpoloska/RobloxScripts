local Config = {
    ToggleKey = Enum.KeyCode.RightControl,
    RecordKey = Enum.KeyCode.F6,
    PlayKey = Enum.KeyCode.F7,
    FolderName = "PoloskaMacros",

    DefaultGameSpeed = 1.5,
    SupportedSpeeds = { 1, 1.5 },
    FormatVersion = 2,
    TimeBasis = "game_seconds",

    UnitCaptureTimeout = 2,
    PendingResolveTimeout = 3,
    WaveWaitTimeout = 300,
    ReadyTimeout = 60,
    DispatchRetries = 3,
    DispatchRetryDelay = 0.25,
}

return Config
