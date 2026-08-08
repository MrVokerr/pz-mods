# Automatic / Hotkey Gates

Project Zomboid **Build 42.20+** mod for dedicated multiplayer servers (works in singleplayer / Host too). Staff designate vehicle gates as automatic; players near a registered gate open or close it key-fob style — including from inside a vehicle — via hotkey, vehicle radial menu, or right-click.

Gate toggles run **server-side**; clients send intents only.

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
- **Auto-close** — closes after N seconds after **any** open (hotkey, radial, context, or vanilla **E**), with a safety check so it won’t close on a player/vehicle
- **Faction tags** — optional ACL at registration / **Change Tag...**: empty = public, one faction, or comma-separated list; Admin/Moderator bypass
- **Staff tools** — Moderator+ (default) can register, change tags, and unregister
- **Full sandbox page** — range, cooldown, locks, auto-close, staff level, interface toggles, debug logging

## Install (local testing)

Source lives in this repo. Junction it into your user mods folder so the game sees it:

```
D:\Git\pz-mods\auto-gate\mods\AutoHotkeyGates
  →  %USERPROFILE%\Zomboid\mods\AutoHotkeyGates
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
6. Stand in the gateway during auto-close → delayed until clear.
7. Out of range → “No automatic gate in range”.
8. Non-staff cannot register / change tags (MP).
9. Tagged gate denies wrong faction; Admin/Mod still operate.

For failures: enable **Debug Logging**, reproduce once, search `C:\Users\Voker\Zomboid\console.txt` for `[AHG]` and `ERROR`.

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
        shared/AutoHotkeyGates/   AHG_Shared.lua, AHG_Keybind.lua
        client/AutoHotkeyGates/   context, hotkey, radial, client GlobalObject mirror
        server/AutoHotkeyGates/   system, commands, permissions, GlobalObjects
        shared/Translate/EN/      ContextMenu, IG_UI, UI, Sandbox
```

## Changelog

### 1.0.1

- Safe double-door / garage group detection (fixes B42 `ArrayIndexOutOfBounds` spam on normal doors)
- Remote toggle sync: `ToggleDoor` first, silent fallback + `sync` / `transmitUpdatedSpriteToClients`
- Auto-close arms on **any** open (hotkey or vanilla **E**)
- Staff **Change Tag...** on registered gates; default staff level Moderator+
- Defaults: trigger range **7**, auto-close **10s**
- Hardened timestamps, client/server command dispatch, vehicle radial wrap

### 1.0.0

- Initial B42.20 dedicated-MP mod: register gates, hotkey / radial / context, lock bypass, sandbox page, faction-tag ACL hook

## License

Not specified yet. Add a `LICENSE` before public release if you care about reuse terms.
