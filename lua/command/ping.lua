--[[
	Copyright (C) 2014 HarpyWar (harpywar@gmail.com)
	
	This file is a part of the PvPGN Project http://pvpgn.pro
	Licensed under the same terms as Lua itself.
]]--

function command_ping(account, text)
	-- allow warcraft 3 client only
	if not (account.clienttag == CLIENTTAG_WAR3XP) then
		return 1
	end
	-- En lobby/partida: usar código original de GHost++
	if account.game_id and config.ghost then
		return gh_command_ping(account, text)
	end
	
	-- En canal: usar comando latency nativo
	if not account.game_id then
		-- Ejecutar el comando /latency nativo del servidor
		return api.command_latency(account, text)
	end
	return 1
end