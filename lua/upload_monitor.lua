--[[
    UPLOAD MONITOR v2.0 (FASE 3)
    Sistema de monitoreo de resultados de upload de mapas (/upload)
    
    FUNCION: Consulta via IPC (GET_UPLOAD_RESULT) el resultado de cada upload
             en curso y notifica al host. Ya no depende de upload_results.txt.
    PATRON:  Igual que cfg_monitor (tick desde handle_server_mainloop)
]]--

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================
local UPLOAD_MONITOR = {
    last_check     = 0,
    check_interval = 3,
    timeout_exit   = 30,  -- segundos para salir del lobby tras upload exitoso
}

-- ============================================================================
-- FUNCIONES CORE
-- ============================================================================

-- Liberar hold de upload y decrementar contador
function release_upload_hold(hostName)
    if upload_holds and upload_holds[hostName] then
        upload_holds[hostName] = nil
        if upload_active_count and upload_active_count > 0 then
            upload_active_count = upload_active_count - 1
        end
    end
end

-- FASE 3: consulta via IPC (GET_UPLOAD_RESULT) el resultado de cada upload
-- en curso (status == "waiting_upload"), por su gameID propio. Reemplaza la
-- antigua lectura de upload_results.txt linea por linea.
local function process_upload_results()
    if not upload_holds then return end

    for hostName, holdData in pairs(upload_holds) do
        if holdData.status == "waiting_upload" and holdData.game_id_str then
            local r = api.ipc_get_upload_result(holdData.game_id_str)
            if r and r.found == "1" then
                local status  = r.status or ""
                local mapName = r.map_name or ""
                local detail  = r.detail or ""

                -- Si el host cancelo (salio durante descarga), solo confirmar mapa guardado
                if holdData.status == "cancelled" then
                    if status == "UPLOAD_OK" then
                        api.message_send_text(hostName, message_type_info, hostName,
                            "Mapa descargado correctamente: " .. mapName)
                    end
                    release_upload_hold(hostName)

                elseif status == "UPLOAD_OK" then
                    -- FASE 3: slots via IPC (MAP_INFO), no desde el resultado de upload
                    local slots = 0
                    local mi = api.ipc_get_map_info(hostName)
                    if mi and mi.found == "1" then
                        slots = tonumber(mi.slots_totales) or 0
                    else
                        api.message_send_text("DEBUG", message_type_error, nil,
                            "[UPLOAD] MAP_INFO no encontrado para " .. hostName .. " (mapa=" .. mapName .. ")")
                    end
                    -- Verificar bots disponibles
                    if bot_get_available_count() == 0 then
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Mapa descargado correctamente: " .. mapName ..
                            " pero no hay bots disponibles para rehost.")
                        release_upload_hold(hostName)
                    else
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Mapa descargado. Salga del lobby ahora. Tienes 30 segundos.")
                        upload_holds[hostName].status            = "map_received"
                        upload_holds[hostName].map_received_time = os.time()
                        upload_holds[hostName].map_name          = mapName
                        upload_holds[hostName].slots_totales     = slots
                    end

                elseif status == "UPLOAD_IDENTICAL" then
                    -- FASE 3: slots via IPC (MAP_INFO), no desde el resultado de upload
                    local slots = 0
                    local mi = api.ipc_get_map_info(hostName)
                    if mi and mi.found == "1" then
                        slots = tonumber(mi.slots_totales) or 0
                    else
                        api.message_send_text("DEBUG", message_type_error, nil,
                            "[UPLOAD] MAP_INFO no encontrado para " .. hostName .. " (mapa=" .. mapName .. ")")
                    end
                    if bot_get_available_count() == 0 then
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Mapa verificado: " .. mapName ..
                            " pero no hay bots disponibles para rehost.")
                        release_upload_hold(hostName)
                    else
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Mapa verificado. Salga del lobby ahora. Tienes 30 segundos.")
                        upload_holds[hostName].status            = "map_received"
                        upload_holds[hostName].map_received_time = os.time()
                        upload_holds[hostName].map_name          = mapName
                        upload_holds[hostName].slots_totales     = slots
                    end

                elseif status == "UPLOAD_FAIL" then
                    local reason = ""
                    if detail == "MAP_NOT_FOUND_IN_CLIENT" then
                        reason = "el cliente no tiene el mapa localmente."
                    elseif detail == "CLIENT_NOT_FOUND" then
                        reason = "no se encontro cliente disponible."
                    elseif detail == "WRITE_ERROR" then
                        reason = "error al guardar en el servidor."
                    elseif detail == "READ_ERROR" then
                        reason = "error de transferencia."
                    elseif detail == "TIMEOUT" then
                        reason = "tiempo de transferencia agotado."
                    elseif detail == "MAP_DIFFER_NO_OVERWRITE" then
                        reason = "el mapa existe pero es una version distinta. Use overwrite=true para reemplazarlo."
                    elseif detail == "HASH_ERROR" then
                        reason = "error al verificar integridad del mapa existente."
                    else
                        reason = detail
                    end
                    api.message_send_text(hostName, message_type_error, hostName,
                        "Error al subir mapa: " .. mapName .. ". Razon: " .. reason)
                    release_upload_hold(hostName)

                elseif status == "UPLOAD_BUSY" then
                    -- Detectar nuevo motivo QUEUE_TIMEOUT
                    if detail == "QUEUE_TIMEOUT" then
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Cola saturada. Tu orden espero demasiado y fue cancelada. Intente mas tarde.")
                    else
                        api.message_send_text(hostName, message_type_error, hostName,
                            "Servidor ocupado procesando otros uploads. Intente mas tarde.")
                    end
                    release_upload_hold(hostName)

                elseif status == "UPLOAD_EXISTS" then
                    api.message_send_text(hostName, message_type_info, hostName,
                        "El mapa ya existe en el servidor: " .. mapName)
                    release_upload_hold(hostName)
                end
            end
        end
    end
end

-- ============================================================================
-- TIMER Y AVISOS - igual que cfg_monitor
-- ============================================================================

local function check_timeout_warnings()
    if not upload_holds then return end
    local current_time = os.time()

    for hostName, holdData in pairs(upload_holds) do
        if holdData.status == "map_received" then
            local elapsed   = current_time - holdData.map_received_time
            local remaining = UPLOAD_MONITOR.timeout_exit - elapsed

            if remaining == 15 and not holdData.warned_15s then
                api.message_send_text(hostName, message_type_error, hostName,
                    "URGENTE! Quedan 15 segundos para salir del lobby.")
                holdData.warned_15s = true

            elseif remaining == 5 and not holdData.warned_5s then
                api.message_send_text(hostName, message_type_error, hostName,
                    "CRITICO! Quedan 5 segundos. Sal del lobby ahora!")
                holdData.warned_5s = true
            end
        end
    end
end

local function cleanup_expired_holds()
    if not upload_holds then return end
    local current_time = os.time()
    local expired = {}

    for hostName, holdData in pairs(upload_holds) do
        if holdData.status == "map_received" then
            local elapsed = current_time - holdData.map_received_time
            if elapsed > UPLOAD_MONITOR.timeout_exit then
                api.message_send_text(hostName, message_type_error, hostName,
                    "Tiempo para salir expirado. Rehost por upload cancelado.")
                table.insert(expired, hostName)
            end
        elseif holdData.status == "waiting_upload" then
            -- Timeout general si nunca llego el resultado
            local age = current_time - (holdData.timestamp or 0)
            if age > 180 then
                api.message_send_text(hostName, message_type_error, hostName,
                    "Upload cancelado por timeout. Intente nuevamente.")
                table.insert(expired, hostName)
            end
        end
    end

    for _, hostName in ipairs(expired) do
        release_upload_hold(hostName)
    end
end

-- ============================================================================
-- MANEJO DE SALIDA DEL HOST (llamado desde handle_game_destroy)
-- ============================================================================
function upload_handle_host_exit(hostName, gameId)
    if not upload_holds or not upload_holds[hostName] then return false end

    local holdData = upload_holds[hostName]

    -- Solo filtrar por game_id si se provee uno, nil = forzar limpieza
    if gameId and holdData.game_id and tostring(gameId) ~= tostring(holdData.game_id) then
        return false
    end

    -- Host salio durante descarga -> marcar cancelado, mapa llegara igual
    if holdData.status == "waiting_upload" then
        upload_holds[hostName].status = "cancelled"
        return true
    end

    -- Host salio del lobby tras recibir el mapa -> iniciar rehost con .map
    if holdData.status == "map_received" then
        local gameName = holdData.game_name
        local mapPath  = holdData.map_path
        local slots    = holdData.slots_totales or 0
        local assigned_bot = bot_assign_for_rehost(hostName)

        if assigned_bot then
            bot_send_map_rehost_commands(assigned_bot, hostName, gameName, mapPath)

            upload_holds[hostName] = {
                status          = "validating",
                bot_name        = assigned_bot,
                game_name       = gameName,
                map_path        = mapPath,
                validation_time = os.time() + 2,
                timestamp       = os.time(),
                game_id_str     = holdData.game_id_str,
                slots_totales   = slots,
            }
        else
            api.message_send_text(hostName, message_type_error, hostName,
                "Error: No hay bots disponibles en este momento.")
            release_upload_hold(hostName)
        end

        return true
    end

    return false
end

-- Validar que la partida fue creada correctamente
local function validate_game_creation()
    if not upload_holds then return end
    local current_time = os.time()

    for hostName, holdData in pairs(upload_holds) do
        if holdData.status == "validating" and holdData.validation_time 
           and current_time >= holdData.validation_time then

            local game = api.game_get_by_name(holdData.game_name, CLIENTTAG_WAR3XP, game_type_all)

            if next(game) then
                api.message_send_text(hostName, message_type_info, hostName,
                    "Rehost ejecutado con exito. Bot " .. holdData.bot_name .. " recreo la partida.")
                upload_holds[hostName].status    = "game_active"
                upload_holds[hostName].game_name = holdData.game_name
                upload_holds[hostName].bot_name  = holdData.bot_name
                -- Guardar el id del lobby recreado en el propio hold. Permite
                -- identificarlo despues sin depender de comparar nombres. Se
                -- setea aqui y no solo dentro de lobby_track_create porque esa
                -- funcion aborta si slots_totales no es valido.
                upload_holds[hostName].new_game_id = tonumber(game.id)
                -- FIX SLOTS: pasar slots_totales para que no se intente leer .cfg
                lobby_track_create(game.id, hostName, holdData.bot_name, holdData.game_name, holdData.slots_totales)
            else
                api.message_send_text(hostName, message_type_error, hostName,
                    "Partida cancelada, el mapa tiene un error de sistema.")
                release_upload_hold(hostName)
            end
        end
    end
end

-- ============================================================================
-- TICK - LLAMADO DESDE handle_server_mainloop
-- ============================================================================
function upload_monitor_tick()
    local current_time = os.time()
    if current_time - UPLOAD_MONITOR.last_check >= UPLOAD_MONITOR.check_interval then
        UPLOAD_MONITOR.last_check = current_time

        if upload_holds and next(upload_holds) then
            process_upload_results()
            check_timeout_warnings()
            cleanup_expired_holds()
            validate_game_creation()
        end
    end
end

-- ============================================================================
-- INICIALIZACION
-- ============================================================================
-- FASE 3: ya no usa upload_results.txt (CONF_MAP_UPLOAD_RESULTS_FILE
-- eliminado). El resultado se consulta via IPC (GET_UPLOAD_RESULT).
function upload_monitor_init()
    UPLOAD_MONITOR.check_interval = CONF_CFG_CHECK_INTERVAL
    UPLOAD_MONITOR.last_check     = 0
    UPLOAD_MONITOR.timeout_exit   = 30

    print("[UPLOAD-MONITOR] Sistema iniciado (IPC directo, sin upload_results.txt)")
end
