-- Copyright 2026 renzler
-- Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
-- 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

_addon.name = 'MagianWS'
_addon.author = 'renzler'
_addon.version = '0.0.1'
_addon.commands = {'magianws'}

config = require('config')
texts = require('texts')
local res = require('resources')
local packets = require('packets')

local COLOR_PAT = '[' .. string.char(0x1e, 0x1f) .. '].'
local COLOR_RESET = string.char(0x7f)
local function strip_colors(s)
    return (s:gsub(COLOR_PAT, ''):gsub(COLOR_RESET, ''))
end

local function has_flag(n, f)
    return math.floor(n / f) % 2 == 1
end

local function is_player_or_trust(spawn_type)
    return has_flag(spawn_type, 0x01) or has_flag(spawn_type, 0x04)
end

local defaults = {}
defaults.ws_name = 'Piercing Arrow'
defaults.tp_threshold = 1000
defaults.food_name = ''
defaults.ammo_name = ''
defaults.buffs = {}
defaults.provoke = false
defaults.follow = false
defaults.target_name = ''
defaults.trial_remaining = -1
defaults.display = {}
defaults.display.pos = {}
defaults.display.pos.x = 100
defaults.display.pos.y = 50
defaults.display.bg = {}
defaults.display.bg.red = 0
defaults.display.bg.green = 0
defaults.display.bg.blue = 0
defaults.display.bg.alpha = 160
defaults.display.bg.visible = true
defaults.display.text = {}
defaults.display.text.font = 'Consolas'
defaults.display.text.size = 11
defaults.display.text.red = 255
defaults.display.text.green = 255
defaults.display.text.blue = 255
defaults.display.text.alpha = 255
defaults.display.flags = {}
defaults.display.flags.draggable = true

local settings = config.load(defaults)

local display = texts.new('', settings.display, settings)
local display_visible = true

local last_provoke_time = 0
local PROVOKE_RECAST = 30

local function parse_trial_remaining(lower_text)
    return tonumber(lower_text:match('trial %d+: (%d+) objectives? remain'))
        or tonumber(lower_text:match('(%d+) objectives? remain'))
        or tonumber(lower_text:match('(%d+) more'))
        or tonumber(lower_text:match('(%d+) remaining'))
        or tonumber(lower_text:match('remaining[^%d]*(%d+)'))
end

local function update_display()
    if not display_visible then
        display:hide()
        return
    end
    local rem_str
    if settings.trial_remaining < 0 then
        rem_str = '\\cs(160,160,160)?\\cr'
    else
        rem_str = ('\\cs(100,255,100)%d\\cr'):format(settings.trial_remaining)
    end
    local target_line = ''
    if settings.target_name ~= '' then
        local active_str = active and '\\cs(100,255,100)▶\\cr ' or '\\cs(160,160,160)■\\cr '
        target_line = '\n  Target: ' .. active_str .. '\\cs(255,180,80)' .. settings.target_name .. '\\cr'
    end
    display:text(('\\cs(255,200,80)[ MagianWS ]\\cr\n  WS: \\cs(200,220,255)%s\\cr\n  Remaining: %s%s'):format(settings.ws_name, rem_str, target_line))
    display:show()
end

local function is_food_active()
    local player = windower.ffxi.get_player()
    for _, buff_id in ipairs(player.buffs) do
        if buff_id == 251 then
            return true
        end
    end
    return false
end

local function find_in_inventory(name)
    local items = windower.ffxi.get_items(0)
    for i = 1, items.max do
        local item = items[i]
        if item and item.id ~= 0 then
            local item_data = res.items[item.id]
            if item_data and item_data.en:lower() == name:lower() then
                return true
            end
        end
    end
    return false
end

local function find_buff_info(name)
    local lower = name:lower()
    for _, spell in pairs(res.spells) do
        if spell.en and spell.en:lower() == lower and spell.status and spell.status ~= 0 then
            return {name = spell.en, type = 'spell', buff_id = spell.status}
        end
    end
    if res.job_abilities then
        for _, ja in pairs(res.job_abilities) do
            if ja.en and ja.en:lower() == lower and ja.status and ja.status ~= 0 then
                return {name = ja.en, type = 'ability', buff_id = ja.status}
            end
        end
    end
    return nil
end

local function is_buff_active(buff_id)
    local target_id = tonumber(buff_id)
    local player = windower.ffxi.get_player()
    for _, id in ipairs(player.buffs) do
        if id == target_id then return true end
    end
    return false
end

local function cast_buff(name, buff_type, delay)
    local cmd
    if buff_type == 'spell' then
        cmd = 'input /ma "' .. name .. '" <me>'
    else
        cmd = 'input /ja "' .. name .. '" <me>'
    end
    if delay and delay > 0 then
        windower.send_command('wait ' .. delay .. '; ' .. cmd)
    else
        windower.send_command(cmd)
    end
end

local function maintain_buffs()
    local player = windower.ffxi.get_player()
    if player.status ~= 1 then return end
    local delay = 0
    for _, entry in pairs(settings.buffs) do
        if not is_buff_active(entry.buff_id) then
            cast_buff(entry.name, entry.type, delay)
            delay = delay + 6
        end
    end
end

local function try_eat_food()
    if settings.food_name ~= '' and not is_food_active() and find_in_inventory(settings.food_name) then
        windower.send_command('input /item "' .. settings.food_name .. '" <me>')
    end
end

local function try_equip_ammo()
    if settings.ammo_name ~= '' then
        if find_in_inventory(settings.ammo_name) then
            windower.send_command('input /equip Ammo "' .. settings.ammo_name .. '"')
        else
            windower.add_to_chat(8, 'MagianWS: Out of "' .. settings.ammo_name .. '".')
        end
    end
end

local function try_provoke()
    if not settings.provoke then return end
    local player = windower.ffxi.get_player()
    if player.status ~= 1 then return end
    if os.time() - last_provoke_time < PROVOKE_RECAST then return end
    last_provoke_time = os.time()
    windower.send_command('input /ja "Provoke" <t>')
end

local function find_target_mob(name)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return nil end
    local mobs = windower.ffxi.get_mob_array()
    if not mobs then return nil end

    local lower_name = name:lower()
    local best, best_dist = nil, math.huge

    for _, mob in pairs(mobs) do
        if mob and mob.id and mob.id ~= 0
                and mob.name and mob.name:lower() == lower_name
                and not is_player_or_trust(mob.spawn_type or 0)
                and (mob.status or 0) ~= 2
                and (mob.hpp or 0) > 0
                and (mob.claim_id or 0) == 0
        then
            local dx = mob.x - me.x
            local dy = mob.y - me.y
            local dz = mob.z - me.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist < best_dist then
                best_dist = dist
                best = mob
            end
        end
    end
    return best
end

local last_scan_tick  = 0
local SCAN_INTERVAL   = 2.0
local ATTACK_RANGE_SQ = 400  -- 20 yalms; mob.distance is squared
local debug_target    = false
local active          = false  -- start/stop toggle (not persisted)

local function dbg(msg)
    if debug_target then
        windower.add_to_chat(8, 'MagianWS[dbg]: ' .. msg)
    end
end

local function try_engage_target()
    if not active then return end
    if settings.target_name == '' then return end
    local player = windower.ffxi.get_player()
    dbg('scan | status=' .. tostring(player.status) .. ' target="' .. settings.target_name .. '"')
    if player.status == 1 then return end

    local lower_name = settings.target_name:lower()

    -- Already have the right mob targeted — approach or attack
    local current_target = windower.ffxi.get_mob_by_target('t')
    if current_target and current_target.name
            and current_target.name:lower() == lower_name
            and (current_target.hpp or 0) > 0
            and (current_target.status or 0) ~= 2 then
        local dist_sq = current_target.distance or math.huge
        if dist_sq <= ATTACK_RANGE_SQ then
            dbg('in range (dist_sq=' .. tostring(dist_sq) .. ') — attacking')
            windower.send_command('input /attack')
        else
            dbg('following (dist_sq=' .. tostring(dist_sq) .. ')')
            windower.send_command('input /follow <t>')
        end
        return
    end

    -- No valid target yet — scan and lock on to the closest matching mob
    local mobs = windower.ffxi.get_mob_array()
    if not mobs then
        dbg('get_mob_array() returned nil')
        return
    end

    local me = windower.ffxi.get_mob_by_target('me')
    local total, name_matches, nearby = 0, {}, {}

    for _, mob in pairs(mobs) do
        if mob and mob.id and mob.id ~= 0 and mob.name and mob.name ~= '' then
            total = total + 1
            if mob.name:lower() == lower_name then
                local reason
                if is_player_or_trust(mob.spawn_type or 0) then
                    reason = 'SKIP:player/trust'
                elseif (mob.status or 0) == 2 then
                    reason = 'SKIP:dead'
                elseif (mob.hpp or 0) == 0 then
                    reason = 'SKIP:hpp=0'
                elseif (mob.claim_id or 0) ~= 0 then
                    reason = 'SKIP:claimed'
                else
                    reason = 'OK'
                end
                name_matches[#name_matches+1] = 'id=' .. tostring(mob.id)
                    .. ' hpp=' .. tostring(mob.hpp)
                    .. ' status=' .. tostring(mob.status)
                    .. ' claim=' .. tostring(mob.claim_id)
                    .. ' spawn=' .. tostring(mob.spawn_type)
                    .. ' [' .. reason .. ']'
            elseif me then
                local dx = (mob.x or 0) - me.x
                local dy = (mob.y or 0) - me.y
                local dz = (mob.z or 0) - me.z
                if math.sqrt(dx*dx + dy*dy + dz*dz) < 30 then
                    nearby[#nearby+1] = '"' .. mob.name .. '"'
                end
            end
        end
    end

    dbg('total entities=' .. total .. ' | name matches=' .. #name_matches)
    for _, info in ipairs(name_matches) do
        dbg('  matched: ' .. info)
    end
    if #name_matches == 0 then
        dbg('no name match — nearby (<30y): ' .. (#nearby > 0 and table.concat(nearby, ', ') or '(none)'))
    end

    local mob = find_target_mob(settings.target_name)
    if mob then
        dbg('targeting id=' .. tostring(mob.id) .. ' index=' .. tostring(mob.index))
        local ok, err = pcall(function()
            packets.inject(packets.new('incoming', 0x058, {
                ['Player']       = player.id,
                ['Target']       = mob.id,
                ['Player Index'] = player.index,
            }))
        end)
        if ok then
            dbg('targeted — following')
            windower.send_command('input /follow <t>')
        else
            dbg('packet error: ' .. tostring(err))
        end
    else
        dbg('find_target_mob returned nil')
    end
end

windower.register_event('prerender', function()
    local now = os.clock()
    if now >= last_scan_tick + SCAN_INTERVAL then
        last_scan_tick = now
        try_engage_target()
    end
end)

local function print_status()
    local buff_count = 0
    for _ in pairs(settings.buffs) do buff_count = buff_count + 1 end
    local rem_str = settings.trial_remaining >= 0 and tostring(settings.trial_remaining) or '?'
    windower.add_to_chat(8, 'MagianWS: Weaponskill: "' .. settings.ws_name .. '" | TP threshold: ' .. settings.tp_threshold .. ' | Remaining: ' .. rem_str .. ' | Food: ' .. (settings.food_name ~= '' and settings.food_name or 'off') .. ' | Ammo: ' .. (settings.ammo_name ~= '' and settings.ammo_name or 'off') .. ' | Buffs: ' .. buff_count .. ' | Provoke: ' .. (settings.provoke and 'on' or 'off') .. ' | Follow: ' .. (settings.follow and 'on' or 'off') .. ' | Target: ' .. (settings.target_name ~= '' and '"' .. settings.target_name .. '"' or 'off') .. ' | Active: ' .. (active and 'yes' or 'no'))
end

local function try_eat_food_if_engaged()
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        try_eat_food()
    end
end

local function execute_ws()
    try_equip_ammo()
    windower.send_command('input /ws "' .. settings.ws_name .. '" <t>')
end

windower.register_event('addon command', function(cmd, ...)
    if cmd == 'ws' then
        settings.ws_name = table.concat({...}, ' ')
        settings:save()
        print_status()
    elseif cmd == 'tp' then
        local val = tonumber((...))
        if val then
            settings.tp_threshold = val
            settings:save()
            print_status()
        else
            windower.add_to_chat(8, 'MagianWS: Invalid TP value.')
        end
    elseif cmd == 'food' then
        local arg = table.concat({...}, ' ')
        if arg == '' or arg:lower() == 'off' then
            settings.food_name = ''
        else
            settings.food_name = arg
            try_eat_food_if_engaged()
        end
        settings:save()
        print_status()
    elseif cmd == 'ammo' then
        local arg = table.concat({...}, ' ')
        if arg == '' or arg:lower() == 'off' then
            settings.ammo_name = ''
        else
            settings.ammo_name = arg
            try_equip_ammo()
        end
        settings:save()
        print_status()
    elseif cmd == 'buff' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        if subcmd == 'add' then
            local buff_name = table.concat(rest, ' ')
            local info = find_buff_info(buff_name)
            if info then
                local key = info.name:gsub(' ', '_')
                settings.buffs[key] = {name = info.name, type = info.type, buff_id = info.buff_id}
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Added buff "' .. info.name .. '" (' .. info.type .. ', buff ID ' .. info.buff_id .. ').')
            else
                windower.add_to_chat(8, 'MagianWS: Unknown buff "' .. buff_name .. '".')
            end
        elseif subcmd == 'remove' then
            local buff_name = table.concat(rest, ' ')
            local search_key = buff_name:gsub(' ', '_')
            for k in pairs(settings.buffs) do
                if k:lower() == search_key:lower() then
                    local display_name = settings.buffs[k].name or k
                    settings.buffs[k] = nil
                    settings:save()
                    windower.add_to_chat(8, 'MagianWS: Removed buff "' .. display_name .. '".')
                    return
                end
            end
            windower.add_to_chat(8, 'MagianWS: Buff "' .. buff_name .. '" not found.')
        elseif subcmd == 'list' then
            local count = 0
            for _, entry in pairs(settings.buffs) do
                windower.add_to_chat(8, 'MagianWS: "' .. entry.name .. '" (' .. entry.type .. ', buff ID ' .. entry.buff_id .. ')')
                count = count + 1
            end
            if count == 0 then
                windower.add_to_chat(8, 'MagianWS: No buffs configured.')
            end
        end
    elseif cmd == 'provoke' then
        local arg = (...)
        if arg == 'on' then
            settings.provoke = true
            last_provoke_time = 0
        elseif arg == 'off' then
            settings.provoke = false
        else
            windower.add_to_chat(8, 'MagianWS: Usage: provoke on|off')
            return
        end
        settings:save()
        print_status()
    elseif cmd == 'follow' then
        local arg = (...)
        if arg == 'on' then
            settings.follow = true
        elseif arg == 'off' then
            settings.follow = false
        else
            windower.add_to_chat(8, 'MagianWS: Usage: follow on|off')
            return
        end
        settings:save()
        print_status()
    elseif cmd == 'target' then
        local arg = table.concat({...}, ' ')
        if arg == '' or arg:lower() == 'off' then
            settings.target_name = ''
            windower.add_to_chat(8, 'MagianWS: Auto-target disabled.')
        else
            settings.target_name = arg
            windower.add_to_chat(8, 'MagianWS: Auto-target set to "' .. arg .. '".')
        end
        settings:save()
        print_status()
        update_display()
    elseif cmd == 'trial' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        if subcmd == 'set' then
            local val = tonumber(rest[1])
            if val then
                settings.trial_remaining = val
                settings:save()
                update_display()
                windower.add_to_chat(8, 'MagianWS: Trial remaining set to ' .. val .. '.')
            else
                windower.add_to_chat(8, 'MagianWS: Usage: trial set <number>')
            end
        elseif subcmd == 'reset' then
            settings.trial_remaining = -1
            settings:save()
            update_display()
            windower.add_to_chat(8, 'MagianWS: Trial remaining reset.')
        else
            local rem_str = settings.trial_remaining >= 0 and tostring(settings.trial_remaining) or 'unknown'
            windower.add_to_chat(8, 'MagianWS: Trial remaining: ' .. rem_str)
        end
    elseif cmd == 'show' then
        display_visible = true
        update_display()
    elseif cmd == 'hide' then
        display_visible = false
        update_display()
    elseif cmd == 'start' then
        if settings.target_name == '' then
            windower.add_to_chat(8, 'MagianWS: Set a target first: //magianws target <name>')
        else
            active = true
            windower.add_to_chat(8, 'MagianWS: Started — targeting "' .. settings.target_name .. '".')
            update_display()
        end
    elseif cmd == 'stop' then
        active = false
        windower.add_to_chat(8, 'MagianWS: Stopped.')
        update_display()
    elseif cmd == 'debug' then
        local arg = (...)
        if arg == 'on' then
            debug_target = true
            windower.add_to_chat(8, 'MagianWS: Target debug logging ON.')
        elseif arg == 'off' then
            debug_target = false
            windower.add_to_chat(8, 'MagianWS: Target debug logging OFF.')
        else
            windower.add_to_chat(8, 'MagianWS: Usage: debug on|off')
        end
    elseif cmd == 'status' then
        print_status()
    end
end)

windower.register_event('status change', function(new_status)
    if new_status == 1 then
        try_eat_food()
        maintain_buffs()
    end
end)

windower.register_event('lose buff', function(buff_id)
    if buff_id == 251 then
        try_eat_food()
    end
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        for _, entry in pairs(settings.buffs) do
            if tonumber(entry.buff_id) == buff_id then
                cast_buff(entry.name, entry.type)
                break
            end
        end
    end
end)

windower.register_event('incoming text', function(original, modified, mode)
    local text = strip_colors(original)
    local lower = text:lower()

    if settings.follow then
        local player = windower.ffxi.get_player()
        if player.status == 1 then
            if lower:find('out of range') or lower:find('cannot see') then
                windower.send_command('input /follow <t>')
            end
        end
    end

    local n = parse_trial_remaining(lower)
    if n then
        settings.trial_remaining = n
        settings:save()
        update_display()
    end
end)

windower.register_event('tp change', function(new_tp, old_tp)
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        try_provoke()
        if new_tp >= settings.tp_threshold then
            execute_ws()
        end
    end
end)



print_status()
update_display()
try_equip_ammo()
try_eat_food_if_engaged()
maintain_buffs()
execute_ws()
