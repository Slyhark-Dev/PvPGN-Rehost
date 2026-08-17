--[[
    Connection interface between PvPGN and GHost
    https://github.com/OHSystem/ohsystem/issues/279

    
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--

------------------------------
--- CONFIGURACION
--- Las rutas se leen dinamicamente desde config.lua (CONF_*)
--- dentro de cada funcion para garantizar que ya esten cargadas.
------------------------------

------------------------------
--- USER -> PVPGN -> GHOST ---
------------------------------

-- /unhost
function command_unhost(account, text)
    if not account.clienttag == CLIENTTAG_WAR3XP then 
        return 1 
    end

    local bot_name, message = bot_send_unhost_command(account.name)
    
    if bot_name then
        api.message_send_text(account.name, message_type_info, account.name, message)
    else
        api.message_send_text(account.name, message_type_error, account.name, message)
    end
    
    return 0
end

-- /start
function command_start(account, text)
    if not account.clienttag == CLIENTTAG_WAR3XP then
        return 1
    end
 
    local hold_data = rehost_holds[account.name]
    if not hold_data then return -1 end
    if hold_data.status ~= "game_active" then return -1 end
    if not account.game_id then return -1 end
    if tonumber(account.game_id) ~= tonumber(hold_data.new_game_id) then return -1 end
 
    local assigned_bot = hold_data.bot_name
    if not assigned_bot then return -1 end
 
    local start_command = CONF_BOT_TRIGGER .. "start"
    api.message_send_text(assigned_bot, message_type_whisper, nil, start_command)
 
    api.message_send_text(account.name, message_type_info, account.name, "Iniciando partida...")
    return 0
end

-- hold
if not rehost_holds then
    rehost_holds = {}
end

-- Estado de uploads activos (contador en memoria, se reinicia con el servidor)
if not upload_active_count then
    upload_active_count = 0
end

-- Tabla para rastrear uploads en curso por usuario
if not upload_holds then
    upload_holds = {}
end

-- FASE 3: La validacion ya no lee server_status.txt. El MapServer ya conoce
-- el username via SET_USERNAME (lo asocia PvPGN al loguearse). Esta funcion
-- solo confirma que el MapClient de ese username esta activo.
function verify_user_ip_in_server_status(account)
    local r = api.ipc_check_username(account.name)
    return r and r.found == "1"
end

-- /rehost
function command_rehost(account, text)
    if not verify_user_ip_in_server_status(account) then
        api.message_send_text(account.name, message_type_error, account.name, 
            "El jugador no esta usando el loadder correcto, descargarlo: https://sinpagina.pe/")
        return -1
    end
    
    if not account.game_id then
        api.message_send_text(account.name, message_type_error, account.name, "Debes estar en una partida")
        return -1
    end
    
    local game = api.game_get_by_id(account.game_id)
    if not next(game) then
        api.message_send_text(account.name, message_type_error, account.name, "Error obteniendo info del juego")
        return -1
    end
    
    if game.owner ~= account.name then
        api.message_send_text(account.name, message_type_error, account.name, "No tienes permitido usar este comando.")
        return -1
    end
  
    if bot_get_available_count() == 0 then
        api.message_send_text(account.name, message_type_error, account.name, "No hay bots disponibles para rehost en este momento.")
        return -1
    end

    if rehost_holds[account.name] then
        api.message_send_text(account.name, message_type_error, account.name, "Ya hay un rehost en curso, espere a que termine.")
        return -1
    end
    
    local mapPath = game.mappath or game.mapname or "unknown.w3x"
    if string.find(mapPath, "^maps/") then
        mapPath = string.sub(mapPath, 6)
    end
    
    local gameID   = string.format("%03d", game.id or 1)
    local gameName = game.name or "Rehost"
    
    -- FASE 3: orden enviada directo via IPC (username = game.owner = account.name)
    local r = api.ipc_send_order(account.name, mapPath, gameID, gameName)
    
    if r and r.ok == "1" then
        rehost_holds[account.name] = {
            timestamp  = os.time(),
            game_id    = account.game_id,
            game_name  = gameName,
            status     = "waiting_cfg"
        }
        
        api.message_send_text(account.name, message_type_info, account.name, "Rehost activado, espere que se procese el mapa.")
    else
        local reason = (r and r.error) or "ERROR_DESCONOCIDO"
        if reason == "CLIENT_NOT_FOUND" then
            api.message_send_text(account.name, message_type_error, account.name, 
                "El jugador no esta usando el loadder correcto, descargarlo: https://sinpagina.pe/")
        else
            api.message_send_text(account.name, message_type_error, account.name, "Error enviando orden de rehost.")
        end
    end
    
    return 0
end

-- /upload
function command_upload(account, text)
    local max_concurrent = CONF_MAP_UPLOAD_MAX_CONCURRENT

    -- Verificar que usa el loader correcto
    if not verify_user_ip_in_server_status(account) then
        api.message_send_text(account.name, message_type_error, account.name,
            "El jugador no esta usando el loader correcto, descargarlo: https://sinpagina.pe/")
        return -1
    end

    -- Verificar que esta en una partida
    if not account.game_id then
        api.message_send_text(account.name, message_type_error, account.name, "Debes estar en una partida para usar este comando.")
        return -1
    end

    local game = api.game_get_by_id(account.game_id)
    if not next(game) then
        api.message_send_text(account.name, message_type_error, account.name, "Error obteniendo info del juego.")
        return -1
    end

    -- Verificar que es el owner de la partida
    if game.owner ~= account.name then
        api.message_send_text(account.name, message_type_error, account.name, "No tienes permitido usar este comando.")
        return -1
    end

    -- Verificar que no tiene un upload ya en curso
    if upload_holds[account.name] then
        api.message_send_text(account.name, message_type_error, account.name, "Ya tienes un upload en curso, espere a que termine.")
        return -1
    end

    -- Verificar limite de uploads simultaneos
    if upload_active_count >= max_concurrent then
        api.message_send_text(account.name, message_type_error, account.name,
            "Hay " .. upload_active_count .. " uploads en curso. Intente mas tarde.")
        return -1
    end

    -- Obtener datos del mapa
    local mapPath = game.mappath or game.mapname or "unknown.w3x"
    if string.find(mapPath, "^maps/") then
        mapPath = string.sub(mapPath, 6)
    end

    -- Extraer solo el nombre del archivo del path
    local mapName = string.match(mapPath, "[^\\/]+$") or mapPath

    local gameID = string.format("%03d", game.id or 1)

    -- FASE 3: orden enviada directo via IPC (username = game.owner = account.name)
    local r = api.ipc_send_upload(account.name, mapPath, gameID)

    if r and r.ok == "1" then
        -- Registrar upload en curso
        upload_active_count = upload_active_count + 1
        upload_holds[account.name] = {
            timestamp   = os.time(),
            game_id     = account.game_id,
            map_name    = mapName,
            map_path    = mapPath,
            game_name   = game.name or "Rehost",
            game_id_str = gameID,
            status      = "waiting_upload",
        }

        api.message_send_text(account.name, message_type_info, account.name,
            "Upload iniciado para: " .. mapName .. ". Espere...")
    else
        local reason = (r and r.error) or "ERROR_DESCONOCIDO"
        if reason == "CLIENT_NOT_FOUND" then
            api.message_send_text(account.name, message_type_error, account.name,
                "El jugador no esta usando el loader correcto, descargarlo: https://sinpagina.pe/")
        elseif reason == "UPLOAD_BUSY" then
            api.message_send_text(account.name, message_type_error, account.name,
                "El servidor esta saturado de uploads. Intente mas tarde.")
        else
            api.message_send_text(account.name, message_type_error, account.name, "Error enviando orden de upload.")
        end
    end

    return 0
end
