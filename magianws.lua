-- Copyright 2026 renzler
-- Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
-- 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

local ws_name = 'Piercing Arrow'
local tp_threshold = 1000

windower.register_event('addon command', function(cmd, ...)
    if cmd == 'ws' then
        ws_name = table.concat({...}, ' ')
        windower.add_to_chat(8, 'MagianWS: Weaponskill set to "' .. ws_name .. '"')
    elseif cmd == 'tp' then
        local val = tonumber((...))
        if val then
            tp_threshold = val
            windower.add_to_chat(8, 'MagianWS: TP threshold set to ' .. tp_threshold)
        else
            windower.add_to_chat(8, 'MagianWS: Invalid TP value.')
        end
    elseif cmd == 'status' then
        windower.add_to_chat(8, 'MagianWS: Weaponskill: "' .. ws_name .. '" | TP threshold: ' .. tp_threshold)
    end
end)

windower.register_event('tp change', function(new_tp, old_tp)
    local player = windower.ffxi.get_player()
    if new_tp >= tp_threshold and player.status == 1 then
        windower.send_command('input /ws "' .. ws_name .. '" <t>')
    end
end)