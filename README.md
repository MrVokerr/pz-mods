# Automatic / Hotkey Gates

Project Zomboid **Build 42.20** mod for dedicated multiplayer servers. Staff designate vehicle gates as automatic; players near a registered gate open or close it key-fob style — including from inside a vehicle — via hotkey, vehicle radial menu, or right-click.

Gate toggles run **server-side**; clients send intents only.

**Mod ID:** `AutoHotkeyGates`

## Features

- **Designated gates only** — staff register multi-tile vehicle gates / garage doors (sandbox can allow any door)
- **Three triggers** — rebindable hotkey (default **G**), vehicle radial “Operate Gate”, right-click on the gate
- **Lock bypass** — fob opens locked gates; lock state is remembered and restored on close
- **Optional auto-close** — close after N seconds, with a safety check so it won’t close on a player/vehicle
- **Faction tags** — optional ACL at registration: empty = public, one faction, or comma-separated list; Admin/Moderator bypass
- **Full sandbox page** — range, cooldown, locks, auto-close, staff level, interface toggles, debug logging

## Requirements

- Project Zomboid **Build 42.20+** (`versionMin=42.20`)
- Dedicated server recommended for multiplayer use

## Install

1. Enable mod ID **`AutoHotkeyGates`** in the game or server mod list.
2. On a dedicated server, add `AutoHotkeyGates` to `Mods=` (use your usual Workshop or collection flow for distribution).
3. Tune options under the sandbox page **Automatic Hotkey Gates**.

## Quick start

1. Enable the mod and load a world (or join the server).
2. As staff (Moderator+ by default), right-click a large vehicle gate → **Register Automatic Gate**. Leave the tag empty for public, type one faction (e.g. `Police`), or several comma-separated (`Police, Military`). Staff can later use **Change Tag...** on any registered gate.
3. Bind the key under **Options → Key Bindings → Automatic Hotkey Gates** (default G).
4. Stand or sit in a vehicle within range → press the hotkey, use the vehicle radial, or right-click the gate.

## Sandbox options

| Option | Default | Purpose |
|--------|---------|---------|
| Trigger Range | 7 tiles | Fob distance |
| Trigger Cooldown | 1 s | Anti-spam |
| Vehicle Gates Only | on | Multi-tile gates only |
| Operate From Vehicle Only | off | Strict key-fob RP |
| Bypass Locks / Re-lock On Close | on / on | Lock behavior |
| Auto-Close Delay | 10 s | Seconds until auto-close (0 = off) |
| Auto-Close Safety Check | on | Don’t close on bodies/vehicles |
| Min Staff Level To Register | Moderator+ | Who can register / change tags / unregister |
| Max Registered Gates | 0 (unlimited) | Cap |
| Enforce Permission Hook | on | Master switch for faction-tag checks |
| Enable Hotkey / Radial / Context | on | Per-trigger toggles |
| Show Feedback Messages | on | Halo text |
| Debug Logging | off | `[AHG]` console lines |

Sandbox options are read live via `SandboxVars` (F1 admin sandbox edits apply without a mod reload). File-only dedicated edits still need a vanilla options reload or restart.

## Faction permissions

When **Enforce Permission Hook** is on:

| Gate tag | Who can operate |
|----------|-----------------|
| Empty | Anyone (public) |
| One name (e.g. `Police`) | Members of that vanilla faction (trim + case-insensitive) |
| Comma list (e.g. `Police, Military`) | Members of **any** listed faction |
| Any tagged gate | **Admin** and **Moderator** always bypass |

Solo sandbox always allows. Logic lives in `42/media/lua/server/AutoHotkeyGates/AHG_Permissions.lua`. Change access with **Change Tag...** (or unregister / re-register).

## Mod layout

```
AutoHotkeyGates/
  mod.info
  42/
    mod.info
    media/
      sandbox-options.txt
      lua/
        shared/AutoHotkeyGates/   AHG_Shared.lua, AHG_Keybind.lua
        client/AutoHotkeyGates/   context menu, hotkey, radial, client system
        server/AutoHotkeyGates/   system, commands, permissions, global objects
        shared/Translate/EN/      ContextMenu, IG_UI, UI, Sandbox
```

## License

Not specified yet. Add a `LICENSE` before public release if you care about reuse terms.
