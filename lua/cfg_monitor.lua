--[[
    Monitor de archivos .cfg para sistema /rehost
    Se integra con handle_server_mainloop()
]]--

-- ============================================================================
-- TABLA DE ESTADO (sin valores aun - se llenan en cfg_monitor_init)
-- ============================================================================
local CFG_MONITOR = {
    last_check = 0,
}

-- ============================================================================
-- FUNCIONES DE ARCHIVOS
-- ============================================================================
function cfg_file_exists(filepath)
    local file = io.open(filepath, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- ============================================================================
-- FUNCIONES PRINCIPALES
-- ============================================================================
function cfg_monitor_init()
    -- Aqui se leen las CONF_* porque main() (que llama a cfg_monitor_init)
    -- corre DESPUES de que todos los archivos lua estan cargados,
    -- incluyendo config.lua
    CFG_MONITOR.last_check           = 0
    CFG_MONITOR.check_interval       = CONF_CFG_CHECK_INTERVAL
    CFG_MONITOR.cfg_directory        = CONF_CFG_DIRECTORY
    CFG_MONITOR.timeout_waiting_cfg  = CONF_TIMEOUT_WAITING_CFG
    CFG_MONITOR.timeout_waiting_exit = CONF_TIMEOUT_WAITING_EXIT
    CFG_MONITOR.timeout_validation   = CONF_TIMEOUT_VALIDATION
end

function cfg_check_for_new_files()
    if not next(rehost_holds) then
        return
    end
    
    for hostname, hold_data in pairs(rehost_holds) do
        if hold_data.status == "waiting_cfg" then
            local cfg_file = CFG_MONITOR.cfg_directory .. hostname .. ".cfg"
            
            if cfg_file_exists(cfg_file) then
                rehost_holds[hostname].status            = "cfg_received"
                rehost_holds[hostname].cfg_received_time = os.time()
                
                api.message_send_text(hostname, message_type_error, hostname, 
                    "Mapa procesado. Salga del lobby ahora. Tienes 30 segundos.")
                    
                local account = api.account_get_by_name(hostname)
                if account and next(account) then
                    map_checker_on_rehost(account)
                end
            end
        end
    end
end

function cfg_check_timeout_warnings()
    local current_time = os.time()
    
    for hostname, hold_data in pairs(rehost_holds) do
        if hold_data.status == "cfg_received" then
            local time_elapsed   = current_time - hold_data.cfg_received_time
            local time_remaining = CFG_MONITOR.timeout_waiting_exit - time_elapsed
            
            if time_remaining == 15 and not hold_data.warned_15s then
                api.message_send_text(hostname, message_type_error, hostname, 
                    "URGENTE! Quedan 15 segundos para salir del lobby.")
                hold_data.warned_15s = true
                
            elseif time_remaining == 5 and not hold_data.warned_5s then
                api.message_send_text(hostname, message_type_error, hostname, 
                    "CRITICO! Quedan 5 segundos. Sal del lobby ahora!")
                hold_data.warned_5s = true
            end
        end
    end
end

function cfg_cleanup_expired_holds()
    local current_time = os.time()
    local expired_hosts = {}
    
    for hostname, hold_data in pairs(rehost_holds) do
        local age = current_time - hold_data.timestamp
        local timeout, reason
        
        if hold_data.status == "waiting_cfg" then
            timeout = CFG_MONITOR.timeout_waiting_cfg
            reason  = "No se proceso el mapa en el tiempo esperado. Rehost cancelado."
        elseif hold_data.status == "cfg_received" then
            timeout = CFG_MONITOR.timeout_waiting_exit
            reason  = "Tiempo para salir expirado. Rehost cancelado."
        elseif hold_data.status == "validating" then
            timeout = CFG_MONITOR.timeout_validation
            reason  = "Validacion expirada. Rehost cancelado."
        end
        
        if timeout and age > timeout then
            api.message_send_text(hostname, message_type_error, hostname, reason)
            table.insert(expired_hosts, hostname)
        end
    end
    
    for _, hostname in pairs(expired_hosts) do
        rehost_holds[hostname] = nil
    end
end

-- ============================================================================
-- VALIDACION DE CREACION DE PARTIDA
-- ============================================================================
function cfg_validate_game_creation()
    local current_time = os.time()
    
    for hostname, hold_data in pairs(rehost_holds) do
        if hold_data.status == "validating" and hold_data.validation_time and current_time >= hold_data.validation_time then
            local game = api.game_get_by_name(hold_data.game_name, CLIENTTAG_WAR3XP, game_type_all)
            
            if next(game) then
                api.message_send_text(hostname, message_type_info, hostname, 
                    --"Rehost ejecutado con exito. Bot " .. hold_data.bot_name .. " recreo la partida.")
                    "Rehost ejecutado con exito.")
                rehost_holds[hostname].status    = "game_active"
                rehost_holds[hostname].game_name = hold_data.game_name
                rehost_holds[hostname].bot_name  = hold_data.bot_name
                -- Guardar el id del lobby recreado en el propio hold. Permite
                -- identificarlo despues sin depender de comparar nombres. Se
                -- setea aqui y no solo dentro de lobby_track_create porque esa
                -- funcion aborta si slots_totales no es valido.
                rehost_holds[hostname].new_game_id = tonumber(game.id)

                -- FASE 3: slots via IPC (MAP_INFO), enviado por el MapClient
                -- junto con el .cfg. Ya no se lee el .cfg de disco para esto.
                local slots_totales = 0
                local mi = api.ipc_get_map_info(hostname)
                if mi and mi.found == "1" then
                    slots_totales = tonumber(mi.slots_totales) or 0
                else
                    api.message_send_text("DEBUG", message_type_error, nil,
                        "[REHOST] MAP_INFO no encontrado para " .. hostname)
                end

                lobby_track_create(game.id, hostname, hold_data.bot_name, hold_data.game_name, slots_totales)
                bot_game_register(game.id, hold_data.bot_name, hostname, hold_data.game_name)
            else
                api.message_send_text(hostname, message_type_error, hostname, 
                    "Partida cancelada, el mapa tiene un error de sistema.")
                rehost_holds[hostname] = nil
            end
        end
    end
end

-- ============================================================================
-- FUNCION PRINCIPAL PARA MAINLOOP
-- ============================================================================
function cfg_monitor_tick()
    -- Proteccion: si init no se ejecuto aun, salir silenciosamente
    if not CFG_MONITOR.check_interval then return end
    
    local current_time = os.time()
    
    if current_time - CFG_MONITOR.last_check >= CFG_MONITOR.check_interval then
        CFG_MONITOR.last_check = current_time
        
        if next(rehost_holds) then
            cfg_check_for_new_files()
            cfg_check_timeout_warnings()
            cfg_cleanup_expired_holds()
            cfg_validate_game_creation()
        end
    end
end

-- ============================================================================
-- MANEJO DE SALIDA DE HOST
-- ============================================================================
function cfg_handle_host_exit(hostname)
    local hold_data = rehost_holds[hostname]
    if not hold_data then
        return false
    end
    
    if hold_data.status == "cfg_received" then
        local game_name    = hold_data.game_name
        local assigned_bot = bot_assign_for_rehost(hostname)
        
        if assigned_bot then
            bot_send_rehost_commands(assigned_bot, hostname, game_name)
            
            rehost_holds[hostname] = {
                status          = "validating",
                bot_name        = assigned_bot,
                game_name       = game_name,
                validation_time = os.time() + 2,
                timestamp       = os.time()
            }
        else
            api.message_send_text(hostname, message_type_error, hostname, 
                "Error: No hay bots disponibles en este momento.")
            rehost_holds[hostname] = nil
        end
        
        return true
        
    elseif hold_data.status == "waiting_cfg" then
        api.message_send_text(hostname, message_type_error, hostname, 
            "Rehost cancelado: No se proceso el mapa antes de salir.")
        rehost_holds[hostname] = nil
        return true
    end
    
    return false
end
