--[[
    Slyhark (marcos@carpiomeza.eu.org)
    
    W3MMD SCORE API v2.1 - CON ESTADISTICAS POR RAZA (FORMATO DB CORREGIDO)
    Sistema de EXP y Level basado en logs w3mmd_results.log
    
    NUEVA CARACTERISTICA: Actualiza estadisticas por raza cuando hay winner/loser
    METODO: API NATIVA DE PVPGN (TIEMPO REAL)
    FORMATO: Basado en estructura real de base de datos
    
    Formato de log esperado:
    timestamp|gamename|playername|race|flags|pid
    
    Donde:
    - flags = resultado del juego ("winner" = victoria, "loser" = derrota, "" = solo jugo)
    - race = raza jugada ("orc", "human", "undead", "nightelf", "random")
    - pid = slot del jugador (0, 1, 2, etc.)
]]--

-- ============================================================================
-- CONFIGURACION
-- Variables declaradas vacias. Se llenan en w3mmd_score_init() para que las
-- variables CONF_* de config.lua ya esten disponibles cuando se lean.
-- ============================================================================
local RESULTS_LOG_FILE   = nil
local DEBUG_ENABLED      = false
local EXP_REWARDS        = {}

-- MAPEO DE RAZAS A CAMPOS DE BASE DE DATOS
local RACE_MAPPING = {
    ["human"]    = "humans",
    ["orc"]      = "orcs",
    ["undead"]   = "undead",
    ["nightelf"] = "nightelves",
    ["random"]   = "random",
}

-- ============================================================================
-- VARIABLES GLOBALES
-- ============================================================================



-- ============================================================================
-- FUNCIONES AUXILIARES
-- ============================================================================

function split_string(str, delimiter)
    local result = {}
    if not str then return result end
    
    local s = str .. delimiter
    for match in s:gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    
    return result
end

-- ============================================================================
-- FUNCIONES DE ARCHIVO
-- ============================================================================

function file_exists(filename)
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function read_all_lines(filename)
    local file = io.open(filename, "r")
    if not file then return nil end
    
    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()
    
    return lines
end

function write_remaining_lines(lines)
    local file = io.open(RESULTS_LOG_FILE, "w")
    if not file then
        if DEBUG_ENABLED then
            print("[W3MMD] No se pudo escribir " .. RESULTS_LOG_FILE)
        end
        return
    end
    
    for _, line in ipairs(lines) do
        file:write(line .. "\n")
    end
    file:close()
end

-- ============================================================================
-- FUNCIONES DE DATOS CON API NATIVA
-- ============================================================================

function get_current_exp(playername)
    local exp = api.account_get_attr(playername, "Record\\W3XP_solo_xp", attr_type_num)
    return exp or 0
end

function get_current_level(playername)
    local level = api.account_get_attr(playername, "Record\\W3XP_solo_level", attr_type_num)
    return level or 1
end

function get_current_wins(playername)
    local wins = api.account_get_attr(playername, "Record\\W3XP_solo_wins", attr_type_num)
    return wins or 0
end

function get_current_losses(playername)
    local losses = api.account_get_attr(playername, "Record\\W3XP_solo_losses", attr_type_num)
    return losses or 0
end

function get_current_race_wins(playername, race)
    local race_field = RACE_MAPPING[string.lower(race)]
    if not race_field then return 0 end
    
    local race_wins = api.account_get_attr(playername, "Record\\W3XP_" .. race_field .. "_wins", attr_type_num)
    return race_wins or 0
end

function get_current_race_losses(playername, race)
    local race_field = RACE_MAPPING[string.lower(race)]
    if not race_field then return 0 end
    
    local race_losses = api.account_get_attr(playername, "Record\\W3XP_" .. race_field .. "_losses", attr_type_num)
    return race_losses or 0
end

function calculate_level_from_exp(exp)
    if exp < 100 then return 1
    elseif exp < 200 then return 2
    elseif exp < 400 then return 3
    elseif exp < 600 then return 4
    elseif exp < 900 then return 5
    elseif exp < 1200 then return 6
    elseif exp < 1600 then return 7
    elseif exp < 2000 then return 8
    elseif exp < 2500 then return 9
    elseif exp < 3000 then return 10
    else return math.min(50, math.floor(exp / 500) + 1) end
end

function update_player_exp_and_stats(playername, result_type, race)
    local exp_gained     = EXP_REWARDS[result_type] or EXP_REWARDS["played"]
    local current_exp    = get_current_exp(playername)
    local current_wins   = get_current_wins(playername)
    local current_losses = get_current_losses(playername)
    
    local new_exp    = current_exp + exp_gained
    local new_level  = calculate_level_from_exp(new_exp)
    local new_wins   = current_wins
    local new_losses = current_losses
    
    local current_race_wins   = 0
    local current_race_losses = 0
    local new_race_wins       = 0
    local new_race_losses     = 0
    local race_field          = nil
    
    local success = true
    
    if result_type == "winner" then
        new_wins = current_wins + 1
        
        if race and RACE_MAPPING[string.lower(race)] then
            race_field        = RACE_MAPPING[string.lower(race)]
            current_race_wins = get_current_race_wins(playername, race)
            new_race_wins     = current_race_wins + 1
        end
        
    elseif result_type == "loser" then
        new_losses = current_losses + 1
        
        if race and RACE_MAPPING[string.lower(race)] then
            race_field          = RACE_MAPPING[string.lower(race)]
            current_race_losses = get_current_race_losses(playername, race)
            new_race_losses     = current_race_losses + 1
        end
    end
    
    if not api.account_set_attr(playername, "Record\\W3XP_solo_xp", attr_type_num, new_exp) then
        success = false
    end
    
    if not api.account_set_attr(playername, "Record\\W3XP_solo_level", attr_type_num, new_level) then
        success = false
    end
    
    if new_wins ~= current_wins then
        if not api.account_set_attr(playername, "Record\\W3XP_solo_wins", attr_type_num, new_wins) then
            success = false
        end
    end
    
    if new_losses ~= current_losses then
        if not api.account_set_attr(playername, "Record\\W3XP_solo_losses", attr_type_num, new_losses) then
            success = false
        end
    end
    
    if race_field then
        if result_type == "winner" and new_race_wins > current_race_wins then
            if not api.account_set_attr(playername, "Record\\W3XP_" .. race_field .. "_wins", attr_type_num, new_race_wins) then
                success = false
            end
        elseif result_type == "loser" and new_race_losses > current_race_losses then
            if not api.account_set_attr(playername, "Record\\W3XP_" .. race_field .. "_losses", attr_type_num, new_race_losses) then
                success = false
            end
        end
    end
    
    if DEBUG_ENABLED then
        local result_text = result_type == "winner" and "VICTORIA" or (result_type == "loser" and "DERROTA" or "PARTIDA")
        local status      = success and "ACTUALIZADO" or "ERROR"
        local race_info   = ""
        
        if race_field then
            if result_type == "winner" then
                race_info = string.format(" | %s W: %d->%d", race, current_race_wins, new_race_wins)
            elseif result_type == "loser" then
                race_info = string.format(" | %s L: %d->%d", race, current_race_losses, new_race_losses)
            end
        elseif race then
            race_info = " | Raza: " .. race .. " (sin stats)"
        end
        
        print(string.format("[W3MMD-RAZA] %s | %s | +%d EXP | Level:%d | Total:%d | W/L:%d/%d%s | %s", 
            playername, result_text, exp_gained, new_level, new_exp, new_wins, new_losses, race_info, status))
    end
    
    return success
end

-- ============================================================================
-- PROCESAMIENTO DE LOGS
-- ============================================================================

function process_w3mmd_results_log()
    if not file_exists(RESULTS_LOG_FILE) then
        return
    end
    
    local lines = read_all_lines(RESULTS_LOG_FILE)
    if not lines or #lines == 0 then
        return
    end
    
    local processed_count = 0
    local remaining_lines = {}
    
    for i, line in ipairs(lines) do
        if process_log_line(line) then
            processed_count = processed_count + 1
        else
            table.insert(remaining_lines, line)
        end
    end
    
    write_remaining_lines(remaining_lines)
    
    if processed_count > 0 and DEBUG_ENABLED then
        print("[W3MMD-RAZA] Procesadas " .. processed_count .. " lineas, restantes: " .. #remaining_lines)
    end
end

function process_log_line(line)
    if not line or string.len(line) == 0 then
        return true
    end
    
    local parts = split_string(line, "|")
    if #parts ~= 6 then
        if DEBUG_ENABLED then
            print("[W3MMD-RAZA] Formato incorrecto (" .. #parts .. " campos): " .. line)
        end
        return false
    end
    
    local timestamp  = parts[1]
    local gamename   = parts[2]
    local playername = parts[3]
    local race       = parts[4]
    local flags      = parts[5]
    local pid        = tonumber(parts[6])
    
    if not playername or playername == "" then
        return true
    end
    
    if (flags == "winner" or flags == "loser") and (not race or race == "") then
        if DEBUG_ENABLED then
            print("[W3MMD-RAZA] ELIMINADO: " .. playername .. " tiene " .. flags .. " pero raza vacia - Datos invalidos")
        end
        return true
    end
    
    local result_type
    if flags == "winner" then
        result_type = "winner"
    elseif flags == "loser" then
        result_type = "loser"
    else
        result_type = "played"
    end
    
    local success = update_player_exp_and_stats(playername, result_type, race)
    
    if not success and DEBUG_ENABLED then
        print("[W3MMD-RAZA] ERROR: No se pudo actualizar " .. playername)
        return false
    end
    
    return true
end

-- ============================================================================
-- MAINLOOP INTEGRATION
-- ============================================================================
-- Ya no se usa polling. process_w3mmd_results_log() se dispara directamente
-- desde handle_game_end() en handle_game.lua cada vez que finaliza una partida.
function w3mmd_score_mainloop()
end

-- ============================================================================
-- HOOK IPC: EVENTOS EXTERNOS
-- ============================================================================
-- Llamado desde C++ (ipc_server.cpp, puerto 7773) cuando el .py de W3MMD
-- envia un resultado parseado de replay. Diseno generico: event_type permite
-- agregar futuros eventos sin modificar C++.
--
-- Formato payload para W3MMD_RESULT:
--   "gameID|timestamp|gamename|playername|race|flags|pid"
--
-- Si el IPC falla o el .py no puede conectar, el .py escribe al log como
-- fallback y process_w3mmd_results_log() lo procesa en el siguiente ciclo.
-- ============================================================================
function handle_external_event(event_type, payload)
    if not CONF_W3MMD_ENABLED then
        return
    end

    if event_type == "W3MMD_RESULT" then
        -- payload: "gameID|timestamp|gamename|playername|race|flags|pid"
        local parts = split_string(payload, "|")
        if #parts ~= 7 then
            if DEBUG_ENABLED then
                print("[W3MMD-IPC] Payload invalido (" .. #parts .. " campos): " .. tostring(payload))
            end
            return
        end

        local gameID     = parts[1]
        local timestamp  = parts[2]
        local gamename   = parts[3]
        local playername = parts[4]
        local race       = parts[5]
        local flags      = parts[6]
        local pid        = tonumber(parts[7])

        if not playername or playername == "" then
            if DEBUG_ENABLED then
                print("[W3MMD-IPC] playername vacio, ignorando")
            end
            return
        end

        -- Validacion: winner/loser requieren raza
        if (flags == "winner" or flags == "loser") and (not race or race == "") then
            if DEBUG_ENABLED then
                print("[W3MMD-IPC] ELIMINADO: " .. playername .. " tiene " .. flags .. " pero raza vacia")
            end
            return
        end

        local result_type
        if flags == "winner" then
            result_type = "winner"
        elseif flags == "loser" then
            result_type = "loser"
        else
            result_type = "played"
        end

        if DEBUG_ENABLED then
            print(string.format("[W3MMD-IPC] Procesando via IPC: game=%s player=%s race=%s result=%s",
                gamename, playername, race, result_type))
        end

        local success = update_player_exp_and_stats(playername, result_type, race)

        if DEBUG_ENABLED then
            if success then
                print("[W3MMD-IPC] OK: " .. playername .. " actualizado")
            else
                print("[W3MMD-IPC] ERROR: no se pudo actualizar " .. playername)
            end
        end
    else
        -- Evento desconocido. Generico: logear y continuar sin error.
        if DEBUG_ENABLED then
            print("[W3MMD-IPC] Evento desconocido: " .. tostring(event_type))
        end
    end
end

-- ============================================================================
-- COMANDO DE VERIFICACION
-- ============================================================================

function command_w3stats(account, text)
    local target_player = account.name
    local args = split_string(text, " ")
    if args[1] then target_player = args[1] end
    
    local exp    = get_current_exp(target_player)
    local level  = get_current_level(target_player)
    local wins   = get_current_wins(target_player)
    local losses = get_current_losses(target_player)
    
    local total_games = wins + losses
    local win_ratio   = total_games > 0 and math.floor((wins / total_games) * 100) or 0
    
    if exp > 0 or total_games > 0 then
        print(string.format("[STATS-RAZA] %s | Level %d | EXP: %d | W/L: %d/%d (%d%%) | DATOS EN TIEMPO REAL", 
            target_player, level, exp, wins, losses, win_ratio))
        
        for race_name, race_field in pairs(RACE_MAPPING) do
            local race_wins   = get_current_race_wins(target_player, race_name)
            local race_losses = get_current_race_losses(target_player, race_name)
            if race_wins > 0 or race_losses > 0 then
                local race_total = race_wins + race_losses
                local race_ratio = race_total > 0 and math.floor((race_wins / race_total) * 100) or 0
                print(string.format("[STATS-RAZA] %s %s: %d/%d (%d%%)", 
                    target_player, race_name, race_wins, race_losses, race_ratio))
            end
        end
    else
        print("[STATS-RAZA] No se encontraron stats para: " .. target_player)
    end
    
    return 0
end

-- ============================================================================
-- INICIALIZACION
-- ============================================================================

function w3mmd_score_init()
    if not CONF_W3MMD_ENABLED then
        print("[W3MMD-RAZA] Sistema DESACTIVADO (CONF_W3MMD_ENABLED = false)")
        return
    end
    -- Aqui se leen las CONF_* porque main() (que llama a w3mmd_score_init)
    -- corre DESPUES de que todos los archivos lua estan cargados,
    -- incluyendo config.lua
    RESULTS_LOG_FILE   = CONF_W3MMD_LOG_FILE
    DEBUG_ENABLED      = CONF_DEBUG_W3MMD
    
    EXP_REWARDS = {
        ["winner"] = CONF_W3MMD_EXP_WINNER,
        ["loser"]  = CONF_W3MMD_EXP_LOSER,
        ["played"] = CONF_W3MMD_EXP_PLAYED,
    }
    
    if DEBUG_ENABLED then
        print("[W3MMD-RAZA] === SISTEMA W3MMD SCORE v2.1 INICIADO ===")
        print("[W3MMD-RAZA] METODO: API NATIVA DE PVPGN (TIEMPO REAL)")
        print("[W3MMD-RAZA] Archivo monitoreado: " .. RESULTS_LOG_FILE)
        print("[W3MMD-RAZA] Victoria (flags='winner'): " .. EXP_REWARDS["winner"] .. " EXP + race stats")
        print("[W3MMD-RAZA] Derrota (flags='loser'): " .. EXP_REWARDS["loser"] .. " EXP + race stats")
        print("[W3MMD-RAZA] Solo jugo (flags=''): " .. EXP_REWARDS["played"] .. " EXP solamente")
        print("[W3MMD-RAZA] Modo: evento handle_game_end (sin polling)")
        print("[W3MMD-RAZA] Mapeo de razas:")
        for race_name, race_field in pairs(RACE_MAPPING) do
            print("[W3MMD-RAZA]   " .. race_name .. " -> W3XP_" .. race_field .. "_wins/losses")
        end
        print("[W3MMD-RAZA] OK ACTUALIZACION INSTANTANEA CON RAZAS HABILITADA")
        print("[W3MMD-RAZA] =======================================")
    end
end
