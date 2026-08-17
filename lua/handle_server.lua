--[[
    Copyright (C) 2014 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--

function handle_server_mainloop()
    -- Tick all timers
    for t in pairs(__timers) do
        __timers[t]:tick()
    end
    
    -- MONITOR CFG
    cfg_monitor_tick()
    
    -- VERIFICAR BOTS STUCK (rejoin cada 5s)
    bot_check_stuck_assignments()
    
    -- W3MMD SCORE PROCESSOR
    w3mmd_score_mainloop()

    -- MONITOR UPLOAD DE MAPAS
    upload_monitor_tick()
    
    -- DEBUG(os.time())
end

-- When restart Lua VM
function handle_server_rehash()

    -- LIMPIAR HOLDS AL REINICIAR LUA
    if rehost_holds then
        rehost_holds = {}
        -- DEBUG("[CFG-MONITOR] Holds limpiados por rehash")
    end

    -- LIMPIAR HOLDS DE UPLOAD AL REINICIAR LUA
    if upload_holds then
        upload_holds = {}
        upload_active_count = 0
    end
end
