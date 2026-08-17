-- ============================================================================
-- ADMINISTRADOR DE BOTS PARA REHOST + FLOOD IMMUNITY
-- ============================================================================

-- Tabla declarada vacia. Se llena en bot_manager_init() para que las
-- variables CONF_* de config.lua ya esten disponibles cuando se lean.
BOT_MANAGER = {
    available_bots    = {},
    assigned_bots     = {},
    last_stuck_check  = 0,
    stuck_check_interval = 1,
}

-- ============================================================================
-- FLOOD IMMUNITY FUNCTIONS
-- ============================================================================

function bot_manager_update_immunity()
    local full_immunity_list = {}
    
    for _, user in pairs(BOT_MANAGER.system_immunity_users) do
        table.insert(full_immunity_list, user)
    end
    
    for _, bot in pairs(BOT_MANAGER.bot_list) do
        table.insert(full_immunity_list, bot)
    end
    
    return #full_immunity_list
end

function bot_manager_add_immunity(username)
    if not username or username == "" then return false end
    
    for _, existing in pairs(BOT_MANAGER.system_immunity_users) do
        if existing == username then
            return false
        end
    end
    
    table.insert(BOT_MANAGER.system_immunity_users, username)
    bot_manager_update_immunity()
    
    return true
end

function bot_manager_remove_immunity(username)
    for i, existing in pairs(BOT_MANAGER.system_immunity_users) do
        if existing == username then
            if username == "admin" or username == "PvPGN-Realm" then
                return false
            end
            
            table.remove(BOT_MANAGER.system_immunity_users, i)
            bot_manager_update_immunity()
            
            return true
        end
    end
    return false
end

-- ============================================================================
-- FUNCIONES PRINCIPALES
-- ============================================================================

function bot_manager_init()
    -- Aqui se leen las CONF_* porque main() (que llama a bot_manager_init)
    -- corre DESPUES de que todos los archivos lua estan cargados,
    -- incluyendo config.lua
    BOT_MANAGER.target_channel        = CONF_BOT_CHANNEL
    BOT_MANAGER.command_trigger       = CONF_BOT_TRIGGER
    BOT_MANAGER.bot_list              = CONF_BOT_LIST
    BOT_MANAGER.system_immunity_users = CONF_BOT_IMMUNITY_USERS
    BOT_MANAGER.available_bots        = {}
    BOT_MANAGER.assigned_bots         = {}
    BOT_MANAGER.last_stuck_check      = 0
    BOT_MANAGER.stuck_check_interval  = CONF_BOT_STUCK_CHECK_INTERVAL or 1
    
    bot_manager_update_immunity()
end

function bot_manager_tick()
    -- Funcion vacia - la logica usa eventos de canal en tiempo real
end

-- ============================================================================
-- FUNCIONES DE ACCESO (para handle_channel.lua)
-- ============================================================================

function bot_get_target_channel()
    return BOT_MANAGER.target_channel
end

function bot_get_bot_list()
    return BOT_MANAGER.bot_list
end

function bot_add_to_available(bot_name)
    if BOT_MANAGER.assigned_bots[bot_name] then
        return false
    end
    
    for i, existing_bot in pairs(BOT_MANAGER.available_bots) do
        if existing_bot == bot_name then
            return false
        end
    end
    
    table.insert(BOT_MANAGER.available_bots, bot_name)
    return true
end

function bot_remove_from_available(bot_name)
    for i, available_bot in pairs(BOT_MANAGER.available_bots) do
        if available_bot == bot_name then
            table.remove(BOT_MANAGER.available_bots, i)
            return true
        end
    end
    return false
end

function bot_handle_channel_exit(bot_name)
    if BOT_MANAGER.assigned_bots[bot_name] then
        if BOT_MANAGER.assigned_bots[bot_name].status == "waiting_rejoin" then
            BOT_MANAGER.assigned_bots[bot_name].status = "working"
        end
    end
end

function bot_handle_channel_return(bot_name)
    if BOT_MANAGER.assigned_bots[bot_name] then
        BOT_MANAGER.assigned_bots[bot_name] = nil
        return true
    end
    return false
end

-- ============================================================================
-- FUNCIONES DE ASIGNACION
-- ============================================================================

function bot_assign_for_rehost(hostname)
    if #BOT_MANAGER.available_bots == 0 then
        return nil
    end
    
    -- Priorizar bots que ya tienen partidas activas
    for i, bot_name in ipairs(BOT_MANAGER.available_bots) do
        if bot_game_count(bot_name) > 0 then
            table.remove(BOT_MANAGER.available_bots, i)
            INFO("[BOT-ASSIGN] Priorizado bot con partidas activas: " .. bot_name .. " (" .. bot_game_count(bot_name) .. " en curso)")
            return bot_name
        end
    end
    
    -- Si ninguno tiene partidas activas, tomar el primero (comportamiento original)
    local assigned_bot = table.remove(BOT_MANAGER.available_bots, 1)
    return assigned_bot
end

-- ============================================================================
-- FUNCIONES DE COMANDOS (CON DELAYS)
-- ============================================================================

function bot_send_rehost_commands(bot_name, hostname, game_name)
    if not bot_name then
        return false
    end
    
    local load_command  = BOT_MANAGER.command_trigger .. "load " .. hostname .. ".cfg"
    local pubby_command = BOT_MANAGER.command_trigger .. "pubby " .. hostname .. " " .. game_name
    
    api.message_send_text(bot_name, message_type_whisper, nil, load_command)
    
    BOT_MANAGER.assigned_bots[bot_name] = {
        hostname    = hostname,
        game_name   = game_name,
        status      = "sending_pubby",
        pubby_time  = os.time() + 1,
        rejoin_time = os.time() + 4
    }
    
    return true
end

-- Igual que bot_send_rehost_commands pero usa .map en vez de .load
-- mapPath ejemplo: Maps\Download\Orc_Gladiators.w3x
function bot_send_map_rehost_commands(bot_name, hostname, game_name, map_path)
    if not bot_name then
        return false
    end

    -- Extraer solo el nombre del archivo sin ruta
    local map_name = map_path:match("[^\\/]+$") or map_path

    local map_command   = BOT_MANAGER.command_trigger .. "map " .. map_name
    local pubby_command = BOT_MANAGER.command_trigger .. "pubby " .. hostname .. " " .. game_name

    api.message_send_text(bot_name, message_type_whisper, nil, map_command)

    BOT_MANAGER.assigned_bots[bot_name] = {
        hostname    = hostname,
        game_name   = game_name,
        status      = "sending_pubby",
        pubby_time  = os.time() + 1,
        rejoin_time = os.time() + 4
    }

    return true
end

function bot_send_unhost_command(hostname)
    local assigned_bot = nil
    local cleanup_hold = false
    
    if rehost_holds[hostname] then
        if rehost_holds[hostname].bot_name then
            assigned_bot = rehost_holds[hostname].bot_name
            cleanup_hold = true
        end
    end
    
    if not assigned_bot then
        for bot_name, assignment_data in pairs(BOT_MANAGER.assigned_bots) do
            if assignment_data.hostname == hostname then
                assigned_bot = bot_name
                break
            end
        end
    end
    
    if not assigned_bot then
        return nil, "No tienes ninguna partida con bots activa."
    end
    
    local unhost_command = BOT_MANAGER.command_trigger .. "unhost"
    api.message_send_text(assigned_bot, message_type_whisper, nil, unhost_command)
    
    if cleanup_hold then
        local cfg_file = CONF_CFG_DIRECTORY .. hostname .. ".cfg"
        if file_exists(cfg_file) then
            os.remove(cfg_file)
        end
        rehost_holds[hostname] = nil
    end
    
    if BOT_MANAGER.assigned_bots[assigned_bot] then
        BOT_MANAGER.assigned_bots[assigned_bot] = nil
    end
    
    return assigned_bot, "Partida liberada con exito, enviado al bot " .. assigned_bot
end

-- ============================================================================
-- VERIFICACION Y LIMPIEZA
-- ============================================================================

function bot_check_stuck_assignments()
    local current_time = os.time()
    
    -- Throttle: solo correr cada CONF_BOT_STUCK_CHECK_INTERVAL segundos
    if current_time - BOT_MANAGER.last_stuck_check < BOT_MANAGER.stuck_check_interval then
        return
    end
    BOT_MANAGER.last_stuck_check = current_time
    
    -- Salida rapida si no hay bots asignados
    if not next(BOT_MANAGER.assigned_bots) then
        return
    end
    
    for bot_name, assignment_data in pairs(BOT_MANAGER.assigned_bots) do
        
        if assignment_data.status == "sending_pubby" then
            if current_time >= assignment_data.pubby_time then
                local pubby_command = BOT_MANAGER.command_trigger .. "pubby " .. assignment_data.hostname .. " " .. assignment_data.game_name
                api.message_send_text(bot_name, message_type_whisper, nil, pubby_command)
                
                assignment_data.status = "waiting_rejoin"
            end
        end
        
        if assignment_data.status == "waiting_rejoin" then
            if current_time >= assignment_data.rejoin_time then
                api.message_send_text(bot_name, message_type_whisper, nil, BOT_MANAGER.command_trigger .. "say /rejoin")
                
                assignment_data.status       = "rejoin_sent"
                assignment_data.cleanup_time = current_time + 30
            end
        end
        
        if assignment_data.status == "rejoin_sent" then
            if current_time >= assignment_data.cleanup_time then
                BOT_MANAGER.assigned_bots[bot_name] = nil
                
                local bot_account = api.account_get_by_name(bot_name)
                if bot_account and bot_account.channel_name == BOT_MANAGER.target_channel then
                    bot_add_to_available(bot_name)
                end
            end
        end
    end
end

-- ============================================================================
-- COMANDOS DE ADMINISTRACION
-- ============================================================================

function command_botimmunity(account, text)
    local args     = split_command(text, 2)
    local action   = args[1]
    local username = args[2]
    
    if not action then
        local immunity_list = {}
        for _, user in pairs(BOT_MANAGER.system_immunity_users) do
            table.insert(immunity_list, user)
        end
        for _, bot in pairs(BOT_MANAGER.bot_list) do
            table.insert(immunity_list, bot)
        end
        
        api.message_send_text(account.name, message_type_info, nil, 
            "Usuarios con inmunidad flood (" .. #immunity_list .. "):")
        api.message_send_text(account.name, message_type_info, nil, 
            table.concat(immunity_list, ", "))
        api.message_send_text(account.name, message_type_info, nil, 
            "Uso: /botimmunity [add|remove|refresh] [username]")
        return -1
    end
    
    if action == "add" and username then
        if bot_manager_add_immunity(username) then
            api.message_send_text(account.name, message_type_info, nil, 
                "Usuario agregado a inmunidad: " .. username)
        else
            api.message_send_text(account.name, message_type_error, nil, 
                "Error al agregar usuario: " .. username)
        end
        
    elseif action == "remove" and username then
        if bot_manager_remove_immunity(username) then
            api.message_send_text(account.name, message_type_info, nil, 
                "Usuario removido de inmunidad: " .. username)
        else
            api.message_send_text(account.name, message_type_error, nil, 
                "Error al remover usuario: " .. username)
        end
        
    elseif action == "refresh" then
        local count = bot_manager_update_immunity()
        api.message_send_text(account.name, message_type_info, nil, 
            "Inmunidad actualizada para " .. count .. " usuarios")
    else
        api.message_send_text(account.name, message_type_error, nil, 
            "Uso: /botimmunity [add|remove|refresh] [username]")
    end
    
    return -1
end

-- ============================================================================
-- DEBUG / STATUS
-- ============================================================================

function bot_show_status()
    local assigned_count = 0
    for _ in pairs(BOT_MANAGER.assigned_bots) do
        assigned_count = assigned_count + 1
    end
end

function bot_get_available_count()
    return #BOT_MANAGER.available_bots
end

-- ============================================================================
-- VERIFICACION Y COMUNICACION CON BOTS
-- ============================================================================

function bot_is_authorized(username)
    if not BOT_MANAGER.bot_list then return false end
    for _, bot_name in pairs(BOT_MANAGER.bot_list) do
        if string.lower(bot_name) == string.lower(username) then 
            return true 
        end
    end
    return false
end

function bot_message_send(botname, text)
    api.message_send_text(botname, message_type_whisper, nil, text)
end

function bot_is_online(botname)
    local botacc = api.account_get_by_name(botname)
    return botacc and botacc.online == "true"
end

function bot_get_online_list()
    local online_bots = {}
    for _, bot_name in pairs(BOT_MANAGER.bot_list) do
        if bot_is_online(bot_name) then
            table.insert(online_bots, bot_name)
        end
    end
    return online_bots
end

-- ============================================================================
-- FUNCIONES DE UTILIDAD
-- ============================================================================

function bot_is_game_owner(account)
    if not account.game_id then 
        return false 
    end

    local game = api.game_get_by_id(account.game_id)
    if not next(game) then 
        return false 
    end
    
    return bot_is_authorized(game.owner)
end

function bot_find_assigned(username)
    if rehost_holds[username] and rehost_holds[username].bot_name then
        return rehost_holds[username].bot_name
    end
    
    for bot_name, assignment_data in pairs(BOT_MANAGER.assigned_bots) do
        if assignment_data.hostname == username then
            return bot_name
        end
    end
    
    return nil
end

-- ============================================================================
-- MANEJO DE EVENTOS DE USUARIOS Y JUEGOS
-- ============================================================================

function bot_handle_user_login(account)
    if bot_is_authorized(account.name) then
        local bot_account = api.account_get_by_name(account.name)
        if bot_account and bot_account.channel_name == BOT_MANAGER.target_channel then
            bot_add_to_available(account.name)
        end
    end
end

function bot_handle_game_userjoin(game, account)
    if not bot_is_authorized(game.owner) then 
        return 
    end
    bot_update_game_stats(game.owner, "user_join", account.name)
end

function bot_handle_game_userleft(game, account)
    if not bot_is_authorized(game.owner) then 
        return 
    end
    bot_update_game_stats(game.owner, "user_left", account.name)
end

-- ============================================================================
-- ESTADISTICAS Y MONITOREO
-- ============================================================================

function bot_update_game_stats(bot_name, action, username)
    if not BOT_MANAGER.bot_stats then
        BOT_MANAGER.bot_stats = {}
    end
    
    if not BOT_MANAGER.bot_stats[bot_name] then
        BOT_MANAGER.bot_stats[bot_name] = {
            games_hosted  = 0,
            users_served  = 0,
            last_activity = os.time()
        }
    end
    
    if action == "user_join" then
        BOT_MANAGER.bot_stats[bot_name].users_served = BOT_MANAGER.bot_stats[bot_name].users_served + 1
    end
    
    BOT_MANAGER.bot_stats[bot_name].last_activity = os.time()
end

function bot_monitor_health()
    for _, bot_name in pairs(BOT_MANAGER.bot_list) do
        if not bot_is_online(bot_name) then
            bot_remove_from_available(bot_name)
            
            if BOT_MANAGER.assigned_bots[bot_name] then
                BOT_MANAGER.assigned_bots[bot_name] = nil
            end
        end
    end
end

function bot_get_stats_summary()
    local active_bots = 0
    local total_games = 0
    local total_users = 0
    
    for _, bot_name in pairs(BOT_MANAGER.bot_list) do
        if bot_is_online(bot_name) then
            active_bots = active_bots + 1
        end
        total_games = total_games + bot_game_count(bot_name)
    end
    
    if BOT_MANAGER.bot_stats then
        for _, stats in pairs(BOT_MANAGER.bot_stats) do
            total_users = total_users + stats.users_served
        end
    end
    
    return string.format("Bots activos: %d/%d | Juegos: %d | Usuarios atendidos: %d", 
        active_bots, #BOT_MANAGER.bot_list, total_games, total_users)
end
-- ============================================================================
-- RASTREO DE PARTIDAS ACTIVAS POR BOT
-- Tabla independiente de los holds. Se registra cuando el game se valida
-- exitosamente y se limpia en handle_game_destroy usando game_id como key.
-- ============================================================================
BOT_ACTIVE_GAMES = {}

function bot_game_register(game_id, bot_name, hostname, game_name)
    if not game_id or not bot_name then return false end
    BOT_ACTIVE_GAMES[tonumber(game_id)] = {
        bot_name  = bot_name,
        hostname  = hostname,
        game_name = game_name,
        timestamp = os.time()
    }
    INFO("[BOT-GAMES] Registrada: game_id=" .. tostring(game_id) .. " bot=" .. bot_name .. " host=" .. hostname)
    return true
end

function bot_game_remove(game_id)
    local id = tonumber(game_id)
    if not id or not BOT_ACTIVE_GAMES[id] then return false end
    local entry = BOT_ACTIVE_GAMES[id]
    INFO("[BOT-GAMES] Removida: game_id=" .. tostring(id) .. " bot=" .. entry.bot_name .. " host=" .. entry.hostname)
    BOT_ACTIVE_GAMES[id] = nil
    return true
end

function bot_game_count(bot_name)
    local count = 0
    for _, data in pairs(BOT_ACTIVE_GAMES) do
        if data.bot_name == bot_name then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- COMANDO BOTSTATS
-- ============================================================================

function command_botstats(account, text)
    local args   = split_command(text, 1)
    local action = args[1]
    
    if action == "summary" or not action then
        local summary = bot_get_stats_summary()
        api.message_send_text(account.name, message_type_info, nil, summary)
        
    elseif action == "health" then
        bot_monitor_health()
        local online_bots = bot_get_online_list()
        api.message_send_text(account.name, message_type_info, nil, 
            "Bots online: " .. #online_bots .. "/" .. #BOT_MANAGER.bot_list)
        api.message_send_text(account.name, message_type_info, nil, 
            "Disponibles: " .. bot_get_available_count())
        
    elseif action == "list" then
        local online_bots = bot_get_online_list()
        api.message_send_text(account.name, message_type_info, nil, 
            "Bots online: " .. #online_bots .. "/" .. #BOT_MANAGER.bot_list)
        for _, bot_name in pairs(online_bots) do
            local estado = "Ocupado"
            for _, av in ipairs(BOT_MANAGER.available_bots) do
                if av == bot_name then
                    estado = "Disponible"
                    break
                end
            end
            local partidas = bot_game_count(bot_name)
            api.message_send_text(account.name, message_type_info, nil, 
                bot_name .. ": " .. estado .. " | Partidas en curso: " .. partidas)
        end
    else
        api.message_send_text(account.name, message_type_error, nil, 
            "Uso: /botstats [summary|health|list]")
    end
    
    return -1
end
