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
local sc_data = require('sc_data')

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
defaults.ws2_name = ''
defaults.tp_threshold = 1000
defaults.food_name = ''
defaults.ammo_name = ''
defaults.buff_sets = {}
defaults.active_buff_set = ''
defaults.provoke = false
defaults.follow = false
defaults.target_names = {}
defaults.pull_mode = false
defaults.pull_range = 25
defaults.pull_method = 'ra'
defaults.home_set = false
defaults.home_x = 0
defaults.home_y = 0
defaults.home_z = 0
defaults.trial_remaining = -1
defaults.mode = 'trials'
defaults.target_spells = {}
defaults.use_item = ''
defaults.scan_range = 40
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

local session_start = os.time()
local session_exp   = 0
local session_cp    = 0
local session_ep    = 0

local _init_player  = windower.ffxi.get_player()
local player_name_lower = _init_player and _init_player.name and _init_player.name:lower() or ''

local last_provoke_time = 0
local PROVOKE_RECAST = 30

local function parse_trial_remaining(lower_text)
    return tonumber(lower_text:match('trial %d+: (%d+) objectives? remain'))
        or tonumber(lower_text:match('(%d+) objectives? remain'))
        or tonumber(lower_text:match('(%d+) more'))
        or tonumber(lower_text:match('(%d+) remaining'))
        or tonumber(lower_text:match('remaining[^%d]*(%d+)'))
end

local ATTACK_RANGE_SQ = 400  -- 20 yalms; mob.distance is squared
-- PULL_RANGE_SQ derived from settings.pull_range at use time (mob.distance is squared)
local HOME_RANGE      = 10   -- yalms; within this = considered at home

local function home_distance()
    if not settings.home_set then return nil end
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return nil end
    local dx = settings.home_x - me.x
    local dy = settings.home_y - me.y
    local dz = settings.home_z - me.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function format_rate(total)
    local elapsed = os.time() - session_start
    if elapsed < 1 then return '---' end
    local n = math.floor(total / (elapsed / 3600))
    return tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

local function has_targets()
    return next(settings.target_names) ~= nil
end

local function is_target_mob(mob_name)
    local lower = mob_name:lower()
    for _, entry in pairs(settings.target_names) do
        if entry.name:lower() == lower then return true end
    end
    return false
end

local function target_names_display()
    local names = {}
    for _, entry in pairs(settings.target_names) do
        names[#names+1] = entry.name
    end
    table.sort(names)
    return table.concat(names, ', ')
end

local function update_display()
    if not display_visible then
        display:hide()
        return
    end
    local mode_label = settings.mode == 'exp' and '\\cs(160,220,160)Exp\\cr' or '\\cs(255,180,80)Trials\\cr'
    local rem_line = ''
    if settings.mode == 'trials' then
        local rem_str
        if settings.trial_remaining < 0 then
            rem_str = '\\cs(160,160,160)?\\cr'
        else
            rem_str = ('\\cs(100,255,100)%d\\cr'):format(settings.trial_remaining)
        end
        rem_line = '\n  Remaining: ' .. rem_str
    end
    local target_line = ''
    if has_targets() then
        local active_str = active and '\\cs(100,255,100)▶\\cr ' or '\\cs(160,160,160)■\\cr '
        target_line = '\n  Target: ' .. active_str .. '\\cs(255,180,80)' .. target_names_display() .. '\\cr'
    end
    local home_line = ''
    if settings.home_set then
        local dist = home_distance()
        if dist then
            local color = dist <= HOME_RANGE and '100,255,100' or '255,140,80'
            home_line = ('\n  Home: \\cs(%s)%.1fy\\cr'):format(color, dist)
        end
    end
    local rate_lines = ''
    if session_exp > 0 then
        rate_lines = rate_lines .. ('\n  EXP/hr:  \\cs(200,220,255)%s\\cr'):format(format_rate(session_exp))
    end
    if session_cp > 0 then
        rate_lines = rate_lines .. ('\n  CP/hr:   \\cs(200,220,255)%s\\cr'):format(format_rate(session_cp))
    end
    if session_ep > 0 then
        rate_lines = rate_lines .. ('\n  EP/hr:   \\cs(200,220,255)%s\\cr'):format(format_rate(session_ep))
    end
    local ws_display = settings.ws2_name ~= ''
        and (settings.ws_name .. ' \\cs(160,160,160)→\\cr \\cs(200,220,255)' .. settings.ws2_name .. '\\cr')
        or settings.ws_name
    display:text(('\\cs(255,200,80)[ MagianWS | %s]\\cr\n  WS: \\cs(200,220,255)%s\\cr%s%s%s%s'):format(mode_label, ws_display, rem_line, target_line, home_line, rate_lines))
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
            if ja.en and ja.en:lower() == lower then
                local bid = (ja.status and ja.status ~= 0) and ja.status or 0
                return {name = ja.en, type = 'ability', buff_id = bid, recast_id = ja.recast_id}
            end
        end
    end
    return nil
end

local function find_spell_name(name)
    local lower = name:lower()
    for _, spell in pairs(res.spells) do
        if spell.en and spell.en:lower() == lower then
            return spell.en
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

local last_buff_attempt = {}
local BUFF_ATTEMPT_COOLDOWN = 20.0

local last_target_spell_cast = {}
local TARGET_SPELL_INTERVAL  = 60  -- default seconds between target spell recasts
local target_spell_delay_until = 0  -- os.clock() after which target spells may fire

local function get_active_buffs()
    if settings.active_buff_set == '' then return {} end
    return settings.buff_sets[settings.active_buff_set] or {}
end

local function maintain_buffs()
    local player = windower.ffxi.get_player()
    if player.status ~= 1 then return end
    local delay = 0
    local now = os.clock()
    local ab_recasts = nil
    for _, entry in pairs(get_active_buffs()) do
        local needs_cast
        if (entry.buff_id or 0) == 0 then
            -- Ability with no status effect (e.g. Meditate): cast when off recast
            if not ab_recasts then ab_recasts = windower.ffxi.get_ability_recasts() end
            local recast = entry.recast_id and (ab_recasts[entry.recast_id] or 0) or 0
            needs_cast = (recast == 0)
        else
            needs_cast = not is_buff_active(entry.buff_id)
        end
        if needs_cast then
            local last = last_buff_attempt[entry.name] or 0
            if now >= last + BUFF_ATTEMPT_COOLDOWN then
                cast_buff(entry.name, entry.type, delay)
                last_buff_attempt[entry.name] = now + delay
                delay = delay + 6
            end
        end
    end
end

local function maintain_target_spells()
    local player = windower.ffxi.get_player()
    if player.status ~= 1 then return end
    if os.clock() < target_spell_delay_until then return end
    if next(settings.target_spells) == nil then return end
    local now = os.time()
    local delay = 0
    for _, entry in pairs(settings.target_spells) do
        local duration = entry.duration or TARGET_SPELL_INTERVAL
        local last = last_target_spell_cast[entry.name] or 0
        if now >= last + duration then
            last_target_spell_cast[entry.name] = now + delay
            if delay > 0 then
                windower.send_command('wait ' .. delay .. '; input /ma "' .. entry.name .. '" <t>')
            else
                windower.send_command('input /ma "' .. entry.name .. '" <t>')
            end
            delay = delay + 3
        end
    end
end

local last_item_use     = 0
local ITEM_USE_COOLDOWN = 5.0

local function try_eat_food()
    if settings.food_name ~= '' and not is_food_active() and find_in_inventory(settings.food_name) then
        windower.send_command('input /item "' .. settings.food_name .. '" <me>')
    end
end

local function try_use_item()
    if settings.use_item == '' then return end
    local now = os.clock()
    if now < last_item_use + ITEM_USE_COOLDOWN then return end
    if find_in_inventory(settings.use_item) then
        last_item_use = now
        windower.send_command('input /item "' .. settings.use_item .. '" <me>')
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

local function find_target_mob()
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return nil end
    local mobs = windower.ffxi.get_mob_array()
    if not mobs then return nil end

    -- Rank by distance to home when set; otherwise by distance to player
    local ref_x = settings.home_set and settings.home_x or me.x
    local ref_y = settings.home_set and settings.home_y or me.y
    local ref_z = settings.home_set and settings.home_z or me.z

    local best, best_dist = nil, math.huge

    for _, mob in pairs(mobs) do
        if mob and mob.id and mob.id ~= 0
                and mob.name and is_target_mob(mob.name)
                and not is_player_or_trust(mob.spawn_type or 0)
                and (mob.status or 0) ~= 2
                and (mob.hpp or 0) > 0
                and (mob.claim_id or 0) == 0
        then
            -- When anchored at home with pull mode, only consider mobs within RA range of home
            local max_range = (settings.home_set and settings.pull_mode) and settings.pull_range or settings.scan_range
            local origin_x  = (settings.home_set and settings.pull_mode) and settings.home_x or me.x
            local origin_y  = (settings.home_set and settings.pull_mode) and settings.home_y or me.y
            local origin_z  = (settings.home_set and settings.pull_mode) and settings.home_z or me.z
            local pdx = mob.x - origin_x
            local pdy = mob.y - origin_y
            local pdz = mob.z - origin_z
            if math.sqrt(pdx*pdx + pdy*pdy + pdz*pdz) <= max_range then
                local rdx = mob.x - ref_x
                local rdy = mob.y - ref_y
                local rdz = mob.z - ref_z
                local rank = math.sqrt(rdx*rdx + rdy*rdy + rdz*rdz)
                if rank < best_dist then
                    best_dist = rank
                    best = mob
                end
            end
        end
    end
    return best
end

local sc_window = nil  -- open skillchain window: {active, delay_until, expires} or nil

local last_scan_tick  = 0
local SCAN_INTERVAL   = 2.0
local last_buff_tick  = 0
local BUFF_CHECK_INTERVAL = 10.0
local debug_target    = false
local active          = false  -- start/stop toggle (not persisted)
local returning_home  = false  -- true while windower.ffxi.run() is active toward home
local unlock_at       = 0     -- os.clock() timestamp to send the lock-off packet
local pull_sent       = false  -- true after /ra fired; reset when acquiring a new target
local pull_sent_at    = 0     -- os.clock() when /ra was sent; used for pull failsafe
local PULL_TIMEOUT    = 15.0  -- seconds before retrying a failed pull

local function dbg(msg)
    if debug_target then
        windower.add_to_chat(8, 'MagianWS[dbg]: ' .. msg)
    end
end

local function stop_return_home()
    if returning_home then
        returning_home = false
        windower.ffxi.run(false)
    end
end

local function try_return_home()
    if not settings.home_set then return end
    if settings.pull_mode then return end
    local dist = home_distance()
    if not dist then return end

    if dist <= HOME_RANGE then
        stop_return_home()
        return
    end

    local me = windower.ffxi.get_mob_by_target('me')
    if not me then return end
    local dx = settings.home_x - me.x
    local dy = settings.home_y - me.y
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return end

    returning_home = true
    dbg('run[return-home] dist=' .. string.format('%.1f', dist) .. 'y')
    windower.ffxi.run(dx / len, dy / len)
end

local function face_mob(mob)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me or not mob then return end
    -- FFXI angle convention: 0=east, π/2=south, π=west, 3π/2=north (clockwise).
    -- from_radian(r) = {cos(r), -sin(r)}, so the target angle = atan2(-(dy), dx).
    windower.ffxi.turn(math.atan2(me.y - mob.y, mob.x - me.x))
end

local function try_engage_target()
    if not active then return end
    if not has_targets() then return end
    local player = windower.ffxi.get_player()
    if not player or (player.status ~= 0 and player.status ~= 1) then return end
    dbg('scan | status=' .. tostring(player.status) .. ' targets="' .. target_names_display() .. '"')

    if player.status == 1 then
        local current_target = windower.ffxi.get_mob_by_target('t')
        if current_target then
            if settings.home_set or not settings.follow then
                face_mob(current_target)
            else
                dbg('follow[engaged] target="' .. (current_target.name or '?') .. '" hpp=' .. tostring(current_target.hpp) .. ' status=' .. tostring(current_target.status))
                pcall(function()
                    packets.inject(packets.new('incoming', 0x058, {
                        ['Player']       = player.id,
                        ['Target']       = current_target.id,
                        ['Player Index'] = player.index,
                    }))
                end)
                windower.send_command('input /follow <t>')
                unlock_at = os.clock() + 1.0
            end
        end
        return
    end

    -- Already have the right mob targeted — approach or attack
    local current_target = windower.ffxi.get_mob_by_target('t')
    local target_claim = current_target and (current_target.claim_id or 0)
    local claimed_by_other = target_claim ~= nil and target_claim ~= 0 and target_claim ~= player.id
    if current_target and current_target.name
            and is_target_mob(current_target.name)
            and (current_target.hpp or 0) > 0
            and (current_target.status or 0) ~= 2
            and not claimed_by_other then
        local dist_sq = current_target.distance or math.huge
        if settings.pull_mode then
            if not pull_sent then
                if dist_sq <= settings.pull_range * settings.pull_range then
                    face_mob(current_target)
                    local method = settings.pull_method or 'ra'
                    if method == 'magic' then
                        local pull_spell = nil
                        for _, e in pairs(settings.target_spells) do pull_spell = e; break end
                        if pull_spell then
                            dbg('pull mode — magic pull: ' .. pull_spell.name .. ' (dist_sq=' .. tostring(dist_sq) .. ')')
                            windower.send_command('wait 1; input /ma "' .. pull_spell.name .. '" <t>')
                            pull_sent = true
                            pull_sent_at = os.clock() + 1
                            last_target_spell_cast[pull_spell.name] = os.time()
                        else
                            windower.add_to_chat(8, 'MagianWS: pull method is magic but no target spells configured.')
                        end
                    else
                        dbg('pull mode — RA pull (dist_sq=' .. tostring(dist_sq) .. ')')
                        windower.send_command('wait 2; input /ra <t>')
                        pull_sent = true
                        pull_sent_at = os.clock() + 2
                    end
                else
                    dbg('pull mode — approaching to pull (dist_sq=' .. tostring(dist_sq) .. ')')
                    windower.send_command('input /follow <t>')
                end
            elseif dist_sq <= ATTACK_RANGE_SQ then
                dbg('in range — attacking')
                windower.send_command('input /attack')
            else
                if os.clock() >= pull_sent_at + PULL_TIMEOUT then
                    dbg('pull timed out — retrying RA')
                    pull_sent = false
                else
                    dbg('pull mode — waiting for mob (dist_sq=' .. tostring(dist_sq) .. ')')
                end
            end
        else
            dbg('follow[approach] target="' .. (current_target.name or '?') .. '" hpp=' .. tostring(current_target.hpp) .. ' status=' .. tostring(current_target.status) .. ' dist_sq=' .. tostring(dist_sq))
            windower.send_command('input /follow <t>')
            if dist_sq <= ATTACK_RANGE_SQ then
                dbg('in range — attacking')
                windower.send_command('input /attack')
            end
        end
        return
    end

    -- Target mob became invalid (died, claimed, etc.) — deselect to cancel follow
    if current_target and current_target.name and is_target_mob(current_target.name) then
        dbg('deselect[invalid] target="' .. current_target.name .. '" hpp=' .. tostring(current_target.hpp) .. ' status=' .. tostring(current_target.status) .. ' claim=' .. tostring(current_target.claim_id))
        pull_sent = false
        pcall(function()
            packets.inject(packets.new('incoming', 0x058, {
                ['Player']       = player.id,
                ['Target']       = 0,
                ['Player Index'] = player.index,
            }))
        end)
        return
    end

    -- No valid target yet — scan and lock on to the closest matching mob
    pull_sent = false
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
            if is_target_mob(mob.name) then
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
                    local scan_origin_x = (settings.home_set and settings.pull_mode) and settings.home_x or (me and me.x or 0)
                    local scan_origin_y = (settings.home_set and settings.pull_mode) and settings.home_y or (me and me.y or 0)
                    local scan_origin_z = (settings.home_set and settings.pull_mode) and settings.home_z or (me and me.z or 0)
                    local max_range = (settings.home_set and settings.pull_mode) and settings.pull_range or settings.scan_range
                    local ddx, ddy, ddz = mob.x - scan_origin_x, mob.y - scan_origin_y, mob.z - scan_origin_z
                    local dist = math.sqrt(ddx*ddx + ddy*ddy + ddz*ddz)
                    if dist > max_range then
                        reason = 'SKIP:range(' .. string.format('%.0f', dist) .. '>' .. tostring(max_range) .. ')'
                    else
                        reason = 'OK'
                    end
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

    local mob = find_target_mob()
    if mob then
        stop_return_home()
        dbg('targeting id=' .. tostring(mob.id) .. ' index=' .. tostring(mob.index))
        local ok, err = pcall(function()
            packets.inject(packets.new('incoming', 0x058, {
                ['Player']       = player.id,
                ['Target']       = mob.id,
                ['Player Index'] = player.index,
            }))
        end)
        if ok then
            if settings.pull_mode and settings.home_set then
                dbg('targeted — holding at home, waiting for mob to enter RA range')
            else
                dbg(settings.pull_mode and 'targeted — approaching to pull' or 'targeted — following')
                windower.send_command('input /follow <t>')
            end
        else
            dbg('packet error: ' .. tostring(err))
        end
    else
        dbg('find_target_mob returned nil')
        try_return_home()
    end
end

windower.register_event('prerender', function()
    local now = os.clock()

    if unlock_at > 0 and now >= unlock_at then
        unlock_at = 0
        local player = windower.ffxi.get_player()
        if player then
            pcall(function()
                packets.inject(packets.new('incoming', 0x058, {
                    ['Player']       = player.id,
                    ['Target']       = 0,
                    ['Player Index'] = player.index,
                }))
            end)
        end
    end

    if now >= last_scan_tick + SCAN_INTERVAL then
        last_scan_tick = now
        if settings.home_set or settings.mode == 'exp' then update_display() end
        try_engage_target()
        if active then try_use_item() end
    end

    if now >= last_buff_tick + BUFF_CHECK_INTERVAL then
        last_buff_tick = now
        if active then
            maintain_buffs()
            maintain_target_spells()
        end
    end
end)

local function print_status()
    local buff_count = 0
    for _ in pairs(get_active_buffs()) do buff_count = buff_count + 1 end
    local buff_str = settings.active_buff_set ~= '' and (settings.active_buff_set .. ' (' .. buff_count .. ')') or 'off'
    local rem_str = settings.trial_remaining >= 0 and tostring(settings.trial_remaining) or '?'
    local home_str = settings.home_set and ('(%.1f, %.1f, %.1f)'):format(settings.home_x, settings.home_y, settings.home_z) or 'off'
    windower.add_to_chat(8, 'MagianWS: Weaponskill: "' .. settings.ws_name .. '" | TP threshold: ' .. settings.tp_threshold .. ' | Remaining: ' .. rem_str .. ' | Food: ' .. (settings.food_name ~= '' and settings.food_name or 'off') .. ' | Ammo: ' .. (settings.ammo_name ~= '' and settings.ammo_name or 'off') .. ' | Item: ' .. (settings.use_item ~= '' and settings.use_item or 'off') .. ' | Buffs: ' .. buff_str .. ' | Provoke: ' .. (settings.provoke and 'on' or 'off') .. ' | Follow: ' .. (settings.follow and 'on' or 'off') .. ' | Pull: ' .. (settings.pull_mode and 'on' or 'off') .. ' | Range: ' .. tostring(settings.scan_range) .. 'y | Home: ' .. home_str .. ' | Target: ' .. (has_targets() and target_names_display() or 'off') .. ' | Active: ' .. (active and 'yes' or 'no'))
end

local function try_eat_food_if_engaged()
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        try_eat_food()
    end
end

-- Returns the level of skillchain formed (1-4) if ws2_props can close the
-- resonance opened by ws1_props, or nil if no chain is possible.
local function check_sc_props(ws1_props, ws2_props)
    for _, first in ipairs(ws1_props) do
        local combo = sc_data.sc_info[first]
        if combo then
            for _, second in ipairs(ws2_props) do
                local result = combo[second]
                if result then return result[1], result[2] end
            end
        end
    end
    return nil
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
    elseif cmd == 'ws2' then
        local arg = table.concat({...}, ' ')
        if arg == '' or arg:lower() == 'off' then
            settings.ws2_name = ''
            sc_window = nil
            windower.add_to_chat(8, 'MagianWS: WS2 disabled.')
        else
            local ws_data = sc_data.ws_by_name[arg:lower()]
            if ws_data then
                settings.ws2_name = arg
                windower.add_to_chat(8, ('MagianWS: WS2 set to "%s" (%s).'):format(arg, table.concat(ws_data.skillchain, '/')))
            else
                -- Accept the name even if not in skill data (might be a newer WS)
                settings.ws2_name = arg
                windower.add_to_chat(8, ('MagianWS: WS2 set to "%s" (no SC data — chain detection unavailable).'):format(arg))
            end
        end
        settings:save()
        update_display()
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
    elseif cmd == 'item' then
        local arg = table.concat({...}, ' ')
        if arg == '' or arg:lower() == 'off' then
            settings.use_item = ''
        else
            settings.use_item = arg
        end
        settings:save()
        print_status()
    elseif cmd == 'buff' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        local active_set_name = settings.active_buff_set
        if subcmd == 'add' then
            if active_set_name == '' then
                windower.add_to_chat(8, 'MagianWS: No active buff set. Use: //magianws buffset use <name>')
            else
                local buff_name = table.concat(rest, ' ')
                local info = find_buff_info(buff_name)
                if info then
                    local set = settings.buff_sets[active_set_name]
                    local key = info.name:gsub(' ', '_')
                    set[key] = {name = info.name, type = info.type, buff_id = info.buff_id}
                    settings:save()
                    windower.add_to_chat(8, 'MagianWS: Added "' .. info.name .. '" to set "' .. active_set_name .. '".')
                else
                    windower.add_to_chat(8, 'MagianWS: Unknown buff "' .. buff_name .. '".')
                end
            end
        elseif subcmd == 'remove' then
            if active_set_name == '' then
                windower.add_to_chat(8, 'MagianWS: No active buff set.')
            else
                local buff_name = table.concat(rest, ' ')
                local search_key = buff_name:gsub(' ', '_')
                local set = settings.buff_sets[active_set_name]
                local found = false
                for k in pairs(set) do
                    if k:lower() == search_key:lower() then
                        local display_name = set[k].name or k
                        set[k] = nil
                        settings:save()
                        windower.add_to_chat(8, 'MagianWS: Removed "' .. display_name .. '" from set "' .. active_set_name .. '".')
                        found = true
                        break
                    end
                end
                if not found then
                    windower.add_to_chat(8, 'MagianWS: Buff "' .. buff_name .. '" not found in set "' .. active_set_name .. '".')
                end
            end
        elseif subcmd == 'list' then
            if active_set_name == '' then
                windower.add_to_chat(8, 'MagianWS: No active buff set.')
            else
                local set = settings.buff_sets[active_set_name]
                local count = 0
                for _, entry in pairs(set) do
                    windower.add_to_chat(8, 'MagianWS: "' .. entry.name .. '" (' .. entry.type .. ')')
                    count = count + 1
                end
                if count == 0 then
                    windower.add_to_chat(8, 'MagianWS: Set "' .. active_set_name .. '" has no buffs.')
                end
            end
        end
    elseif cmd == 'buffset' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        local name = table.concat(rest, ' ')
        if subcmd == 'create' then
            if name == '' then
                windower.add_to_chat(8, 'MagianWS: Usage: buffset create <name>')
            elseif settings.buff_sets[name] then
                windower.add_to_chat(8, 'MagianWS: Set "' .. name .. '" already exists.')
            else
                settings.buff_sets[name] = {}
                settings.active_buff_set = name
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Created buff set "' .. name .. '" (now active).')
            end
        elseif subcmd == 'use' then
            if name == '' or name:lower() == 'off' then
                settings.active_buff_set = ''
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Buff set deactivated.')
            elseif settings.buff_sets[name] then
                settings.active_buff_set = name
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Using buff set "' .. name .. '".')
            else
                windower.add_to_chat(8, 'MagianWS: Set "' .. name .. '" not found. Use: //magianws buffset create <name>')
            end
        elseif subcmd == 'delete' then
            if name == '' then
                windower.add_to_chat(8, 'MagianWS: Usage: buffset delete <name>')
            elseif settings.buff_sets[name] then
                settings.buff_sets[name] = nil
                if settings.active_buff_set == name then settings.active_buff_set = '' end
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Deleted buff set "' .. name .. '".')
            else
                windower.add_to_chat(8, 'MagianWS: Set "' .. name .. '" not found.')
            end
        elseif subcmd == 'list' then
            local count = 0
            for set_name, set in pairs(settings.buff_sets) do
                local n = 0
                for _ in pairs(set) do n = n + 1 end
                local marker = set_name == settings.active_buff_set and ' ◀' or ''
                windower.add_to_chat(8, 'MagianWS: "' .. set_name .. '" — ' .. n .. ' buff(s)' .. marker)
                count = count + 1
            end
            if count == 0 then
                windower.add_to_chat(8, 'MagianWS: No buff sets configured.')
            end
        else
            windower.add_to_chat(8, 'MagianWS: Usage: buffset create|use|delete|list <name>')
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
    elseif cmd == 'home' then
        local arg = (...)
        if arg == 'set' then
            local me = windower.ffxi.get_mob_by_target('me')
            if me then
                settings.home_set = true
                settings.home_x = me.x
                settings.home_y = me.y
                settings.home_z = me.z
                settings:save()
                windower.add_to_chat(8, ('MagianWS: Home set to (%.1f, %.1f, %.1f).'):format(me.x, me.y, me.z))
                update_display()
            else
                windower.add_to_chat(8, 'MagianWS: Could not read player position.')
            end
        elseif arg == 'clear' then
            settings.home_set = false
            settings:save()
            windower.add_to_chat(8, 'MagianWS: Home point cleared.')
            update_display()
        else
            if settings.home_set then
                local dist = home_distance()
                local dist_str = dist and string.format('%.1f', dist) .. 'y away' or 'unknown'
                windower.add_to_chat(8, ('MagianWS: Home at (%.1f, %.1f, %.1f) — %s.'):format(settings.home_x, settings.home_y, settings.home_z, dist_str))
            else
                windower.add_to_chat(8, 'MagianWS: No home point set. Use //magianws home set.')
            end
        end
    elseif cmd == 'pull' then
        local arg = (...)
        local rest = {select(2, ...)}
        if arg == 'on' then
            settings.pull_mode = true
            settings:save()
            print_status()
        elseif arg == 'off' then
            settings.pull_mode = false
            settings:save()
            print_status()
        elseif arg == 'method' then
            local method = rest[1] and rest[1]:lower()
            if method == 'ra' or method == 'magic' then
                settings.pull_method = method
                settings:save()
                local note = method == 'magic' and ' (set pullrange <=21)' or ''
                windower.add_to_chat(8, 'MagianWS: Pull method set to "' .. method .. '".' .. note)
            else
                windower.add_to_chat(8, 'MagianWS: Usage: pull method ra|magic')
            end
        else
            windower.add_to_chat(8, 'MagianWS: Usage: pull on|off  or  pull method ra|magic')
        end
    elseif cmd == 'pullrange' then
        local val = tonumber((...))
        if val and val > 0 then
            settings.pull_range = val
            settings:save()
            windower.add_to_chat(8, ('MagianWS: Pull range set to %d yalms.'):format(val))
        else
            windower.add_to_chat(8, ('MagianWS: Pull range: %d yalms. Usage: pullrange <yalms>'):format(settings.pull_range))
        end
    elseif cmd == 'range' then
        local val = tonumber((...))
        if val and val > 0 then
            settings.scan_range = val
            settings:save()
            windower.add_to_chat(8, ('MagianWS: Scan range set to %d yalms.'):format(val))
        else
            windower.add_to_chat(8, ('MagianWS: Scan range: %d yalms. Usage: range <yalms>'):format(settings.scan_range))
        end
    elseif cmd == 'target' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        if subcmd == nil or subcmd == 'off' then
            settings.target_names = {}
            settings:save()
            windower.add_to_chat(8, 'MagianWS: Auto-target disabled.')
            update_display()
        elseif subcmd == 'add' then
            local name = table.concat(rest, ' ')
            if name ~= '' then
                local key = name:gsub(' ', '_')
                settings.target_names[key] = {name = name}
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Added target "' .. name .. '".')
                update_display()
            else
                windower.add_to_chat(8, 'MagianWS: Usage: target add <name>')
            end
        elseif subcmd == 'remove' then
            local name = table.concat(rest, ' ')
            local search = name:lower()
            local found = false
            for k, entry in pairs(settings.target_names) do
                if entry.name:lower() == search then
                    settings.target_names[k] = nil
                    settings:save()
                    windower.add_to_chat(8, 'MagianWS: Removed target "' .. entry.name .. '".')
                    update_display()
                    found = true
                    break
                end
            end
            if not found then
                windower.add_to_chat(8, 'MagianWS: Target "' .. name .. '" not found.')
            end
        elseif subcmd == 'list' then
            if has_targets() then
                windower.add_to_chat(8, 'MagianWS: Targets: ' .. target_names_display())
            else
                windower.add_to_chat(8, 'MagianWS: No targets configured.')
            end
        else
            -- Plain name (no subcommand) — replace all targets with this one
            local name = table.concat({subcmd, unpack(rest)}, ' ')
            settings.target_names = {}
            settings.target_names[name:gsub(' ', '_')] = {name = name}
            settings:save()
            windower.add_to_chat(8, 'MagianWS: Auto-target set to "' .. name .. '".')
            update_display()
        end
        print_status()
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
        if not has_targets() then
            windower.add_to_chat(8, 'MagianWS: Set a target first: //magianws target <name>')
        else
            active = true
            windower.add_to_chat(8, 'MagianWS: Started — targeting ' .. target_names_display() .. '.')
            update_display()
        end
    elseif cmd == 'stop' then
        active = false
        stop_return_home()
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
    elseif cmd == 'exp' then
        local subcmd = (...)
        if subcmd == 'reset' then
            session_start = os.time()
            session_exp   = 0
            session_cp    = 0
            session_ep    = 0
            update_display()
            windower.add_to_chat(8, 'MagianWS: Session reset.')
        else
            local elapsed = os.time() - session_start
            local mins = math.floor(elapsed / 60)
            windower.add_to_chat(8, ('MagianWS: Session %dm — EXP/hr: %s | CP/hr: %s | EP/hr: %s'):format(
                mins, format_rate(session_exp), format_rate(session_cp), format_rate(session_ep)))
        end
    elseif cmd == 'mode' then
        local arg = (...)
        if arg == 'trials' or arg == 'exp' then
            settings.mode = arg
            settings:save()
            update_display()
            windower.add_to_chat(8, 'MagianWS: Mode set to ' .. arg .. '.')
        else
            windower.add_to_chat(8, 'MagianWS: Usage: mode trials|exp')
        end
    elseif cmd == 'spell' then
        local subcmd = (...)
        local rest = {select(2, ...)}
        if subcmd == 'add' then
            local spell_name = table.concat(rest, ' ')
            local found = find_spell_name(spell_name)
            if found then
                local key = found:gsub(' ', '_'):lower()
                settings.target_spells[key] = {name = found, duration = TARGET_SPELL_INTERVAL}
                settings:save()
                windower.add_to_chat(8, 'MagianWS: Added target spell "' .. found .. '".')
            else
                windower.add_to_chat(8, 'MagianWS: Unknown spell "' .. spell_name .. '". Check spelling and capitalisation.')
            end
        elseif subcmd == 'remove' then
            local spell_name = table.concat(rest, ' ')
            local search = spell_name:lower()
            local found = false
            for k, entry in pairs(settings.target_spells) do
                if entry.name:lower() == search then
                    settings.target_spells[k] = nil
                    settings:save()
                    windower.add_to_chat(8, 'MagianWS: Removed target spell "' .. entry.name .. '".')
                    found = true
                    break
                end
            end
            if not found then
                windower.add_to_chat(8, 'MagianWS: Spell "' .. spell_name .. '" not in list.')
            end
        elseif subcmd == 'list' then
            if next(settings.target_spells) == nil then
                windower.add_to_chat(8, 'MagianWS: No target spells configured.')
            else
                for _, entry in pairs(settings.target_spells) do
                    windower.add_to_chat(8, 'MagianWS: "' .. entry.name .. '" (every ' .. (entry.duration or TARGET_SPELL_INTERVAL) .. 's)')
                end
            end
        elseif subcmd == 'off' then
            settings.target_spells = {}
            settings:save()
            windower.add_to_chat(8, 'MagianWS: All target spells cleared.')
        else
            windower.add_to_chat(8, 'MagianWS: Usage: spell add|remove|list|off <name>')
        end
    elseif cmd == 'status' then
        print_status()
    end
end)

windower.register_event('status change', function(new_status)
    if new_status == 1 then
        stop_return_home()
        if active then
            try_eat_food()
            maintain_buffs()
            last_target_spell_cast = {}
            target_spell_delay_until = pull_sent and (os.clock() + 3.0) or 0
            maintain_target_spells()
        end
    else
        sc_window = nil  -- clear any open chain window on disengage or death
    end
end)

windower.register_event('lose buff', function(buff_id)
    if not active then return end
    if buff_id == 251 then
        try_eat_food()
    end
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        for _, entry in pairs(get_active_buffs()) do
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

    if player_name_lower ~= '' then
        local pn = player_name_lower
        local exp = lower:match(pn .. ' gains (%d+) experience points')
                 or lower:match(pn .. ' gains (%d+) limit points')
        if exp then session_exp = session_exp + tonumber(exp); update_display() end

        local cp = lower:match(pn .. ' gains (%d+) capacity points')
        if cp then session_cp = session_cp + tonumber(cp); update_display() end

        local ep = lower:match(pn .. ' gains (%d+) exemplar points')
        if ep then session_ep = session_ep + tonumber(ep); update_display() end
    end
end)

-- Detect when player's weaponskill resolves and open a skillchain window.
-- Category 3 = weaponskill_finish in action packets (0x028).
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x028 or settings.ws2_name == '' then return end
    local act = windower.packets.parse_action(data)
    if act.category ~= 3 then return end
    local player = windower.ffxi.get_player()
    if not player or act.actor_id ~= player.id then return end
    local ws_data = sc_data.weapon_skills[act.param]
    if not ws_data then return end
    local delay = ws_data.delay or 3
    sc_window = {
        active     = ws_data.skillchain,
        delay_until= os.clock() + delay,
        expires    = os.clock() + delay + 8,
    }
    dbg('SC window opened: ' .. ws_data.en .. ' → ' .. table.concat(ws_data.skillchain, '/'))
end)

windower.register_event('tp change', function(new_tp, old_tp)
    local player = windower.ffxi.get_player()
    if not player or player.status ~= 1 then return end
    try_provoke()

    -- If a skillchain window is open, try to close it with WS2 before firing WS1
    if sc_window and settings.ws2_name ~= '' then
        local now = os.clock()
        if now >= sc_window.expires then
            sc_window = nil
        elseif now >= sc_window.delay_until and new_tp >= settings.tp_threshold then
            local ws2_data = sc_data.ws_by_name[settings.ws2_name:lower()]
            if ws2_data then
                local level, chain_name = check_sc_props(sc_window.active, ws2_data.skillchain)
                if level then
                    dbg(('SC close: %s → Lv.%d %s'):format(settings.ws2_name, level, chain_name or '?'))
                    try_equip_ammo()
                    windower.send_command('input /ws "' .. settings.ws2_name .. '" <t>')
                    sc_window = nil
                    return
                end
            end
            -- WS2 can't close the current resonance; give up and let WS1 fire below
            sc_window = nil
        else
            -- Waiting: window open but delay hasn't passed or TP not ready yet;
            -- don't fire WS1 while we still have a chance to close the chain
            if now < sc_window.expires then return end
        end
    end

    if new_tp >= settings.tp_threshold then
        execute_ws()
    end
end)

windower.register_event('zone change', function()
    pull_sent = false
    sc_window  = nil
    stop_return_home()
    if active then
        active = false
        windower.add_to_chat(8, 'MagianWS: Stopped — zone change detected.')
        update_display()
    end
end)



print_status()
update_display()
