--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--

-- Entry point
-- Executes after preload all the lua files
function main()
    
    if (config.ah) then
        -- start antihack
        ah_init()
    end
    
    -- INICIALIZAR MONITOR CFG
    cfg_monitor_init()
    
    -- INICIALIZAR BOT MANAGER
    bot_manager_init()
    
    -- INICIALIZAR API DE DESCARGA
    download_api_init()
    
    -- INICIALIZAR W3MMD SCORE SYSTEM
    w3mmd_score_init()
    
    -- INICIALIZAR CHECK MAP WITH REHOST
    map_checker_init()
    
    -- INICIALIZAR LOBBY TRACKER (/slots)
    lobby_tracker_init()

    -- INICIALIZAR MONITOR DE UPLOAD DE MAPAS
    upload_monitor_init()
end
