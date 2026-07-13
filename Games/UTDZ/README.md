# PoloskaLib Macro Recorder — fixed v2

Исправленная версия UTDZ macro recorder.

## Главные исправления

- Label юнита резервируется синхронно, UUID привязывается позже без перестановки `Name - N`.
- Быстрые Upgrade/Sell/ChangePriority ожидают привязку UUID.
- Проверяются JSON, CFrame, имена файлов, remotes и наличие юнита в hotbar.
- Playback прекращается с понятной ошибкой вместо молчаливого рассинхрона.
- End-game restart ждёт готовности UI/workspace вместо фиксированных пауз.
- Старые макросы v1 поддерживаются.

## Скорости x1 и x1.5

Формат v2 хранит `Time` в **логических игровых секундах**, а не в реальных секундах компьютера.

- При записи x1: `logical = real * 1`.
- При записи x1.5: `logical = real * 1.5`.
- При воспроизведении: действие выполняется, когда `realElapsed * currentPlaybackSpeed >= logicalTimestamp`.

Поэтому один макрос можно записать на x1.5 и проиграть на x1, либо наоборот. Отдельные файлы для скоростей не нужны. В UI `Current game speed` должен соответствовать фактической скорости матча; скрипт не переключает скорость игры сам.

Старый v1 timestamp считался реальным временем. При загрузке он автоматически переводится в логическое время как `oldSeconds * macro["Game Speed"]`.

## Build

```bash
luabundler bundle ./src/Main.lua -p "./src/?.lua" -o ./dist/MacroRecorder.lua
```

Результат: `dist/MacroRecorder.lua`.

## v2.2 AFK changes

- Playback is permanently armed after selecting a non-empty macro.
- Mission end is detected by `PlayerGui.GameUI.MissionResultFrameNew.Enabled`.
- Auto actions wait for visible `ImageLabel` controls under `PlayerGui.Finished.Page3`.
- Empty macros are created on disk immediately and appear in the dropdown.
- Recording over a non-empty macro requires a second confirmation within 8 seconds.
- After mission results, playback state resets and waits for the macro start wave in the next match.

## v2.3 persistent Play Macro toggle

- Restored the Play Macro toggle.
- While enabled, playback remains armed across matches and waits for the recorded start wave.
- Turning it off immediately stops playback and prevents further macro action remotes.
- Auto Replay/Next/Leave remain controlled by their own independent toggles.
