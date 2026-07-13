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
