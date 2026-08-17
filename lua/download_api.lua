--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--


-- API DE DESCARGA ROBUSTA - VERSION SIMPLIFICADA
active_downloads = 0

-- Tabla declarada vacia. Se llena en download_api_init() para que las
-- variables CONF_* de config.lua ya esten disponibles cuando se lean.
-- allowed_contexts         = "lobby", or "both" 
local DOWNLOAD_CONFIG = {
    require_permissions      = false,
    moderator_command_groups = {2, 4},
    allowed_contexts         = "both",  
}

function url_decode(str)
    if not str then return "" end
    str = string.gsub(str, "+", " ")
    str = string.gsub(str, "%%(%x%x)", function(h) 
        return string.char(tonumber(h, 16)) 
    end)
    return str
end

function extract_domain_from_url(url)
    if not url then return nil end
    return url:match("^https?://([^/]+)")
end

function validate_url_improved(url)
    if not url or url == "" then
        return false, "URL vacia"
    end
    if not url:match("^https?://") then
        return false, "URL debe empezar con http:// o https://"
    end
    local domain = extract_domain_from_url(url)
    if not domain then
        return false, "No se pudo extraer dominio"
    end
    for _, allowed_domain in pairs(DOWNLOAD_CONFIG.allowed_domains) do
        if domain == allowed_domain then
            return true, "OK"
        end
    end
    return false, "Dominio no permitido: " .. domain
end

function extract_filename_improved(url)
    if not url then return "unknown.w3x" end
    local clean_url = url:match("([^?#]+)") or url
    local filename  = clean_url:match(".*/([^/]+)$")
    if not filename or filename == "" or filename == "download" then
        local map_id = url:match("/maps/(%d+)")
        if map_id then
            filename = "epicwar_" .. map_id .. ".w3x"
        else
            filename = "map_" .. os.time() .. ".w3x"
        end
    else
        filename = url_decode(filename)
    end
    filename = filename:gsub('[<>:"/\\|?*]', "_")
    if not filename:match("%.w3[xm]$") then
        filename = filename .. ".w3x"
    end
    if #filename > 100 then
        filename = filename:sub(1, 90) .. ".w3x"
    end
    return filename
end

function validate_file_extension_improved(filename)
    local ext = filename:match("%.([^%.]+)$")
    if not ext then return false, "Sin extension" end
    ext = "." .. ext:lower()
    for _, allowed in pairs(DOWNLOAD_CONFIG.allowed_extensions) do
        if ext == allowed then return true, "OK" end
    end
    return false, "Extension no permitida"
end

function check_file_exists(filepath)
    local file = io.open(filepath, "r")
    if file then file:close(); return true end
    return false
end

function get_file_size(filepath)
    local file = io.open(filepath:gsub("/", "\\"), "rb")
    if not file then return 0 end
    local size = file:seek("end")
    file:close()
    return tonumber(size) or 0
end

function get_user_context(account)
    local game_id = tonumber(account.game_id)
    if game_id and game_id > 0 then return "lobby" end
    return "channel"
end

function check_download_permissions(account)
    local context = get_user_context(account)
    if DOWNLOAD_CONFIG.allowed_contexts ~= "both" and DOWNLOAD_CONFIG.allowed_contexts ~= context then
        return false, "Solo en " .. DOWNLOAD_CONFIG.allowed_contexts
    end
    if account_get_auth_admin(account.name) then return true, "admin" end
    if not DOWNLOAD_CONFIG.require_permissions then return true, "ok" end
    return false, "Sin permisos"
end

-- ============================================================================
-- HEAD REQUEST: obtiene el nombre real del archivo SIN descargarlo
-- Devuelve el nombre real o nil si falla
-- ============================================================================
function get_real_filename_from_url(url)
    local timestamp = os.time()
    local url_file  = DOWNLOAD_CONFIG.download_directory .. "head_url_" .. timestamp .. ".txt"
    local ps_script = DOWNLOAD_CONFIG.download_directory .. "head_" .. timestamp .. ".ps1"
    
    os.execute('if not exist "' .. DOWNLOAD_CONFIG.download_directory .. '" mkdir "' .. DOWNLOAD_CONFIG.download_directory .. '"')
    
    local uf = io.open(url_file, "w")
    if not uf then return nil end
    uf:write(url)
    uf:close()
    
    local ps = io.open(ps_script, "w")
    if not ps then
        os.remove(url_file)
        return nil
    end
    
    ps:write("$ErrorActionPreference = 'Stop'\n")
    ps:write("$urlFile = '" .. url_file .. "'\n")
    ps:write("try {\n")
    ps:write("  $url = Get-Content $urlFile\n")
    ps:write("  Add-Type -AssemblyName System.Net.Http\n")
    ps:write("  $handler = New-Object System.Net.Http.HttpClientHandler\n")
    ps:write("  $handler.AllowAutoRedirect = $true\n")
    ps:write("  $client = New-Object System.Net.Http.HttpClient($handler)\n")
    ps:write("  $client.Timeout = [TimeSpan]::FromSeconds(30)\n")
    ps:write("  $client.DefaultRequestHeaders.Add('User-Agent', 'Mozilla/5.0')\n")
    ps:write("  $client.DefaultRequestHeaders.Add('Referer', 'https://www.epicwar.com/')\n")
    ps:write("  $request = New-Object System.Net.Http.HttpRequestMessage('Head', $url)\n")
    ps:write("  $response = $client.SendAsync($request).Result\n")
    ps:write("  $response.EnsureSuccessStatusCode()\n")
    ps:write("  if ($response.Content.Headers.ContentDisposition) {\n")
    ps:write("    $dn = $response.Content.Headers.ContentDisposition.FileName\n")
    ps:write("    if ($dn) {\n")
    ps:write("      $realName = $dn.Trim('\"')\n")
    ps:write("      Write-Output \"REALNAME:$realName\"\n")
    ps:write("    } else {\n")
    ps:write("      Write-Output 'NONAME'\n")
    ps:write("    }\n")
    ps:write("  } else {\n")
    ps:write("    Write-Output 'NONAME'\n")
    ps:write("  }\n")
    ps:write("  $response.Dispose()\n")
    ps:write("  $client.Dispose()\n")
    ps:write("} catch {\n")
    ps:write("  Write-Output \"ERROR:$($_.Exception.Message)\"\n")
    ps:write("}\n")
    ps:close()
    
    local ps_cmd = 'powershell -ExecutionPolicy Bypass -File "' .. ps_script .. '"'
    local handle = io.popen(ps_cmd)
    local result = handle:read("*a")
    handle:close()
    
    os.remove(ps_script)
    os.remove(url_file)
    
    if result then
        result = result:gsub("[\r\n]", "")
        local real_name = result:match("REALNAME:([^\n]+)")
        if real_name then
            return real_name
        end
    end
    
    return nil
end

function download_file_secure(url, custom_filename, force_download)
    if active_downloads >= DOWNLOAD_CONFIG.max_concurrent_downloads then
        return false, "Demasiadas descargas activas"
    end
    
    active_downloads = active_downloads + 1
    
    local valid, error_msg = validate_url_improved(url)
    if not valid then
        active_downloads = active_downloads - 1
        return false, error_msg
    end
    
    local filename     = custom_filename or extract_filename_improved(url)
    local ext_valid, ext_msg = validate_file_extension_improved(filename)
    if not ext_valid then
        active_downloads = active_downloads - 1
        return false, ext_msg
    end
    
    -- Verificacion previa con HEAD request
    if not force_download then
        local real_name = get_real_filename_from_url(url)
        if real_name then
            local real_path = DOWNLOAD_CONFIG.download_directory .. real_name
            if check_file_exists(real_path) then
                active_downloads = active_downloads - 1
                return false, "Archivo existe (" .. real_name .. "). Usa 'force'"
            end
            filename = real_name
        end
    end
    
    local filepath = DOWNLOAD_CONFIG.download_directory .. filename
    
    if check_file_exists(filepath) and not force_download then
        active_downloads = active_downloads - 1
        return false, "Archivo existe. Usa 'force'"
    end
    
    os.execute('if not exist "' .. DOWNLOAD_CONFIG.download_directory .. '" mkdir "' .. DOWNLOAD_CONFIG.download_directory .. '"')
    
    local url_file  = DOWNLOAD_CONFIG.download_directory .. "temp_url_" .. os.time() .. ".txt"
    local uf = io.open(url_file, "w")
    if uf then
        uf:write(url)
        uf:close()
    end
    
    local path_file = DOWNLOAD_CONFIG.download_directory .. "temp_path_" .. os.time() .. ".txt"
    local pf = io.open(path_file, "w")
    if pf then
        pf:write(filepath)
        pf:close()
    end
    
    local dir_param = DOWNLOAD_CONFIG.download_directory
    local ps_script = DOWNLOAD_CONFIG.download_directory .. "dl_" .. os.time() .. ".ps1"
    local ps = io.open(ps_script, "w")
    if not ps then
        active_downloads = active_downloads - 1
        return false, "No se pudo crear script"
    end
    
    ps:write("$ErrorActionPreference = 'Stop'\n")
    ps:write("$urlFile = '" .. url_file .. "'\n")
    ps:write("$pathFile = '" .. path_file .. "'\n")
    ps:write("$dirPath = '" .. dir_param .. "'\n")
    ps:write("try {\n")
    ps:write("  $url = Get-Content $urlFile\n")
    ps:write("  $filepath = Get-Content $pathFile\n")
    ps:write("  Add-Type -AssemblyName System.Net.Http\n")
    ps:write("  $handler = New-Object System.Net.Http.HttpClientHandler\n")
    ps:write("  $handler.AllowAutoRedirect = $true\n")
    ps:write("  $client = New-Object System.Net.Http.HttpClient($handler)\n")
    ps:write("  $client.Timeout = [TimeSpan]::FromSeconds(60)\n")
    ps:write("  $client.DefaultRequestHeaders.Add('User-Agent', 'Mozilla/5.0')\n")
    ps:write("  $client.DefaultRequestHeaders.Add('Referer', 'https://www.epicwar.com/')\n")
    ps:write("  $response = $client.GetAsync($url).Result\n")
    ps:write("  if ($response.Content.Headers.ContentType.MediaType -like 'text/html*') {\n")
    ps:write("    Write-Output 'ERROR:HTML'\n")
    ps:write("    exit\n")
    ps:write("  }\n")
    ps:write("  $response.EnsureSuccessStatusCode()\n")
    ps:write("  $realName = $null\n")
    ps:write("  if ($response.Content.Headers.ContentDisposition) {\n")
    ps:write("    $dn = $response.Content.Headers.ContentDisposition.FileName\n")
    ps:write("    if ($dn) {\n")
    ps:write("      $realName = $dn.Trim('\"')\n")
    ps:write("      if ($realName -match '\\.w3[xm]$') {\n")
    ps:write("        $filepath = $dirPath + $realName\n")
    ps:write("        Write-Output \"REALNAME:$realName\"\n")
    ps:write("      }\n")
    ps:write("    }\n")
    ps:write("  }\n")
    ps:write("  $stream = [System.IO.File]::Create($filepath)\n")
    ps:write("  $content = $response.Content.ReadAsStreamAsync().Result\n")
    ps:write("  $buffer = New-Object byte[] 131072\n")
    ps:write("  do {\n")
    ps:write("    $r = $content.Read($buffer, 0, $buffer.Length)\n")
    ps:write("    if ($r -gt 0) { $stream.Write($buffer, 0, $r) }\n")
    ps:write("  } while ($r -gt 0)\n")
    ps:write("  $stream.Close()\n")
    ps:write("  $content.Close()\n")
    ps:write("  $response.Dispose()\n")
    ps:write("  $client.Dispose()\n")
    ps:write("  if (Test-Path $filepath) {\n")
    ps:write("    $size = (Get-Item $filepath).Length\n")
    ps:write("    if ($size -eq 0) {\n")
    ps:write("      Remove-Item $filepath\n")
    ps:write("      Write-Output 'ERROR:EMPTY'\n")
    ps:write("      exit\n")
    ps:write("    }\n")
    ps:write("    $bytes = [System.IO.File]::ReadAllBytes($filepath)\n")
    ps:write("    if ($bytes.Length -lt 4) {\n")
    ps:write("      Remove-Item $filepath\n")
    ps:write("      Write-Output 'ERROR:INVALID'\n")
    ps:write("      exit\n")
    ps:write("    }\n")
    ps:write("    $magic = [System.Text.Encoding]::ASCII.GetString($bytes[0..3])\n")
    ps:write("    if ($magic -ne 'HM3W') {\n")
    ps:write("      Remove-Item $filepath\n")
    ps:write("      Write-Output 'ERROR:NOTW3X'\n")
    ps:write("      exit\n")
    ps:write("    }\n")
    ps:write("    Write-Output \"SUCCESS:$size\"\n")
    ps:write("  } else {\n")
    ps:write("    Write-Output 'ERROR:NOTCREATED'\n")
    ps:write("  }\n")
    ps:write("} catch {\n")
    ps:write("  Write-Output \"ERROR:$($_.Exception.Message)\"\n")
    ps:write("}\n")
    ps:close()
    
    local ps_cmd = 'powershell -ExecutionPolicy Bypass -File "' .. ps_script .. '"'
    local handle = io.popen(ps_cmd)
    local result = handle:read("*a")
    handle:close()
    
    os.remove(ps_script)
    os.remove(url_file)
    os.remove(path_file)
    
    active_downloads = active_downloads - 1
    
    if result then
        result = result:gsub("[\r\n]", "")
        local real_name = result:match("REALNAME:([^\n]+)")
        if real_name then
            filename = real_name
        end
        
        if result:find("SUCCESS:") then
            local size    = result:match("SUCCESS:(%d+)")
            local size_kb = math.floor(tonumber(size or 0) / 1024)
            return true, string.format("%s (%d KB)", filename, size_kb)
        elseif result:find("ERROR:HTML") then
            return false, "Token expirado"
        elseif result:find("ERROR:EMPTY") then
            return false, "Archivo vacio"
        elseif result:find("ERROR:NOTW3X") then
            return false, "No es archivo W3X"
        elseif result:find("ERROR:INVALID") then
            return false, "Archivo corrupto"
        elseif result:find("ERROR:NOTCREATED") then
            return false, "No se creo el archivo"
        else
            return false, "Error: " .. result
        end
    end
    
    return false, "Sin respuesta de PowerShell"
end

function split_command(text, max_parts)
    local parts = {}
    local count = 0
    for part in text:gmatch("%S+") do
        count = count + 1
        if max_parts and count > max_parts then break end
        table.insert(parts, part)
    end
    return parts
end

function command_download(account, text)
    local args         = split_command(text, 2)
    local url          = args[1]
    local force_option = args[2]
    
    if not url then
        api.message_send_text(account.name, message_type_error, nil, "Uso: /dl <url> [force]")
        return -1
    end
    
    local context = get_user_context(account)
    if DOWNLOAD_CONFIG.allowed_contexts ~= "both" and DOWNLOAD_CONFIG.allowed_contexts ~= context then
        api.message_send_text(account.name, message_type_error, nil, "Solo se puede usar en: " .. DOWNLOAD_CONFIG.allowed_contexts)
        return -1
    end
    
    local domain = extract_domain_from_url(url)
    api.message_send_text(account.name, message_type_info, nil, 
        "Descargando desde: " .. (domain or "?") .. " [Admin]")
    
    local force          = (force_option == "force")
    local success, message = download_file_secure(url, nil, force)
    
    if success then
        api.message_send_text(account.name, message_type_info, nil, "Descarga exitosa:")
        api.message_send_text(account.name, message_type_info, nil, message)
        --api.message_send_text(account.name, message_type_info, nil, 
        --    "Ubicacion: " .. DOWNLOAD_CONFIG.download_directory)
    else
        api.message_send_text(account.name, message_type_error, nil, "Error: " .. message)
    end
    
    return 0
end

function command_dllist(account, text)
    local context = get_user_context(account)
    if DOWNLOAD_CONFIG.allowed_contexts ~= "both" and DOWNLOAD_CONFIG.allowed_contexts ~= context then
        api.message_send_text(account.name, message_type_error, nil, "Solo se puede usar en: " .. DOWNLOAD_CONFIG.allowed_contexts)
        return -1
    end
    
    local files      = {}
    local total_size = 0
    
    local cmd = 'powershell -Command "Get-ChildItem -Path \'' .. DOWNLOAD_CONFIG.download_directory .. '\' -File | ForEach-Object { Write-Output ($_.Name + \'|\' + $_.Length) }"'
    local handle = io.popen(cmd)
    
    if handle then
        for line in handle:lines() do
            if line and line ~= "" then
                local name, size_str = line:match("(.+)|(%d+)")
                if name and size_str then
                    local size = tonumber(size_str) or 0
                    table.insert(files, {name = name, size = size})
                    total_size = total_size + size
                end
            end
        end
        handle:close()
    end
    
    if #files > 0 then
        local total_mb = math.floor(total_size / (1024 * 1024))
        api.message_send_text(account.name, message_type_info, nil, 
            string.format("=== %d archivos (%d MB) ===", #files, total_mb))
        
        for i, file in pairs(files) do
            if file.size > 1024 * 1024 then
                local mb = string.format("%.2f", file.size / (1024 * 1024))
                api.message_send_text(account.name, message_type_info, nil, 
                    string.format("%d. %s (%s MB)", i, file.name, mb))
            else
                local kb = math.floor(file.size / 1024)
                api.message_send_text(account.name, message_type_info, nil, 
                    string.format("%d. %s (%d KB)", i, file.name, kb))
            end
        end
    else
        api.message_send_text(account.name, message_type_info, nil, "Sin archivos")
    end
    
    return 0
end

function command_dlconfig(account, text)
    
    api.message_send_text(account.name, message_type_info, nil, "=== CONFIG ===")
    api.message_send_text(account.name, message_type_info, nil, 
        "Dir: " .. DOWNLOAD_CONFIG.download_directory)
    api.message_send_text(account.name, message_type_info, nil, 
        "Max: " .. math.floor(DOWNLOAD_CONFIG.max_file_size / (1024 * 1024)) .. " MB")
    api.message_send_text(account.name, message_type_info, nil, 
        "Activas: " .. active_downloads .. "/" .. DOWNLOAD_CONFIG.max_concurrent_downloads)
    
    return 0
end

-- ============================================================================
-- CLEANUP DE ARCHIVOS TEMPORALES (al iniciar)
-- Borra .ps1 y .txt huerfanos que pudieron quedar de descargas fallidas
-- ============================================================================
function cleanup_temp_download_files()
    local dir = DOWNLOAD_CONFIG.download_directory
    if not dir or dir == "" then return 0 end
    
    -- Patrones a limpiar (NO toca .w3x ni .w3m)
    local patterns = {
        "dl_*.ps1",
        "head_*.ps1",
        "temp_url_*.txt",
        "temp_path_*.txt",
        "head_url_*.txt",
    }
    
    local total_removed = 0
    for _, pattern in ipairs(patterns) do
        local cmd = 'del /Q "' .. dir .. pattern .. '" 2>nul'
        os.execute(cmd)
        total_removed = total_removed + 1
    end
    
    return total_removed
end

function download_api_init()
    -- Aqui se leen las CONF_* porque main() (que llama a download_api_init)
    -- corre DESPUES de que todos los archivos lua estan cargados,
    -- incluyendo config.lua
    DOWNLOAD_CONFIG.allowed_domains          = CONF_DOWNLOAD_DOMAINS
    DOWNLOAD_CONFIG.download_directory       = CONF_MAPS_DIRECTORY
    DOWNLOAD_CONFIG.max_file_size            = CONF_DOWNLOAD_MAX_SIZE
    DOWNLOAD_CONFIG.allowed_extensions       = CONF_DOWNLOAD_EXTENSIONS
    DOWNLOAD_CONFIG.max_concurrent_downloads = CONF_DOWNLOAD_MAX_CONCURRENT
    DOWNLOAD_CONFIG.cleanup_on_init          = CONF_DOWNLOAD_CLEANUP_ON_INIT
    
    os.execute('if not exist "' .. DOWNLOAD_CONFIG.download_directory .. '" mkdir "' .. DOWNLOAD_CONFIG.download_directory .. '"')
    active_downloads = 0
    
    -- Limpiar archivos temporales huerfanos al iniciar
    if DOWNLOAD_CONFIG.cleanup_on_init then
        cleanup_temp_download_files()
        INFO("[DOWNLOAD-API] Limpieza de temporales ejecutada")
    end
    
    local ps_test   = io.popen('powershell -Command "Write-Output test"')
    local ps_result = ps_test:read("*a")
    ps_test:close()
    
    if not ps_result or not ps_result:find("test") then
        ERROR("[DOWNLOAD-API] PowerShell no disponible")
        return false
    end
    
    INFO("[DOWNLOAD-API] Inicializado OK")
    return true
end
