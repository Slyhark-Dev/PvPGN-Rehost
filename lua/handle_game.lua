--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--


-- Global function to handle game create
function handle_game_create(game)
    --for i,j in pairs(game) do
    --    api.message_send_text(game.owner, message_type_info, game.owner, i.." = "..j)
    --end
end

-- Global function to handle user join to game
function handle_game_userjoin(game, account)
    if config.ghost then
        gh_handle_game_userjoin(game, account)
    end
    
    -- INTEGRACIÓN SISTEMA NUEVO
    bot_handle_game_userjoin(game, account)
end


-- Global function to handle user left from game
function handle_game_userleft(game, account)
    -- INTEGRACIÓN SISTEMA NUEVO
    bot_handle_game_userleft(game, account)
    
    --for username in string.split(str,",")  do
    --    if (account.name ~= username) then
    --        api.message_send_text(username, message_type_whisper, nil, "Bye ".. account.name)
    --    end
    --end
end

-- Global function to handle game end
function handle_game_end(game)

end

-- Global function to handle game report
function handle_game_report(game)

    --for i,j in pairs(game) do
    --    api.message_send_text("harpywar", message_type_info, game.owner, i.." = "..j)
    --    api.message_send_text(game.owner, message_type_info, game.owner, i.." = "..j)
    --end
    
    --DEBUG(game.last_access)
end

-- Global function to handle game destroy
function handle_game_destroy(game)
    DEBUG("Game destroyed: " .. game.name .. " owner: " .. game.owner)
    bot_game_remove(game.id)
    
    DEBUG("[DEBUG] Buscando holds activos...")
    if rehost_holds and next(rehost_holds) then
        for username, hold_data in pairs(rehost_holds) do
            DEBUG("[DEBUG] Hold: " .. username .. " | status: " .. (hold_data.status or "nil") .. " | bot: " .. (hold_data.bot_name or "nil"))
            
            -- CASO 1: Partida del bot se destruye (timeout, etc.)
            if hold_data.status == "game_active" and hold_data.bot_name == game.owner then
                local cfg_file = "C:\\PVPGN\\mapcfgs\\" .. username .. ".cfg"
                if file_exists(cfg_file) then
                    os.remove(cfg_file)
                    DEBUG("[CFG-CLEANUP] Archivo eliminado por timeout bot: " .. cfg_file)
                end
                
                rehost_holds[username] = nil
                DEBUG("[REHOST] Hold liberado para: " .. username .. " (bot " .. game.owner .. " destruyó partida)")
            end
            
            -- CASO 2: Usuario destruye su propia partida recreada (caso normal)
            if hold_data.status == "game_active" and username == game.owner and hold_data.game_name == game.name then
                local cfg_file = "C:\\PVPGN\\mapcfgs\\" .. username .. ".cfg"
                if file_exists(cfg_file) then
                    os.remove(cfg_file)
                    DEBUG("[CFG-CLEANUP] Archivo eliminado: " .. cfg_file)
                end
                
                rehost_holds[username] = nil
                DEBUG("[REHOST] Hold liberado para: " .. username .. " (partida recreada destruida)")
            end
        end
    else
        DEBUG("[DEBUG] No hay holds activos")
    end

    -- LIMPIAR UPLOAD HOLDS por bot o por usuario
    if upload_holds and next(upload_holds) then
        for username, hold_data in pairs(upload_holds) do
            -- Partida del bot destruida (timeout) -> liberar hold del usuario
            if hold_data.status == "game_active" and hold_data.bot_name == game.owner then
                release_upload_hold(username)
                DEBUG("[UPLOAD] Hold liberado para: " .. username .. " (bot " .. game.owner .. " destruyo partida)")
            end
            -- Partida del usuario destruida -> liberar hold
            if hold_data.status == "game_active" and username == game.owner and hold_data.game_name == game.name then
                release_upload_hold(username)
                DEBUG("[UPLOAD] Hold liberado para: " .. username .. " (partida recreada destruida)")
            end
            -- Partida original del upload destruida durante waiting/cancelled
            if (hold_data.status == "waiting_upload" or hold_data.status == "cancelled") 
               and tostring(hold_data.game_id) == tostring(game.id) then
                release_upload_hold(username)
                DEBUG("[UPLOAD] Hold liberado para: " .. username .. " (partida original destruida)")
            end
        end
    end
    
    cfg_handle_host_exit(game.owner)
    upload_handle_host_exit(game.owner, game.id)
    lobby_track_remove(game.id)
end

-- Global function to handle game status
function handle_game_changestatus(game)
    --api.message_send_text(game.owner, message_type_info, nil, "Change status of the game to ".. game.status)

    -- Liberar el hold de /upload cuando el lobby deja de serlo y pasa a partida
    -- en curso. Valores de game.status: 0=started, 1=full, 2=open, 3=loaded,
    -- 4=done. Hasta ahora el hold solo se soltaba en handle_game_destroy, o sea
    -- recien cuando salia el ultimo jugador; en partidas largas el usuario
    -- quedaba bloqueado toda la partida sin poder volver a usar /upload.
    if not game or not game.id then return end

    local status = tostring(game.status or "")
    if status ~= "0" and status ~= "3" and status ~= "4" then
        return
    end

    local current_game_id = tonumber(game.id)
    if not current_game_id then return end

    if upload_holds and next(upload_holds) then
        for username, hold_data in pairs(upload_holds) do
            if hold_data.status == "game_active"
               and tonumber(hold_data.new_game_id) == current_game_id then
                release_upload_hold(username)
                DEBUG("[UPLOAD] Hold liberado para: " .. username ..
                      " (partida " .. tostring(game.id) .. " inicio, status " .. status .. ")")
            end
        end
    end

    -- Mismo criterio para /rehost. El .cfg se borra aca porque el bot ya lo
    -- consumio al cargar el mapa y crear el lobby; con la partida iniciada no
    -- se vuelve a leer.
    if rehost_holds and next(rehost_holds) then
        for username, hold_data in pairs(rehost_holds) do
            if hold_data.status == "game_active"
               and tonumber(hold_data.new_game_id) == current_game_id then
                local cfg_file = "C:\\PVPGN\\mapcfgs\\" .. username .. ".cfg"
                if file_exists(cfg_file) then
                    os.remove(cfg_file)
                    DEBUG("[CFG-CLEANUP] Archivo eliminado: " .. cfg_file)
                end

                rehost_holds[username] = nil
                DEBUG("[REHOST] Hold liberado para: " .. username ..
                      " (partida " .. tostring(game.id) .. " inicio, status " .. status .. ")")
            end
        end
    end
end
