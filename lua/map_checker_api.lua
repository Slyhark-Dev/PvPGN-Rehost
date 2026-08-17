--[[
    MAP CHECKER API v1.0 - VERSION AUTOMATICA
    Sistema de verificacion automatica de mapas en /rehost
    
    FUNCION: Se ejecuta automaticamente cuando un jugador usa /rehost
    VERIFICA: Si el mapa actual esta disponible en servidor web
]]--

-- ============================================================================
-- CONFIGURACION
-- Variables declaradas vacias. Se llenan en map_checker_init() para que las
-- variables CONF_* de config.lua ya esten disponibles cuando se lean.
-- ============================================================================
local MAPS_DOWNLOAD_DIRECTORY = nil
local MAP_EXTENSIONS          = nil
local DEBUG_ENABLED           = false

-- ============================================================================
-- FUNCIONES CORE
-- ============================================================================

function file_exists_in_directory(filepath)
    local file = io.open(filepath, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function clean_map_name(mapname)
    if not mapname then return "" end
    
    local cleaned = mapname:gsub("^maps/", "")
    cleaned = cleaned:match("([^/\\]+)$") or cleaned
    cleaned = cleaned:gsub("%.w3[xm]$", "")
    
    return cleaned
end

function check_map_availability(mapname)
    if not mapname or mapname == "" then
        return false, "Nombre de mapa vacio"
    end
    
    local cleaned_name = clean_map_name(mapname)
    
    if DEBUG_ENABLED then
        print("[MAP-CHECKER] Verificando: '" .. mapname .. "' -> '" .. cleaned_name .. "'")
    end
    
    for _, extension in ipairs(MAP_EXTENSIONS) do
        local full_path = MAPS_DOWNLOAD_DIRECTORY .. cleaned_name .. extension
        
        if file_exists_in_directory(full_path) then
            if DEBUG_ENABLED then
                print("[MAP-CHECKER] ENCONTRADO: " .. full_path)
            end
            return true, cleaned_name .. extension
        end
    end
    
    if DEBUG_ENABLED then
        print("[MAP-CHECKER] NO ENCONTRADO: " .. cleaned_name)
    end
    
    return false, "Archivo no encontrado"
end

-- ============================================================================
-- FUNCION PRINCIPAL - LLAMADA DESDE /rehost
-- ============================================================================

function map_checker_on_rehost(account)
    -- Proteccion: si init no se ejecuto aun, salir silenciosamente
    if not MAPS_DOWNLOAD_DIRECTORY then return end
    
    local game    = nil
    local game_id = tonumber(account.game_id)
    if game_id and game_id > 0 then
        game = api.game_get_by_id(account.game_id)
    end
    
    if not game or not next(game) then
        if DEBUG_ENABLED then
            print("[MAP-CHECKER] No se pudo obtener info del juego para: " .. account.name)
        end
        return
    end
    
    local mapname = game.mappath or game.mapname or game.name
    
    if not mapname then
        if DEBUG_ENABLED then
            print("[MAP-CHECKER] No se pudo obtener nombre del mapa")
        end
        return
    end
    
    local available, details = check_map_availability(mapname)
    
    if available then
        local message = "Mapa disponible: " .. clean_map_name(mapname)
        api.message_send_text(account.name, message_type_info, account.name, message)
        
        if DEBUG_ENABLED then
            print("[MAP-CHECKER] DISPONIBLE: " .. clean_map_name(mapname))
        end
    else
        local message = "Mapa no disponible: " .. clean_map_name(mapname)
        api.message_send_text(account.name, message_type_error, account.name, message)
        
        if DEBUG_ENABLED then
            print("[MAP-CHECKER] NO DISPONIBLE: " .. clean_map_name(mapname))
        end
    end
end

-- ============================================================================
-- INICIALIZACION
-- ============================================================================

function map_checker_init()
    -- Aqui se leen las CONF_* porque main() (que llama a map_checker_init)
    -- corre DESPUES de que todos los archivos lua estan cargados,
    -- incluyendo config.lua
    MAPS_DOWNLOAD_DIRECTORY = CONF_MAPS_DIRECTORY
    MAP_EXTENSIONS          = CONF_DOWNLOAD_EXTENSIONS
    DEBUG_ENABLED           = CONF_DEBUG_MAP_CHECKER
    
    if DEBUG_ENABLED then
        print("[MAP-CHECKER] === SISTEMA MAP CHECKER INICIADO ===")
        print("[MAP-CHECKER] Directorio: " .. MAPS_DOWNLOAD_DIRECTORY)
        print("[MAP-CHECKER] Extensiones: " .. table.concat(MAP_EXTENSIONS, ", "))
        print("[MAP-CHECKER] Integracion automatica con /rehost: HABILITADA")
        print("[MAP-CHECKER] ==========================================")
    end
end
