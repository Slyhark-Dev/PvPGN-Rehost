--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--


-- Config table can be extended here with your own variables
-- values are preloaded from bnetd.conf
config = {
    -- Path to "var" directory (with slash at the end)
    -- Usage: config.vardir()
    vardir = function()
        return string.replace(config.statusdir, "status", "")
    end,
    
    -- Quiz settings
    quiz = true,
    quiz_filelist = "misc, dota, warcraft", -- display available files in "/quiz start"
    quiz_competitive_mode = true, -- top players loses half of points which last player received; at the end top of records loses half of points which players received in current game
    quiz_max_questions = 100, -- from start to end
    quiz_question_delay = 5, -- delay before send next question
    quiz_hint_delay = 20, -- delay between prompts
    quiz_users_in_top = 15, -- how many users display in TOP list
    quiz_channel = nil, -- (do not modify!) channel when quiz has started (it assigned with start)
    
    -- AntiHack (Starcraft)
    ah = true,
    ah_interval = 60, -- interval for send memory request to all players in games

}

-- ============================================================================
-- CONFIGURACION DEL SISTEMA REHOST / BOTS / MAPAS
-- Editar estos valores para personalizar el servidor
-- ============================================================================

-- BOT MANAGER
CONF_BOT_CHANNEL        = "The Void"       -- Canal donde esperan los bots libres
CONF_BOT_TRIGGER        = "."              -- Prefijo de comandos del bot, debe coincidir con Ghost One (. ! # etc)
CONF_BOT_LIST           = {                -- Lista de cuentas bot registradas
    "prueba74",
    "prueba75",
    "prueba76",
    "prueba77",
    "prueba78",
}
CONF_BOT_IMMUNITY_USERS = {                -- Usuarios con inmunidad flood adicionales
    "admin",
    "PvPGN-Realm",
    "PvPGN Realm",
    "SERVER",
    "LOCAL",
    "[PvPGN-Realm]",
    "admin [PvPGN-Realm]",
}
CONF_BOT_STUCK_CHECK_INTERVAL = 1   -- Segundos entre verificaciones de bots stuck (rejoin)

-- CFG MONITOR (sistema rehost)
CONF_CFG_DIRECTORY      = "C:\\PVPGN\\mapcfgs\\"   -- Carpeta donde llegan los .cfg
CONF_CFG_CHECK_INTERVAL = 3                          -- Segundos entre verificaciones
CONF_TIMEOUT_WAITING_CFG  = 10   -- Timeout esperando que llegue el .cfg
CONF_TIMEOUT_WAITING_EXIT = 30   -- Timeout para que el host salga del lobby
CONF_TIMEOUT_VALIDATION   = 15   -- Timeout para validar creacion de partida

-- DIRECTORIO DE MAPAS (usado por download_api y map_checker_api)
CONF_MAPS_DIRECTORY     = "C:\\xampp\\htdocs\\UPMAPS\\Maps\\"

-- SISTEMA DE DESCARGA DE MAPAS
CONF_DOWNLOAD_MAX_SIZE        = 100 * 1024 * 1024   -- 100 MB
CONF_DOWNLOAD_MAX_CONCURRENT  = 2
CONF_DOWNLOAD_EXTENSIONS      = { ".w3x", ".w3m" }
CONF_DOWNLOAD_DOMAINS         = {
    "epicwar.com", "www.epicwar.com",
    "hiveworkshop.com", "www.hiveworkshop.com",
    "moddb.com", "www.moddb.com",
}
CONF_DOWNLOAD_CLEANUP_ON_INIT = true   -- Limpia archivos temporales (.ps1, temp_url_*, temp_path_*, head_*) al iniciar

-- W3MMD SCORE SYSTEM
CONF_W3MMD_ENABLED      = true  -- true = sistema activo, false = sistema apagado
CONF_W3MMD_LOG_FILE     = "C:\\PVPGN\\main\\logs\\w3mmd_results.log"
CONF_W3MMD_EXP_WINNER   = 100   -- EXP por victoria
CONF_W3MMD_EXP_LOSER    = 25    -- EXP por derrota
CONF_W3MMD_EXP_PLAYED   = 15    -- EXP por participar

-- LOBBY TRACKER (sistema /slots para mostrar info de lobbies rehosteados)
CONF_LOBBY_OUTPUT_FILE      = "C:\\PVPGN\\main\\logs\\lobby_info.txt"
CONF_INSPECTOR_OUTPUT_FILE  = "C:\\PVPGN\\main\\logs\\game_inspect.txt"
CONF_LOBBY_THROTTLE_SECONDS = 3   -- Throttle del TXT en eventos automaticos

-- SISTEMA DE UPLOAD DE MAPAS (/upload)
-- FASE 3: CONF_MAP_UPLOAD_RESULTS_FILE eliminado. El resultado se consulta
-- via IPC (GET_UPLOAD_RESULT), ya no se escribe/lee upload_results.txt.
CONF_MAP_UPLOAD_MAX_CONCURRENT = 3      -- Maximo de uploads simultaneos permitidos (validacion rapida en Lua)
CONF_MAP_UPLOAD_OVERWRITE      = true   -- true = sobreescribe si el mapa ya existe, false = rechaza

-- DEBUG (activar/desactivar logs por modulo)
CONF_DEBUG_W3MMD        = true   -- muestra logs del sistema de EXP/puntos en consola
CONF_DEBUG_MAP_CHECKER  = false  -- muestra logs de verificacion de mapas en /rehost




