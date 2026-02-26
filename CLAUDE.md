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

**Planned features (not yet implemented):**
- Configurable weaponskill name (currently hardcoded to `"Empyreal Arrow"`)
- Configurable minimum TP threshold (currently hardcoded to 1000)
- Target minimum HP% check before firing the WS (for "killing blow" trials)
- Automatic food, SAM job ability handling, ammunition, Trust management, stop/warp at trial completion

## Windower Addon Conventions

- The addon folder name (`MagianWS`) must match the main Lua filename (`magianws.lua`, case-insensitive).
- Commands sent via `windower.send_command` use FFXI's `/` command syntax (e.g., `/ws "Name" <t>`).
- `<t>` is the FFXI macro target placeholder for the current target.
