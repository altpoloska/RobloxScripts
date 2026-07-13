# RemoteHooker 2.0

Remote-call inspector for authorized debugging of your own Roblox experiences.

## Improvements

- Safe snapshots of mutable tables and buffers.
- Raw arguments are kept separately from decoded/display values.
- Valid serialization of string table keys and common Roblox datatypes.
- Safe Instance expressions using `GetService` and `WaitForChild`.
- RichText escaping for captured strings.
- Captures `InvokeServer` return values.
- Minimal responsive interface with built-in `rbxasset://` control icons.
- Resizable and minimizable window with a vertically scrollable responsive action grid.
- Close-confirmation dialog and recording/pause title color.
- Search, method filters, grouping, remote blocking, and a `Reset exclusions` action.
- Editable multiline argument/code editor with live Lua syntax highlighting.
- Lightweight regular-weight status title that changes color without a text outline.
- Compile and runtime error reporting in the editor.
- `Run code` is the first action; `Edit remote` / `Lock editor` is the second.
- A visible blue caret tracks the cursor inside the syntax-highlighted editor.
- `Clear` resets the captured remote list, scrollbar, selection, counter, and editor.
- `Edit remote` explicitly unlocks editing, preventing packet clicks from overwriting work.
- `Run code` executes the modified generated call; `Reset editor` restores captured arguments.
- Zero-argument remotes are generated as `FireServer()` / `InvokeServer()` without an empty args table.
- Non-empty calls use `unpack(args)`; an explicit range is emitted only when nil arguments must be preserved.
- Includes a clickable author badge and a visible resize-corner indicator.
- Replay uses generated editable code and displays errors.
- Bounded 500-packet history with accurate total/retained counters.
- Calling-script and optional traceback display when supported.
- Optimized hot path: unrelated namecalls are forwarded without `table.pack` allocations.
- Unblocked captures are drained through a bounded batched queue instead of one deferred task per packet.
- Pausing recording disables packet copies, metadata collection, snapshots, and UI dispatch while preserving blocking rules.
- Path lookup is skipped until a path exclusion, pattern, or block is configured.
- `captureTraceback` defaults to `false` because stack collection is expensive; enable it in `src/settings.lua` only while diagnosing.
- Original direct `__namecall` forwarding with `setnamecallmethod(method)` and no `pcall` around `oldNamecall`.
- Hook and GUI connection cleanup on close.

## Files

- `RemoteHooker.lua` — bundled single-file build.
- `src/main.lua` — entry point.
- `src/network.lua` — remote interception.
- `src/ui.lua` — interface and actions.
- `src/utils.lua` — snapshots, paths and serialization.
- `src/settings.lua` — exclusions, blocks and limits.

## Build

Run `python3 build.py` from the project folder. No external dependencies are required.

## Compatibility

The runtime must provide `hookmetamethod`, `getnamecallmethod`, and `setnamecallmethod`. Optional APIs such as `checkcaller`, `getcallingscript`, `debug.traceback`, `gethui`, `setclipboard`, and `setthreadidentity` are detected before use.

Use only in experiences you own or where you have explicit authorization. Runtime visual testing must be performed in the target Roblox environment because executor APIs are not available in a normal Luau sandbox.
