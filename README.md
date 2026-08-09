<!-- update:auto:start -->
# pz-mods

Monorepo for Project Zomboid mods. Each mod lives under its own folder with its own README.

## Quick Start

1. Clone or open this repo.
2. Open the mod you want under its folder (see table below).
3. Follow that mod’s README for install (copy/junction into the game or dedicated `mods` path) and sandbox setup.

## Mods

| Mod | Path | Description |
|-----|------|-------------|
| Automatic / Hotkey Gates | [`auto-gate/mods/AutoHotkeyGates/`](auto-gate/mods/AutoHotkeyGates/) | Staff-designated vehicle gates with hotkey / radial / context fob (B42.20+). Faction ACL via vanilla tags or optional **PLZ_Membership** (`USE_VEHICLE_GARAGE`). |

## Directory overview

```
pz-mods/
  README.md
  auto-gate/mods/AutoHotkeyGates/   AHG mod source + README
  .cursor/rules/                    Project agent rules (e.g. gate-mod references)
```

`PLZ_Factions/` is a local reference checkout (gitignored) used when wiring AHG’s optional PLZ permission provider.

## Prerequisites

- Project Zomboid **Build 42.20+** for Automatic / Hotkey Gates
- Dedicated or Host/SP install path for mods

## Configuration

Per-mod sandbox options and server `Mods=` entries — see each mod README. No repo-level `.env`.

## Architecture

Mods are independent Workshop-style trees (`mod.info` + `42/media/lua/...`). Shared lessons (gate toggle/sync patterns) live in `.cursor/rules/`. AHG’s permission hook soft-requires PLZ_Factions when the sandbox **Permission Provider** is set to PLZ_Membership.

## License

Not specified yet. Add a `LICENSE` before public release if you care about reuse terms.
<!-- update:auto:end -->
