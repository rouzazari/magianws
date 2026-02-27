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
local res = require('resources')

local defaults = {}
defaults.ws_name = 'Piercing Arrow'
defaults.tp_threshold = 1000
defaults.food_name = ''
defaults.ammo_name = ''

local settings = config.load(defaults)

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

local function print_status()
    windower.add_to_chat(8, 'MagianWS: Weaponskill: "' .. settings.ws_name .. '" | TP threshold: ' .. settings.tp_threshold .. ' | Food: ' .. (settings.food_name ~= '' and settings.food_name or 'off') .. ' | Ammo: ' .. (settings.ammo_name ~= '' and settings.ammo_name or 'off'))
end

local function try_eat_food_if_engaged()
    local player = windower.ffxi.get_player()
    if player.status == 1 then
        try_eat_food()
    end
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
    elseif cmd == 'status' then
        print_status()
    end
end)

windower.register_event('status change', function(new_status)
    if new_status == 1 then
        try_eat_food()
    end
end)

windower.register_event('lose buff', function(buff_id)
    if buff_id == 251 then
        try_eat_food()
    end
end)

windower.register_event('tp change', function(new_tp, old_tp)
    local player = windower.ffxi.get_player()
    if new_tp >= settings.tp_threshold and player.status == 1 then
        try_equip_ammo()
        windower.send_command('input /ws "' .. settings.ws_name .. '" <t>')
    end
end)

print_status()
try_equip_ammo()
try_eat_food_if_engaged()
