--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--

function handle_channel_message(channel, account, text, message_type)
    if config.quiz and channel.name == config.quiz_channel then
        quiz_handle_message(account.name, text)
    end

    --DEBUG(text)
    --return 1
end

function handle_channel_userjoin(channel, account)
    -- TEST TEMPORAL
    INFO("[TEST] Usuario " .. account.name .. " entró a canal " .. channel.name)
    
    -- VERIFICACIÓN DE TIMING: BOT_MANAGER debe estar inicializado
    if not BOT_MANAGER then
        INFO("[DEBUG] BOT_MANAGER no inicializado aún, saltando lógica")
        return
    end

    -- LÓGICA: Trackear bots disponibles + limpieza automática de asignaciones
    local target = bot_get_target_channel()
    
    if string.lower(channel.name) == string.lower(target) then
        local bot_list = bot_get_bot_list()
        for _, bot_name in pairs(bot_list) do  -- CORREGIDO: _, bot_name
            if account.name == bot_name then
                -- NUEVA: Limpiar asignación si bot regresa (trabajo completado o .rejoin)
                local was_assigned = bot_handle_channel_return(bot_name)
                
                -- Agregar como disponible
                bot_add_to_available(bot_name)
                
                if was_assigned then
                    DEBUG("[BOT-MANAGER] Bot regresó y fue limpiado: " .. bot_name)
                else
                    DEBUG("[BOT-MANAGER] Bot disponible: " .. bot_name)
                end
                break
            end
        end
    end
    
    --DEBUG(account.name.." joined "..channel.name)
end

function handle_channel_userleft(channel, account)
    -- LÓGICA: Remover de disponibles + detectar cuando bot empieza a trabajar
    if channel.name == bot_get_target_channel() then
        bot_remove_from_available(account.name)
        
        -- Verificar si era un bot asignado que salió (confirmación de trabajo)
        bot_handle_channel_exit(account.name)
    end

    --DEBUG(account.name.." left "..channel.name)
end