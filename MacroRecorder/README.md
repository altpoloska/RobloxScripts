# PoloskaLib Macro Recorder

Record & replay macro for tower-defense Roblox games, using [PoloskaLib](https://github.com/altpoloska/PoloskaLib) for the UI. Structured for `luabundler`: recording logic, playback, storage and UI are separate modules.

## Structure

```
src/
├── Main.lua              -- entry point + game adapter (GetWave / Dispatch)
├── Config.lua            -- game speed, hotkeys, folder name
├── Macro/
│   ├── Actions.lua       -- action constructors + CFrame <-> Pos string
│   ├── Recorder.lua      -- records ordered actions with wave+time
│   ├── Player.lua        -- replays actions respecting wave+time
│   └── Storage.lua       -- JSON (de)serialize in target format + save/load
└── UI/
    └── Interface.lua     -- PoloskaLib window & tabs
```

## Build

```bash
luabundler bundle ./src/Main.lua -o ./dist/MacroRecorder.lua
```

## Macro format

Flat JSON object keyed by sequential action number (as string), plus a special `"Game Speed"` key:

```json
{
  "Game Speed": 1.5,
  "1": { "Type": "VoteSkip", "Time": "0 4.881981134414673" },
  "2": { "Type": "PlaceUnit", "Unit": "Bulmo", "Time": "1 2.8764352798461914",
          "Pos": "1014.22052, -229.038589, 1378.0011, 1, 0, 0, 0, 1, 0, 0, 0, 1" },
  "3": { "Type": "UpgradeUnit", "Time": "2 2.437314748764038", "Pos": "Fastcart - 1" }
}
```

### `Time`
`"<wave> <secondsSinceWaveStart>"` — wave number and seconds elapsed since that wave began.

### Action types

| Type | Extra fields | `Pos` meaning |
| --- | --- | --- |
| `VoteSkip` | — | — |
| `PlaceUnit` | `Unit` | 12 CFrame components: `x, y, z, r00..r22` |
| `UpgradeUnit` | — | `"Unit name - index"` |
| `ChangePriority` | `Prio` | `"Unit name - index"` |
| `UseAbility` | `Abi` | `"Unit name - index"` |
| `ConfirmTowerLink` | — | `"Unit name - index"` |

## Wiring to your game

In `Main.lua`:
1. `GetWave()` — return the current wave number.
2. `Dispatch(action, ctx)` — perform an action in-game on playback (`ctx.cframe` is the decoded CFrame for `PlaceUnit`).
3. Call recorder hooks (`recorder:PlaceUnit(...)`, `recorder:UpgradeUnit(...)`, etc.) from your game input/remote intercepts while recording.

Created by `polosa__`.
