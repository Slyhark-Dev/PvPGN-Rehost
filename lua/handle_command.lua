--[[
    Copyright (C) 2026 HarpyWar (harpywar@gmail.com)
    
    This file is a part of the PvPGN Project http://pvpgn.pro
    Licensed under the same terms as Lua itself.
]]--


-- List of available lua commands
--  (To create a new command - create a new file in directory "commands")
local lua_command_table = {
    [1] = {
        ["/help"] = command_menu,
        ["/w3motd"] = command_w3motd,
        
        -- Quiz
        ["/quiz"] = command_quiz,
        
        -- GHost
        ["/start"] = command_start,
        ["/botstats"] = command_botstats,
        ["/rehost"] = command_rehost,
        ["/unhost"] = command_unhost,
        ["/upload"] = command_upload,
        
        ["/dl"] = command_download,
        ["/dlconfig"] = command_dlconfig,
        ["/dltest"] = command_dltest,
        -- Inspector (diagnostico temporal)
        ["/inspect"] = command_inspect,
        ["/slots"] = command_slots,
    },
    [8] = {
        ["/dllist"] = command_dllist,
        ["/redirect"] = command_redirect,
        ["/botimmunity"] = command_botimmunity,
    },
}

-- Global function to handle commands
--   ("return 1" from a command will allow next C++ code execution)
function handle_command(account, text)
    -- api.message_send_text(account.name, message_type_info, nil, 
        -- "CG valor: " .. tostring(account_get_auth_command_groups(account.name)))
    -- find command in table
    for cg,cmdlist in pairs(lua_command_table) do
        for cmd,func in pairs(cmdlist) do
            local text_cmd = string.lower(text):match("^(%S+)") or ""
            if text_cmd == string.lower(cmd) then
                
                -- check if command group is in account commandgroups
                if math_and(account_get_auth_command_groups(account.name), cg) == 0 then
                    api.message_send_text(account.name, message_type_error, account.name, localize(account.name, "This command is reserved for admins."))
                    return -1
                end
                
                return func(account, text) 
            end
        end
    end
    return 1
end


-- Executes before executing any command
-- "return 0" stay with flood protection
-- "return 1" allow ignore flood protection
-- "return -1" will prevent next command execution silently
function handle_command_before(account, text)
    if not BOT_MANAGER.system_immunity_users then return 0 end
    
    for _, username in pairs(BOT_MANAGER.system_immunity_users) do
        if (username == account.name) then return 1 end
    end
    
    for _, bot in pairs(BOT_MANAGER.bot_list) do
        if (bot == account.name) then return 1 end
    end
    
    return 0
end


-- Split command to arguments, 
--  index 0 is always a command name without a slash 
--  return table with arguments
function split_command(text, args_count)
    local count = args_count
    local result = {}
    local tmp = ""
    
    -- remove slash from the command
    if not string:empty(text) then
        text = string.sub(text, 2)
    end

    i = 0
    -- split by space
    for token in string.split(text) do
        if not string:empty(token) then 
            if (i < count) then
                result[i] = token 
                i = i + 1
            else
                if not string:empty(tmp) then
                    tmp = tmp .. " "
                end
                tmp = tmp .. token
            end
        end
    end
    -- push remaining text at the end
    if not string:empty(tmp) then
        result[count] = tmp
    end
    return result
end
