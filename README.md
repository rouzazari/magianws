# MagianWS

**Author:** renzler
**Version:** 0.0.1
**Date:** 2/26/2026

## Description

MagianWS automatically uses a weaponskill at a configurable TP threshold when the player is engaged. Designed for Magian Trials that require a certain number of weaponskill executions.

## Commands

| Command | Description |
|---|---|
| `//magianws ws <name>` | Set the weaponskill to use (default: Piercing Arrow) |
| `//magianws tp <value>` | Set the minimum TP threshold (default: 1000) |
| `//magianws food <name>` | Set a food item to auto-use when engaging or when food wears off |
| `//magianws food off` | Disable auto-food |
| `//magianws ammo <name>` | Set an ammo item to auto-equip from inventory on load and before each WS |
| `//magianws ammo off` | Disable auto-ammo |
| `//magianws status` | Display current settings |

## Usage

```
//lua load MagianWS
//lua reload MagianWS
//lua unload MagianWS
```

## Recommended camps

| Weapon | Trial | Mob | Camp |
|---|---|---|---|
| Archery | [2642](https://www.bg-wiki.com/ffxi/Trial_2642) | [Bight Uragnites](https://www.bg-wiki.com/ffxi/Bight_Uragnite) | [Ceizak Battlegrounds](https://www.bg-wiki.com/ffxi/Ceizak_Battlegrounds) |
| Archery | [3075](https://www.bg-wiki.com/ffxi/Trial_3075) | [Apex Mandragora](https://www.bg-wiki.com/ffxi/Apex_Mandragora) | [Sih Gates](https://www.bg-wiki.com/ffxi/Sih_Gates) |
| Marksmanship | [1786](https://www.bg-wiki.com/ffxi/Trial_1786) | [Apex Eruca](https://www.bg-wiki.com/ffxi/Apex_Eruca) | [Moh Gates](https://www.bg-wiki.com/ffxi/Moh_Gates) |


## Planned Features

- Target minimum HP% check before executing the weaponskill (for "killing blow" trials)
- SAM job ability handling (Meditate, Hasso)
- Trust management
- Stop/warp at trial completion
