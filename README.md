<!-- update:auto:start -->
# Automatic / Hotkey Gates

Project Zomboid **Build 42.20+** mod for dedicated multiplayer servers (works in singleplayer / Host too). Staff designate vehicle gates as automatic; players near a registered gate open or close it key-fob style — including from inside a vehicle — via hotkey, vehicle radial menu, or right-click.

Gate toggles run **server-side**; clients send intents only. Toggle/auto-close behavior is aligned with proven B42 Workshop gate mods (GateMotor, HydeCo, AutomaticSensorGate) — see [`.cursor/rules/gate-mod-references.mdc`](.cursor/rules/gate-mod-references.mdc).

| | |
|---|---|
| **Mod ID** | `AutoHotkeyGates` |
| **Version** | `1.0.1` |
| **Path** | [`auto-gate/mods/AutoHotkeyGates/`](auto-gate/mods/AutoHotkeyGates/) |
| **Target** | Build **42.20+** (`versionMin=42.20`) |

## Features

- **Designated gates only** — staff register multi-tile vehicle gates / garage doors (sandbox can allow any door)
- **Three triggers** — rebindable hotkey (default **G**), vehicle radial “Operate Gate”, right-click on the gate
- **Lock bypass** — fob opens locked gates; lock state is remembered and restored on close
- **Auto-close** — closes after N seconds after **any** open (hotkey, radial, context, or vanilla **E**); manual close before the timer cancels auto-close
- **Faction tags** — optional ACL at registration / **Change Tag...**: empty = public, one faction, or comma-separated list; Admin/Moderator bypass
- **Staff tools** — Moderator+ (default) can register, change tags, and unregister
- **Full sandbox page** — range, cooldown, locks, auto-close, staff level, interface toggles, debug logging

## Install (local testing)

Source lives in this repo. Junction it into your user mods folder so the game sees it directly (no copy step, no rebuild-and-restart-to-sync):

```
F:\Projects\pz-mods\auto-gate\mods\AutoHotkeyGates
  →  %USERPROFILE%\Zomboid\mods\AutoHotkeyGates   (mklink /J)
```

1. Enable **`AutoHotkeyGates`** in the mod menu (alongside Workshop mods — PZ merges both).
2. Load a world or join / Host a server.
3. Tune **Sandbox → Automatic Hotkey Gates**.

### Dedicated server

1. Copy or junction `AutoHotkeyGates` into the server mods path (or ship via Workshop later).
2. Add `AutoHotkeyGates` to `Mods=` in the server ini.
3. Set sandbox options on the server (or via admin sandbox editor).

## Quick start

1. As staff (**Moderator+** by default), right-click a large vehicle gate → **Automatic Gate → Register Automatic Gate...**
2. Leave the tag empty for public, type one faction (e.g. `Police`), or several comma-separated (`Police, Military`).
3. Bind the key under **Options → Key Bindings → Automatic Hotkey Gates** (default **G**).
4. Within range (default **7** tiles), on foot or in a vehicle:
   - Press the hotkey
   - Vehicle radial → **Operate Gate**
   - Right-click the gate → **Open/Close Gate**
5. Staff can later use **Change Tag...** or **Unregister Automatic Gate** on any registered gate.

## Sandbox options

| Option | Default | Purpose |
|--------|---------|---------|
| Trigger Range | 7 tiles | Fob distance |
| Trigger Cooldown | 1 s | Anti-spam |
| Vehicle Gates Only | on | Multi-tile gates only |
| Operate From Vehicle Only | off | Strict key-fob RP (hotkey/radial require a vehicle; context menu still works on foot) |
| Bypass Locks / Re-lock On Close | on / on | Lock behavior |
| Auto-Close Delay | 10 s | Seconds until auto-close after any open; **0 = off** |
| Auto-Close Safety Check | on | Don’t close on bodies/vehicles |
| Min Staff Level To Register | Moderator+ | Who can register / change tags / unregister |
| Max Registered Gates | 0 (unlimited) | Cap |
| Enforce Permission Hook | on | Master switch for faction-tag checks |
| Enable Hotkey / Radial / Context | on | Per-trigger toggles |
| Show Feedback Messages | on | Halo text |
| Debug Logging | off | `[AHG]` lines in `console.txt` |

Sandbox options are read live via `SandboxVars` where PZ allows (F1 admin sandbox edits). File-only dedicated edits may need a vanilla options reload or restart. **Existing saves keep old sandbox values** until you change them in that world.

## Faction permissions

When **Enforce Permission Hook** is on:

| Gate tag | Who can operate |
|----------|-----------------|
| Empty | Anyone (public) |
| One name (e.g. `Police`) | Members of that vanilla faction (trim + case-insensitive) |
| Comma list (e.g. `Police, Military`) | Members of **any** listed faction |
| Any tagged gate | **Admin** and **Moderator** always bypass |

Solo sandbox always allows. Logic lives in [`AHG_Permissions.lua`](auto-gate/mods/AutoHotkeyGates/42/media/lua/server/AutoHotkeyGates/AHG_Permissions.lua). Change access with **Change Tag...** (or unregister / re-register).

## Testing checklist

1. Register a double vehicle gate / garage door → halo confirms registration.
2. Hotkey within range → gate opens/closes visually (not only halo text).
3. Sit in a car → radial **Operate Gate** works.
4. Lock the gate → fob still opens; close → lock restored (with defaults).
5. Open with vanilla **E** → auto-closes after ~10s (if delay > 0).
6. Open with **E**, then close with **E** before the timer → auto-close is cancelled; gate stays closed.
7. Stand in the gateway during auto-close → delayed until clear.
8. Out of range → “No automatic gate in range”.
9. Non-staff cannot register / change tags (MP).
10. Tagged gate denies wrong faction; Admin/Mod still operate.

For failures: enable **Debug Logging**, reproduce once, search `%USERPROFILE%\Zomboid\console.txt` (and `DebugLog-server.txt` on dedicated) for `[AHG]` and `ERROR`.

## Architecture notes

- **Canonical `ToggleDoor`**: one call on a preferred double-door handle (index 1); vanilla syncs partner panels. Do not silent-toggle every leaf.
- **Auto-close actor**: always pass a living player into `ToggleDoor` (borrow nearest online player when the timer fires with no triggerer).
- **Reference mods** (always consult before changing toggle/sync): Workshop `3722192974` (GateMotor), `3594285774` (HydeCo), `3777510303` (AutomaticSensorGate), `3629503450` (Remote Gate Opener).

## Mod layout

```
auto-gate/mods/AutoHotkeyGates/
  mod.info
  common/                         B42 common stub (+ empty AnimSets/actiongroups)
  42/
    mod.info                      versionMin=42.20, modversion=1.0.1
    media/
      sandbox-options.txt
      AnimSets/ actiongroups/     empty stubs (silences B42 missing-folder noise)
      lua/
        shared/AutoHotkeyGates/   AHG_Shared.lua, AHG_Keybind.lua, AHG_VanillaSafety.lua
        client/AutoHotkeyGates/   context, hotkey, radial, client GlobalObject mirror
        server/AutoHotkeyGates/   system, commands, permissions, GlobalObjects
        shared/Translate/EN/      ContextMenu, IG_UI, UI, Sandbox
.cursor/rules/gate-mod-references.mdc   agent rule: keep Workshop mods as toggle reference
```

## Known limitations

- Gates desynced by an older AHG build (multi-leaf silent toggles / forced sprite transmits) may need one vanilla hand open/close or a rebuild to look right again.

## Changelog

### 1.0.1

- Safe double-door / garage group detection (fixes B42 `ArrayIndexOutOfBounds` spam on normal doors)
- Toggle path aligned with GateMotor / HydeCo / AutomaticSensorGate: one `ToggleDoor` on a canonical handle; silent fallback only on that same handle; no per-leaf second pass; no forced `transmitUpdatedSpriteToClients` after toggle
- Auto-close arms on **any** open (hotkey or vanilla **E**); manual close before the timer disarms it; timer re-arms if a gate is open with no timer
- Auto-close borrows a nearby living player for `ToggleDoor` (was passing `nil`)
- Staff **Change Tag...** on registered gates; default staff level Moderator+
- Defaults: trigger range **7**, auto-close **10s**
- Hardened timestamps (`getTimestampMs` / `getTimestamp` / `getTimeInMillis`), client/server command dispatch, vehicle radial wrap
- Hotkey feedback text distinguishes garage doors from regular gates
- Hotkey debounce rewritten as a shared, edge-triggered down/up state machine
- `AHG_VanillaSafety.lua`: patches vanilla `buildUtil.getDoubleDoorObjects` / `getGarageDoorObjects` so broken assemblies (>4 linked pieces) cannot abort destroy or spam the destroy cursor; guarded when `require` fails on dedicated servers
- Destroying a registered/tagged gate clears AHG registration/tag data (strict marker match, not “any door on the square”)

### 1.0.0

- Initial B42.20 dedicated-MP mod: register gates, hotkey / radial / context, lock bypass, sandbox page, faction-tag ACL hook

## License

Not specified yet. Add a `LICENSE` before public release if you care about reuse terms.
<!-- update:auto:end -->
