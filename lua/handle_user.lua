--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--


function handle_user_whisper(account_src, account_dst, text)
    --DEBUG(account_src.name.."->"..account_dst.name.. ": ".. text)
    --return 1;
end

function handle_user_login(account)
    if (config.ghost) then
        gh_handle_user_login(account)
    end
    
    -- INICIALIZACIÓN DE BOTS SISTEMA NUEVO
    bot_handle_user_login(account)
    
    -- send SID_REQUIREDWORK
    --if account.archtag == ARCHTAG_WINX86 then
    --    api.client_requiredwork(account.name, "IX86ExtraWork.mpq")
    --end
    
    --DEBUG(account.name.." logged in")
    --return 1;
end

function handle_user_disconnect(account)
    DEBUG("User disconnect: " .. account.name)
    -- VERIFICAR SI HAY REHOST ACTIVO PARA ESTE USUARIO
    cfg_handle_host_exit(account.name)
    -- VERIFICAR SI HAY UPLOAD ACTIVO PARA ESTE USUARIO
    upload_handle_host_exit(account.name, nil)
end

function handle_user_icon(account, iconinfo)
    --TRACE("iconinfo"..iconinfo)
    --return iconinfo
end