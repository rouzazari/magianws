# MagianWS

**Author:** renzler
**Version:** 0.0.1
**Date:** 2/26/2026

## Description

MagianWS automates mob grinding. It automatically uses a weaponskill at a configurable TP threshold while engaged, and optionally handles mob targeting, following, food, ammo, and self-buffs so you can AFK grind a camp.

Originally built for Magian Trials, it also works for farming experience points, capacity points, and exemplar points against any named mob type.

## Loading

```
//lua load MagianWS
//lua reload MagianWS
//lua unload MagianWS
```

## Commands

### Weaponskill

| Command | Description |
|---|---|
| `//magianws ws <name>` | Set the weaponskill name (default: Piercing Arrow) |
| `//magianws tp <value>` | Set the TP threshold to fire the WS (default: 1000) |

### Auto-Target

Automatically finds, targets, follows, and attacks a named mob.

- Scans for unclaimed, alive mobs matching `target_name` within **40 yalms** every 2 seconds.
- **Follow mode** (default): locks the target then issues `/follow` to close distance and keep the character facing the mob; attacks with `/attack` once within 20 yalms.
- **Pull mode**: fires one ranged attack (`/ra`) to aggro a single mob, then stands still until it walks into 20 yalm melee range before attacking. Avoids linking nearby mobs when grinding in groups. Requires a ranged weapon equipped.
- While engaged, re-locks on the target every 2 seconds and issues `/follow` so the character always faces it — the lock releases after 1 second.
- Stops automatically on zone change.

| Command | Description |
|---|---|
| `//magianws target <name>` | Set the mob name to auto-target |
| `//magianws target off` | Clear the auto-target mob |
| `//magianws pull on\|off` | Use ranged attack to pull mobs instead of following them (default: off) |
| `//magianws start` | Begin the auto-target/follow/attack loop |
| `//magianws stop` | Pause the auto-target loop (also stops on zone change) |

### Consumables

| Command | Description |
|---|---|
| `//magianws food <name>` | Auto-use this food item on engage and when it wears off |
| `//magianws food off` | Disable auto-food |
| `//magianws ammo <name>` | Auto-equip this ammo from inventory before each WS |
| `//magianws ammo off` | Disable auto-ammo |

### Self-Buffs

| Command | Description |
|---|---|
| `//magianws buff add <name>` | Add a spell or job ability to the self-buff list |
| `//magianws buff remove <name>` | Remove a buff from the list |
| `//magianws buff list` | List all configured self-buffs |

Buffs are cast on engage and recast when they wear off, staggered by 6 seconds each to avoid ability conflicts.

### Combat Assists

| Command | Description |
|---|---|
| `//magianws provoke on\|off` | Auto-provoke the current target every 30 seconds |
| `//magianws follow on\|off` | Re-follow the current target on "out of range" or "cannot see" messages |

### Trial Progress

| Command | Description |
|---|---|
| `//magianws trial set <n>` | Manually set the remaining trial count |
| `//magianws trial reset` | Reset the remaining count to unknown |
| `//magianws trial` | Print the current remaining count |

The remaining count auto-updates by parsing trial completion messages from the chat log.

### Overlay

| Command | Description |
|---|---|
| `//magianws show` | Show the HUD overlay (draggable) |
| `//magianws hide` | Hide the HUD overlay |

The overlay shows the active WS, remaining trial count, and auto-target status (▶ running / ■ stopped).

### Misc

| Command | Description |
|---|---|
| `//magianws status` | Print all current settings to chat |
| `//magianws debug on\|off` | Toggle verbose targeting debug output |

## Typical Setup

```
//magianws ws Trueflight
//magianws target Gneiss Leech
//magianws food Sublime Sushi
//magianws buff add Barfire
//magianws trial set 50
//magianws start
```

For a capacity point camp where mobs are grouped (use pull mode to avoid links):
```
//magianws ws Trueflight
//magianws target Apex Bat
//magianws pull on
//magianws start
```

## Recommended Camps

| Weapon | Trial | Mob | Camp | Weaponskill |
|---|---|---|---|---|
| Archery | [2232](https://www.bg-wiki.com/ffxi/Trial_2232) | [Overking Apkallu](https://www.bg-wiki.com/ffxi/Overking_Apkallu) | [Abyssea - Misareaux](https://www.bg-wiki.com/ffxi/Abyssea_-_Misareaux) | Empyreal Arrow (required) |
| Archery | [2642](https://www.bg-wiki.com/ffxi/Trial_2642) | [Bight Uragnites](https://www.bg-wiki.com/ffxi/Bight_Uragnite) | [Ceizak Battlegrounds](https://www.bg-wiki.com/ffxi/Ceizak_Battlegrounds) | Piercing Arrow |
| Archery | [3075](https://www.bg-wiki.com/ffxi/Trial_3075) | [Apex Mandragora](https://www.bg-wiki.com/ffxi/Apex_Mandragora) | [Sih Gates](https://www.bg-wiki.com/ffxi/Sih_Gates) | Piercing Arrow |
| Archery | [3538](https://www.bg-wiki.com/ffxi/Trial_3538) | [Apex Eruca](https://www.bg-wiki.com/ffxi/Apex_Eruca) | [Moh Gates](https://www.bg-wiki.com/ffxi/Moh_Gates) | Apex Arrow |
| Marksmanship | [1786](https://www.bg-wiki.com/ffxi/Trial_1786) | [Apex Eruca](https://www.bg-wiki.com/ffxi/Apex_Eruca) | [Moh Gates](https://www.bg-wiki.com/ffxi/Moh_Gates) | Detonator (required) |

## Planned Features

- Cast Composure before other buffs so it extends their duration
- Retry buffs that fail to apply (e.g. interrupted cast, recast timer not ready)
- Target minimum HP% check before executing the weaponskill (for "killing blow" trials)
- SAM job ability handling (Meditate, Hasso)
- Trust management
- Stop/warp at trial completion
