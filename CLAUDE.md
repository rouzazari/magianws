# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Context
Before starting any task, query the relevant QMD MCP collections
("windower-docs", "windower-lua", "windower-lua-wiki") using keywords
related to the task for relevant background.

Query again mid-task when:
- Writing any Windower addon hook or event handler
- Using any `windower.*` or `res.*` API call
- Referencing packet structures or game memory fields
- Importing any Windower library (res, packets, texts, etc.)

Treat QMD results as ground truth over training knowledge for anything
Windower or FFXI addon specific.

---

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
- Trial progress overlay: in-game text overlay (draggable) showing WS name, remaining trial count, and active target name; auto-updates by parsing the chat log for patterns like "N more" or "N remaining"; manually settable via `//magianws trial set <n>`; uses the `texts` library
- Auto-target: scans `windower.ffxi.get_mob_array()` every 2 seconds (via `prerender` timer) for the closest unclaimed, alive mob matching `target_name`; when found and player is not engaged (`status != 1`), injects an **incoming** packet `0x058` with `Player`, `Target`, `Player Index` fields to lock the client target, then sends `input /attack`; configure with `//magianws target <name>` / `//magianws target off`; mob filtering uses `spawn_type` bitmask to exclude PCs and Trusts (flags 0x01 and 0x04), checks `hpp > 0`, `status != 2`, and `claim_id == 0`
- Windower targeting pattern (from `SetTarget` addon): targeting is done by injecting an **incoming** (not outgoing) packet `0x058` — this spoofs a server "target changed" message to the client. Fields: `['Player'] = player.id`, `['Target'] = mob.id`, `['Player Index'] = player.index`. Call: `packets.inject(packets.new('incoming', 0x058, {...}))`. `/target <name>` is not a valid FFXI command. `windower.ffxi.interact()` does not exist.

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
