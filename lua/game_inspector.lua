--[[
    Slyhark - Game Inspector & Lobby Tracker v3.0
    
    Este archivo contiene DOS sistemas relacionados:
    
    1. INSPECTOR (diagnostico): comando /inspect
       - Vuelca propiedades del game al log y a un TXT
       - Util para debug puntual de la API de PvPGN
    
    2. LOBBY TRACKER (produccion): comando /slots
       - Aprovecha rehost_holds existente, EXTENDIDO con 4 campos extras
       - Genera TXT espejo con todos los lobbies activos rehosteados
       - Muestra info al jugador en el chat (3 lineas)
    
    PATRON: Lee CONF_* dentro de lobby_tracker_init() (igual que otros modulos)
    LIMPIEZA: Aprovecha la limpieza existente de rehost_holds, no agrega nada
    
    INSTALACION (6 cambios totales):
    1. Reemplazar este archivo en la carpeta lua/
    2. Agregar variables CONF_LOBBY_* en config.lua
    3. Agregar 1 linea en cfg_monitor.lua (lobby_track_create)
    4. Agregar 1 linea en handle_game.lua (lobby_track_remove)
    5. Agregar 1 linea en handle_command.lua (registrar /slots)
    6. Agregar 1 linea en main.lua (lobby_tracker_init)
    7. Reiniciar PvPGN
]]--

-- ============================================================================
-- CONFIGURACION INTERNA DEL INSPECTOR (diagnostico)
-- output_file se llena en lobby_tracker_init() desde CONF_INSPECTOR_OUTPUT_FILE
-- Los demas valores son fijos para el comando /inspect
-- ============================================================================
local INSPECTOR_CONFIG = {
    output_file = nil,
    log_prefix = "[INSPECT]",
    inspect_server_games = true,
    inspect_account_data = true
}

-- ============================================================================
-- CONFIGURACION DEL LOBBY TRACKER
-- Variables declaradas vacias. Se llenan en lobby_tracker_init() para que las
-- variables CONF_* de config.lua ya esten disponibles cuando se lean.
-- (Mismo patron que bot_manager, cfg_monitor, w3mmd_score, map_checker)
-- ============================================================================
local LOBBY_CONFIG = {
    output_file = nil,
    throttle_seconds = nil,
    log_prefix = "[LOBBY]"
}

-- ============================================================================
-- VARIABLE INTERNA: timestamp del ultimo write al TXT (para throttle)
-- ============================================================================
local last_txt_write = 0

-- ============================================================================
-- LOG INTERNO DEL LOBBY TRACKER
-- Escribe al bnetd.log con prefijo [LOBBY] para filtrado facil
-- ============================================================================
function lobby_log(text)
    INFO(LOBBY_CONFIG.log_prefix .. " " .. text)
end

-- ============================================================================
-- INICIALIZACION DEL LOBBY TRACKER
-- Se llama desde main.lua DESPUES de que config.lua esta cargado
-- ============================================================================
function lobby_tracker_init()
    -- Leer variables desde config.lua
    LOBBY_CONFIG.output_file      = CONF_LOBBY_OUTPUT_FILE
    LOBBY_CONFIG.throttle_seconds = CONF_LOBBY_THROTTLE_SECONDS
    
    -- Inspector tambien lee su output_file desde config.lua
    INSPECTOR_CONFIG.output_file  = CONF_INSPECTOR_OUTPUT_FILE
    
    -- Reset del throttle al arrancar
    last_txt_write = 0
    
    lobby_log("Lobby Tracker iniciado. TXT: " .. LOBBY_CONFIG.output_file)
    lobby_rewrite_txt(true)
end

-- ============================================================================
-- FUNCIONES AUXILIARES INTERNAS
-- ============================================================================

-- Convierte cualquier valor a string seguro para imprimir (usado por inspector)
function inspect_safe_tostring(value)
    if value == nil then return "<nil>" end
    
    local t = type(value)
    if t == "string" then
        if value == "" then return "<empty_string>" end
        return value
    elseif t == "number" or t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        return "<table>"
    elseif t == "function" then
        return "<function>"
    else
        return "<" .. t .. ">"
    end
end

-- FASE 3: lobby_file_exists eliminada (solo la usaba lobby_parse_cfg).

-- Extrae solo el nombre del archivo de una ruta (sin carpeta)
-- Ejemplo: "Maps\Download\SaintSeiya.w3x" -> "SaintSeiya.w3x"
function lobby_extract_filename(full_path)
    if not full_path or full_path == "" then return "" end
    
    -- Probar separador Windows (\)
    local name = full_path:match("([^\\]+)$")
    if name and name ~= full_path then
        return name
    end
    
    -- Probar separador Unix (/)
    name = full_path:match("([^/]+)$")
    if name then return name end
    
    return full_path
end

-- ============================================================================
-- INSPECTOR - Comando /inspect (diagnostico, sin cambios respecto a v1.0)
-- ============================================================================

-- Escribe linea al log y al TXT del inspector
function inspect_log_line(handle, text)
    INFO(INSPECTOR_CONFIG.log_prefix .. " " .. text)
    if handle then
        handle:write(text .. "\n")
    end
end

-- Vuelca todas las propiedades de un objeto al log y al TXT
function inspect_dump_object(handle, label, obj)
    inspect_log_line(handle, "----------------------------------------")
    inspect_log_line(handle, label)
    inspect_log_line(handle, "----------------------------------------")
    
    if obj == nil then
        inspect_log_line(handle, "  OBJETO ES NIL")
        return 0
    end
    if type(obj) ~= "table" then
        inspect_log_line(handle, "  OBJETO NO ES TABLA, tipo: " .. type(obj))
        return 0
    end
    if not next(obj) then
        inspect_log_line(handle, "  OBJETO ES TABLA VACIA")
        return 0
    end
    
    local count = 0
    for k, v in pairs(obj) do
        count = count + 1
        inspect_log_line(handle, string.format("  [%d] %s = %s  (type: %s)", 
            count, inspect_safe_tostring(k), inspect_safe_tostring(v), type(v)))
    end
    
    inspect_log_line(handle, "  TOTAL DE PROPIEDADES: " .. count)
    return count
end

-- Comando /inspect: vuelca info del game actual al log y a un TXT
function command_inspect(account, text)
    local args = split_command(text, 1)
    local target_gamename = args[1]
    
    -- Abrir TXT de salida
    local handle = io.open(INSPECTOR_CONFIG.output_file, "w")
    if not handle then
        api.message_send_text(account.name, message_type_error, nil, 
            "ERROR: No se pudo abrir archivo de salida")
        return -1
    end
    
    -- Encabezado
    inspect_log_line(handle, "========================================")
    inspect_log_line(handle, "GAME INSPECTOR - DIAGNOSTICO")
    inspect_log_line(handle, "========================================")
    inspect_log_line(handle, "Fecha: " .. os.date("%Y-%m-%d %H:%M:%S"))
    inspect_log_line(handle, "Solicitado por: " .. account.name)
    inspect_log_line(handle, "")
    
    -- Determinar que game inspeccionar
    local game = nil
    if target_gamename and target_gamename ~= "" then
        game = api.game_get_by_name(target_gamename, CLIENTTAG_WAR3XP, game_type_all)
    else
        local game_id = tonumber(account.game_id)
        if game_id and game_id > 0 then
            game = api.game_get_by_id(account.game_id)
        else
            api.message_send_text(account.name, message_type_error, nil, 
                "Debes estar en una partida o pasar el nombre del game")
            handle:close()
            return -1
        end
    end
    
    if not game or not next(game) then
        api.message_send_text(account.name, message_type_error, nil, 
            "No se pudo obtener informacion del game")
        handle:close()
        return -1
    end
    
    -- Volcar propiedades del game
    local prop_count = inspect_dump_object(handle, "PROPIEDADES DEL GAME", game)
    
    -- Volcar propiedades del owner
    if game.owner then
        local owner_acc = api.account_get_by_name(game.owner)
        inspect_dump_object(handle, "PROPIEDADES DEL OWNER (" .. game.owner .. ")", owner_acc)
    end
    
    handle:close()
    
    -- Avisar al usuario
    api.message_send_text(account.name, message_type_info, nil, 
        "Diagnostico completado. " .. prop_count .. " propiedades.")
    api.message_send_text(account.name, message_type_info, nil, 
        "Archivo: " .. INSPECTOR_CONFIG.output_file)
    
    return 0
end

-- ============================================================================
-- LOBBY TRACKER - Lectura del .cfg
-- ============================================================================
-- FASE 3: lobby_parse_cfg fue eliminada. Los slots ya no se leen del .cfg
-- de disco; llegan via MAP_INFO (IPC), calculados una sola vez por el
-- MapClient para rehost y upload por igual.

-- ============================================================================
-- LOBBY TRACKER - Reescritura del TXT (espejo de rehost_holds extendido)
-- ============================================================================

-- Reescribe COMPLETO el TXT con todos los lobbies activos.
-- Recorre rehost_holds y escribe una linea por cada hold con status = "game_active"
-- y que tenga los campos extendidos del lobby tracker.
--
-- Formato de cada linea (separado por |):
--   id|nombre_partida|host_bot|host_falso|mapa|jugadores_csv|count_humanos|slots_libres|slots_totales
--
-- Parametro force: si es true, ignora throttle (escribir siempre)
--                  si es false, respeta throttle (skip si muy reciente)
-- Funcion auxiliar: escribir 1 linea de lobby al handle
-- Devuelve true si escribio, false si el hold no tiene los campos necesarios
local function lobby_write_hold_line(handle, hostname, hold_data)
    if hold_data.status ~= "game_active" 
       or not hold_data.new_game_id 
       or not hold_data.slots_totales then
        return false
    end
    
    -- Datos FIJOS
    local id = hold_data.new_game_id
    local nombre = hold_data.game_name or ""
    local host_bot = hold_data.bot_name or ""
    local host_falso = hostname
    local mapa = hold_data.mapa or ""
    local totales = hold_data.slots_totales or 0
    
    -- Datos DINAMICOS (calculados al momento desde game.players)
    local jugadores_csv = ""
    local count_humanos = 0
    local slots_libres = totales
    
    local game = api.game_get_by_id(id)
    if game and next(game) then
        local players_csv = game.players or ""
        local human_list = {}
        
        for username in string.split(players_csv, ",") do
            if username and username ~= "" then
                if username ~= host_bot then
                    table.insert(human_list, username)
                end
            end
        end
        
        jugadores_csv = table.concat(human_list, ",")
        count_humanos = #human_list
        local players_in_game = 0
        for _ in string.gmatch(game.players or "", "[^,]+") do
            players_in_game = players_in_game + 1
        end
        slots_libres = totales - players_in_game
        if slots_libres < 0 then slots_libres = 0 end
    end
    
    local line = string.format("%d|%s|%s|%s|%s|%s|%d|%d|%d\n",
        id, nombre, host_bot, host_falso, mapa, 
        jugadores_csv, count_humanos, slots_libres, totales)
    
    handle:write(line)
    return true
end

function lobby_rewrite_txt(force)
    -- Proteccion: si init no se ejecuto aun, salir silenciosamente
    if not LOBBY_CONFIG.output_file then return end
    
    local now = os.time()
    
    -- Verificar throttle (solo si no se forzo)
    if not force then
        if (now - last_txt_write) < LOBBY_CONFIG.throttle_seconds then
            return
        end
    end
    
    -- Abrir archivo en modo escritura (sobrescribe contenido anterior)
    local handle = io.open(LOBBY_CONFIG.output_file, "w")
    if not handle then
        lobby_log("ERROR: No se pudo abrir TXT para escritura")
        return
    end
    
    local line_count = 0
    
    -- FIX UPLOAD: recorrer rehost_holds Y upload_holds
    -- Ambas tablas tienen la misma estructura cuando el lobby esta activo
    if rehost_holds then
        for hostname, hold_data in pairs(rehost_holds) do
            if lobby_write_hold_line(handle, hostname, hold_data) then
                line_count = line_count + 1
            end
        end
    end
    
    if upload_holds then
        for hostname, hold_data in pairs(upload_holds) do
            if lobby_write_hold_line(handle, hostname, hold_data) then
                line_count = line_count + 1
            end
        end
    end
    
    handle:close()
    last_txt_write = now
    
    lobby_log(string.format("TXT reescrito: %d lineas (force=%s)", 
        line_count, tostring(force)))
end

-- ============================================================================
-- LOBBY TRACKER - Funciones publicas (las llaman OTROS archivos Lua)
-- ============================================================================

-- LLAMADA POR cfg_monitor.lua cuando un rehost se valida exitosamente.
-- EXTIENDE el hold existente en rehost_holds con 4 campos nuevos:
--   - new_game_id: ID del nuevo lobby creado por el bot
--   - mapa: nombre del mapa (sin ruta)
--   - slots_totales: slots totales leidos del .cfg
-- (host_bot, host_falso, game_name ya estan en el hold por el sistema rehost)
--
-- Despues reescribe el TXT espejo (con throttle).
function lobby_track_create(game_id, hostname, bot_name, game_name, slots_param)
    -- Validar parametros
    if not game_id or not hostname then
        lobby_log("track_create: parametros invalidos")
        return false
    end
    
    -- FIX UPLOAD: buscar en rehost_holds O en upload_holds
    local hold_source = nil
    if rehost_holds and rehost_holds[hostname] then
        hold_source = rehost_holds
    elseif upload_holds and upload_holds[hostname] then
        hold_source = upload_holds
    else
        lobby_log("track_create: hold no existe para " .. hostname)
        return false
    end
    
    -- FASE 3: slots viene siempre de MAP_INFO (IPC), tanto para rehost como
    -- para upload. Ya no se lee el .cfg de disco (lobby_parse_cfg eliminado
    -- de este flujo).
    if not slots_param or slots_param <= 0 then
        lobby_log("No se pudo trackear lobby (MAP_INFO invalido o no disponible): " .. hostname)
        return false
    end
    local max_slots = slots_param
    
    -- Obtener mapa actual desde el game recien creado
    local game = api.game_get_by_id(game_id)
    local map_filename = ""
    if game and next(game) then
        map_filename = lobby_extract_filename(game.mapname or "")
    end
    
    -- EXTENDER el hold existente con campos del tracker (sea rehost o upload)
    hold_source[hostname].new_game_id   = tonumber(game_id)
    hold_source[hostname].mapa          = map_filename
    hold_source[hostname].slots_totales = max_slots
    
    lobby_log(string.format("CREATE: game_id=%s host_falso=%s host_bot=%s slots=%d map=%s", 
        tostring(game_id), hostname, bot_name or "?", max_slots, map_filename))
    
    -- Reescribir TXT con throttle (evento automatico)
    lobby_rewrite_txt(true)
    
    return true
end

-- LLAMADA POR handle_game.lua cuando una partida se destruye.
-- IMPORTANTE: tu codigo existente YA borra rehost_holds[username] = nil
-- Esta funcion solo reescribe el TXT despues de la limpieza para que
-- el espejo refleje el cambio.
function lobby_track_remove(game_id)
    -- Reescribir TXT con throttle (evento automatico)
    -- Como rehost_holds ya fue limpiado por el codigo existente,
    -- esa entrada ya no aparecera en el TXT
    lobby_rewrite_txt(false)
    return true
end

-- ============================================================================
-- LOBBY TRACKER - Comando /slots
-- ============================================================================

-- Comando ejecutado por el jugador dentro de un lobby rehosteado.
-- Solo funciona si el lobby actual tiene un hold trackeado en rehost_holds.
-- Muestra info al jugador en chat y reescribe el TXT (force=true).
function command_slots(account, text)
    -- Verificar que el jugador este en una partida (no en canal)
    local game_id = tonumber(account.game_id)
    if not game_id or game_id <= 0 then
        api.message_send_text(account.name, message_type_error, nil, 
            "Debes estar en un lobby para usar este comando")
        return -1
    end
    
    -- Obtener info del game actual desde la API
    local game = api.game_get_by_id(account.game_id)
    if not game or not next(game) then
        api.message_send_text(account.name, message_type_error, nil, 
            "No se pudo obtener informacion del lobby")
        return -1
    end
    
    -- FIX UPLOAD: buscar en rehost_holds Y upload_holds
    -- El lobby puede venir de /rehost o de /upload, ambos producen entradas
    -- con la misma estructura cuando estan activas (status=game_active + new_game_id + slots_totales)
    local current_game_id = tonumber(game.id)
    local matched_hold = nil
    
    if rehost_holds then
        for hostname, hold_data in pairs(rehost_holds) do
            if hold_data.status == "game_active" 
               and tonumber(hold_data.new_game_id) == current_game_id
               and hold_data.slots_totales then
                matched_hold = hold_data
                matched_hold.host_falso = hostname
                break
            end
        end
    end
    
    if not matched_hold and upload_holds then
        for hostname, hold_data in pairs(upload_holds) do
            if hold_data.status == "game_active" 
               and tonumber(hold_data.new_game_id) == current_game_id
               and hold_data.slots_totales then
                matched_hold = hold_data
                matched_hold.host_falso = hostname
                break
            end
        end
    end
    
    -- Si no encontramos hold, el lobby NO viene de /rehost ni /upload
    if not matched_hold then
        api.message_send_text(account.name, message_type_error, nil, 
            "No disponible. Estas en una partida no rehosteada")
        return -1
    end
    
    -- Datos FIJOS desde el hold extendido
    local nombre = matched_hold.game_name or "?"
    local host_bot = matched_hold.bot_name or ""
    local totales = matched_hold.slots_totales or 0
    
    -- Calcular DINAMICOS desde game.players actual
    local players_csv = game.players or ""
    local human_players = {}
    
    -- Filtrar el bot conocido (sabemos su nombre exacto)
    for username in string.split(players_csv, ",") do
        if username and username ~= "" then
            if username ~= host_bot then
                table.insert(human_players, username)
            end
        end
    end
    
    local count_humanos = #human_players
    local slots_libres = totales - count_humanos
    if slots_libres < 0 then slots_libres = 0 end
    
    -- Construir lista de jugadores para mostrar en chat
    local players_display = "ninguno"
    if count_humanos > 0 then
        players_display = table.concat(human_players, ", ")
    end
    
    -- Reescribir TXT FORZADO (usuario explicitamente lo pidio = ignorar throttle)
    lobby_rewrite_txt(true)
    
    -- Mostrar info al jugador en el chat (3 lineas, sin host_bot ni host_falso)
    api.message_send_text(account.name, message_type_info, nil, 
        "Partida: " .. nombre)
    api.message_send_text(account.name, message_type_info, nil, 
        "Jugadores: " .. players_display)
    api.message_send_text(account.name, message_type_info, nil, 
        string.format("Slots: %d/%d (%d libres)", count_humanos, totales, slots_libres))
    
    lobby_log(string.format("SLOTS query by %s | game_id=%d | humans=%d/%d", 
        account.name, current_game_id, count_humanos, totales))
    
    return 0
end
