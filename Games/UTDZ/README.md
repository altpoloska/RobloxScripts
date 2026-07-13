# PoloskaLib Macro Recorder

Record & replay macro for a Knit-based tower-defense Roblox game, using [PoloskaLib](https://github.com/altpoloska/PoloskaLib) for the UI. Structured for `luabundler`: recording, playback, storage, game hooks and UI are separate modules.

## Structure

```
src/
├── Main.lua               -- entry point: GetWave + hotbar/workspace resolvers
├── Config.lua             -- game speed, hotkeys, folder name
├── Macro/
│   ├── Actions.lua        -- action constructors + CFrame <-> Pos string
│   ├── Recorder.lua       -- records ordered actions with wave+time
│   ├── Player.lua         -- replays actions respecting wave+time
│   ├── Storage.lua        -- JSON (de)serialize in target format + save/load
│   ├── UnitRegistry.lua   -- maps volatile UUIDs <-> "Name - N" identity
│   └── GameAdapter.lua    -- remotes, __namecall hook (record) + Dispatch (replay)
└── UI/
    └── Interface.lua      -- PoloskaLib window & tabs
```

## Build

```bash
luabundler bundle ./src/Main.lua -p "./src/?.lua" -o ./dist/MacroRecorder.lua
```

`-p "./src/?.lua"` is required. `luabundler` resolves each `require` by substituting the string into the `?` pattern (relative to `./src`), NOT relative to the requiring file. So all `require` strings use dot-notation from the `src` root, e.g. `require("Config")`, `require("Macro.GameAdapter")`, `require("UI.Interface")` — do not use `./` or `../` relative paths from subfolders, they will not resolve.

## Wave source

Read from GUI text and parse the leading number:
```
PlayerGui.GameUI.HUD.Upper.WaveInformations.Container.Wave.Text
  = "Wave 10<font color=\"#939393\">/15</font>"  ->  10
```

## Unit identity strategy

- **Name** comes from the **hotbar by slot** (`PlaceUnit` sends `slot`, hotbar is ordered) -> `GetHotbarUnitName(slot)`. The macro stores the name (portable), not the raw slot.
- **UUID** is captured by **diffing the workspace unit list** around the `PlaceUnit` call (snapshot before, find the new id after; falls back to the remote return value if it is a string). The `UnitRegistry` maps that UUID to a stable `"Name - N"` identity (N = Nth placement of that name), matching the `Pos` field in example.json.
- `UpgradeUnit`/`SellUnit` send a UUID -> registry returns `"Name - N"`.
- On replay the registry resets and rebuilds in the same placement order, so labels resolve to the current session's UUIDs.

## Remotes (from captured InvokeServer calls)

| Remote (Knit RF) | Args | Action |
| --- | --- | --- |
| `WaveService.RF.Vote` | `(true)` | `VoteSkip` |
| `TowerService.RF.PlaceUnit` | `(slot:number, cframe:CFrame)` | `PlaceUnit` |
| `TowerService.RF.UpgradeUnit` | `(uuid:string)` | `UpgradeUnit` |
| `TowerService.RF.SellUnit` | `(uuid:string)` | `SellUnit` |
| `TowerService.RF.ChangePriority` | `(uuid:string, prio:number)` | `ChangePriority` |

## Wired to the game

- **Hotbar** (`getHotbar` in `Main.lua`): `PlayerGui.GameUI.HUD.Bottom.Hotbar.Units`. Slots (`ContainerBig` / `Locked`) are sorted by `AbsolutePosition` (top-to-bottom) so the index matches the `slot` sent by `PlaceUnit`; `Locked` slots keep their index but have no name. Name is read from `ContainerBig.Unit.UnitInfomation.RightInfos.UnitName.Text`.
- **Placed units** (`ListPlacedUnitIds`): `workspace.Ignore.Units`, skipping children with purely numeric names (enemies); everything else is treated as a placed unit.

### Assumption to verify

The `slot` number from `PlaceUnit` is assumed to count **all** hotbar slots including `Locked`. If it only counts unlocked (`ContainerBig`) slots, filter `getHotbarSlots()` to `ContainerBig` only.

## Still needed

Remotes for `UseAbility` and `ConfirmTowerLink` are not captured yet — add them to `GameAdapter` once known (stubs are in place).

## Macro format

```json
{
  "Game Speed": 1.5,
  "1": { "Type": "VoteSkip", "Time": "0 4.881981134414673" },
  "2": { "Type": "PlaceUnit", "Unit": "Bulmo", "Time": "1 2.8764352798461914",
          "Pos": "1014.22052, -229.038589, 1378.0011, 1, 0, 0, 0, 1, 0, 0, 0, 1" },
  "3": { "Type": "UpgradeUnit", "Time": "2 2.437314748764038", "Pos": "Fastcart - 1" }
}
```

`Time` = `"<wave> <secondsSinceWaveStart>"` (seconds reset each wave).

Created by `polosa__`.
