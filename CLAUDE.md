# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MagianWS is a [Windower](https://www.windower.net/) Lua addon for Final Fantasy XI. It automatically executes a weaponskill at 1000 TP to assist with Magian Trials that require a set number of weaponskill uses.

## Development Workflow

There is no build step. Windower interprets Lua directly at runtime.

**Load the addon in-game:**
```
//lua load MagianWS
```

**Reload after edits:**
```
//lua reload MagianWS
```

**Unload:**
```
//lua unload MagianWS
```

Changes to `magianws.lua` take effect after reloading the addon in-game. There is no linter or test runner — validation is done by observing behavior in FFXI via Windower.

## Architecture

The entire addon lives in `magianws.lua`. Windower addons are event-driven; logic is registered via `windower.register_event(event_name, callback)`.

**Key Windower APIs used:**
- `windower.ffxi.get_player()` — returns the current player's data table (name, job, TP, vitals, etc.). Currently called once at module load; re-call inside event handlers for live data.
- `windower.send_command(cmd)` — sends a command to the game. Use the `input` prefix to bypass macros and send directly to the client (e.g., `'input /ws "Name" <t>'`).
- `windower.register_event(event, fn)` — subscribes to a Windower event

**Current event:**
- `'tp change'` — fires with `(new_tp, old_tp)` whenever the player's TP changes

**Implemented features:**
- Configurable weaponskill name and TP threshold
- Persistent settings via the `config` library (`data/settings.xml`)
- Auto-food: eats configured food on engage and when it wears off
- Auto-ammo: equips configured ammo from inventory before each WS
- Self-buff maintenance: tracks a list of spells/job abilities, recasts them on engage or when they wear off; staggered with 6-second delays to avoid "Unable to cast" errors; buff names with spaces use underscored XML keys (e.g. `Phalanx_II`) with a `name` field for the actual cast command

**Planned features (not yet implemented):**
- Cast Composure before other buffs so it extends their duration
- Retry buffs that fail to apply (e.g. interrupted cast, recast timer not ready)
- Target minimum HP% check before firing the WS (for "killing blow" trials)
- SAM job ability handling (Meditate, Hasso)
- Trust management
- Stop/warp at trial completion

## Windower Addon Conventions

- The addon folder name (`MagianWS`) must match the main Lua filename (`magianws.lua`, case-insensitive).
- Commands sent via `windower.send_command` use FFXI's `/` command syntax (e.g., `/ws "Name" <t>`).
- `<t>` is the FFXI macro target placeholder for the current target.
