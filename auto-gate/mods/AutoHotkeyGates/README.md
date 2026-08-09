<!-- update:auto:start -->
# Automatic / Hotkey Gates

Project Zomboid **Build 42.20+** mod for dedicated multiplayer servers (works in singleplayer / Host too). Staff designate vehicle gates as automatic; players near a registered gate open or close it key-fob style — including from inside a vehicle — via hotkey, vehicle radial menu, or right-click.

Gate toggles run **server-side**; clients send intents only.

| | |
|---|---|
| **Mod ID** | `AutoHotkeyGates` |
| **Version** | `1.0.1` |
| **Target** | Build **42.20+** (`versionMin=42.20`) |

## Features

- **Designated gates only** — staff register multi-tile vehicle gates / garage doors (sandbox can allow any door)
- **Three triggers** — rebindable hotkey (default **G**), vehicle radial “Operate Gate”, right-click on the gate
- **Lock bypass** — fob opens locked gates; lock state is remembered and restored on close
- **Auto-close** — closes after N seconds after **any** open (hotkey, radial, context, or vanilla **E**); manual close before the timer cancels auto-close
- **Faction tags** — optional ACL at registration / **Change Tag...**: empty = public, one faction, or comma-separated list; Admin/Moderator bypass; sandbox **Permission Provider** chooses Vanilla MP factions or **PLZ_Membership**
- **Staff tools** — Moderator+ (default) can register, change tags, and unregister
- **Full sandbox page** — range, cooldown, locks, auto-close, staff level, permission provider, interface toggles, debug logging

## Directory overview

```
AutoHotkeyGates/
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
```

## Prerequisites

- Project Zomboid **Build 42.20+**
- Mod installed under the game’s mods path (Host / SP or dedicated)
- For dedicated: `Mods=AutoHotkeyGates` in the server ini
- Staff access (**Moderator+** by default) to register gates in MP

## Configuration

### Dedicated server

1. Copy or junction `AutoHotkeyGates` into the server mods path (or ship via Workshop later).
2. Add `AutoHotkeyGates` to `Mods=` in the server ini.
3. Set sandbox options on the server (or via admin sandbox editor).

### Sandbox options

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
| Permission Provider | Vanilla Faction Tag | Vanilla MP factions, or **PLZ_Membership** (PLZ_Factions + `USE_VEHICLE_GARAGE`) |
| Enable Hotkey / Radial / Context | on | Per-trigger toggles |
| Show Feedback Messages | on | Halo text |
| Debug Logging | off | `[AHG]` lines in `console.txt` |

Sandbox options are read live via `SandboxVars` where PZ allows (F1 admin sandbox edits). File-only dedicated edits may need a vanilla options reload or restart. **Existing saves keep old sandbox values** until you change them in that world.

## In-game usage

1. As staff (**Moderator+** by default), right-click a large vehicle gate → **Automatic Gate → Register Automatic Gate...**
2. Leave the tag empty for public, type one faction (e.g. `Police`), or several comma-separated (`Police, Military`).
3. Bind the key under **Options → Key Bindings → Automatic Hotkey Gates** (default **G**).
4. Within range (default **7** tiles), on foot or in a vehicle:
   - Press the hotkey
   - Vehicle radial → **Operate Gate**
   - Right-click the gate → **Open/Close Gate**
5. Staff can later use **Change Tag...** or **Unregister Automatic Gate** on any registered gate.

## Faction permissions

When **Enforce Permission Hook** is on, **Permission Provider** chooses the ACL:

### Vanilla Faction Tag (default)

| Gate tag | Who can operate |
|----------|-----------------|
| Empty | Anyone (public) |
| One name (e.g. `Police`) | Members of that vanilla MP faction (trim + case-insensitive) |
| Comma list (e.g. `Police, Military`) | Members of **any** listed faction |
| Any tagged gate | **Admin** and **Moderator** always bypass |

### PLZ_Membership

Requires **PLZ_Factions** on the server. Same tag matching against the PLZ faction **name**, plus the player's role must have **`USE_VEHICLE_GARAGE`**. If this provider is selected but PLZ is missing, tagged triggers are denied (fail closed).

Solo sandbox always allows. Logic lives in [`42/media/lua/server/AutoHotkeyGates/AHG_Permissions.lua`](42/media/lua/server/AutoHotkeyGates/AHG_Permissions.lua). Change access with **Change Tag...** (or unregister / re-register).

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
11. With **Permission Provider = PLZ_Membership**, matching PLZ faction + `USE_VEHICLE_GARAGE` can operate; missing PLZ denies tagged triggers.

For failures: enable **Debug Logging**, reproduce once, search `%USERPROFILE%\Zomboid\console.txt` (and `DebugLog-server.txt` on dedicated) for `[AHG]` and `ERROR`.

## Changelog

### 1.0.1

- Sandbox **Permission Provider**: Vanilla Faction Tag (default) or **PLZ_Membership** (PLZ_Factions name match + `USE_VEHICLE_GARAGE`; fail closed if PLZ missing)
- Safe double-door / garage group detection (fixes B42 `ArrayIndexOutOfBounds` spam on normal doors)
- Toggle path: one `ToggleDoor` on a canonical handle; silent fallback only on that same handle; no per-leaf second pass; no forced sprite transmit after toggle
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
