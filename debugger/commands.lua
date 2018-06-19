--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local debug = require "debug"

	local assert, type, next = assert, type, next
	local string, table = string, table

	DBG._commands = {}

	-- Creates a new command
	function DBG.newCommand(name, args, func)
		assert(type(name) == "string", "Argument #1 to DBG.newCommand(name, args, func) must be a string!")
		assert(type(args) == "string", "Argument #2 to DBG.newCommand(name, args, func) must be a string!")
		assert(type(func) == "function" or debug.getmetatable(func) and rawget(debug.getmetatable(func), "__call"), "Argument #3 to DBG.newCommand(name, args, func) must be callable!")

		if DBG._commands[name] == nil then
			DBG._commands[name] = { name = name, alias = {} }
		elseif DBG._commands[name].name ~= name then
			error(":Cannot add alternative syntax to alias '" .. DBG._tostring(name) .. "' of command '" .. DBG._tostring(DBG._commands[name].name) .. "'.")
		end
		local c = {
			args = args,
			func = func
		}
		DBG._commands[name][#DBG._commands[name]+1] = c
	end

	-- Aliases a command
	function DBG.aliasCommand(name, as)
		assert(type(name) == "string", "Argument #1 to DBG.aliasCommand(name, as) must be a string!")
		assert(type(as)   == "string", "Argument #2 to DBG.aliasCommand(name, as) must be a string!")

		assert(DBG._commands[name] ~= nil, ":Command '"..name.."' doesn't exist!")
		assert(DBG._commands[as] == nil, ":Command '"..as.."' exists already.")

		DBG._commands[as] = DBG._commands[name]
		DBG._commands[name].alias[#DBG._commands[name].alias+1] = as
	end

	-- Adding some default commands!
	DBG.newCommand("index", "" , DBG.allowFunctionIndex)
	DBG.newCommand("index", "b", DBG.allowFunctionIndex)

	DBG.newCommand("global", "" , DBG.monitorGlobal)
	DBG.newCommand("global", "s", DBG.monitorGlobal)

	DBG.newCommand("local", "sn", DBG.viewLocals)
	DBG.newCommand("local", "", DBG.viewLocals)

	-- Screen Clearing
	DBG.newCommand("clear", "", DBG.clear)

	-- Quick navigation
	DBG.newCommand("to", "", function()
		DBG._envPath = "_G"
		DBG._yScroll = 1
		return ":Moved to "..DBG._envPath.."."
	end)

	DBG.newCommand("to", "s", function(s)
		DBG._envPath = s:gsub("%.([^%[%]\"'%(%)%{%}%.]*)", function(t) return string.format("[%q]", t) end)
		DBG._yScroll = 1
		return ":Moved to " .. DBG._envPath .. "."
	end)

	DBG.newCommand("loc", "", function() return ":Currently at " .. DBG._nicerEnvPath(DBG._envPath) end)

	-- Help about commands
	DBG.newCommand("help", "", function()
		local all = {}
		for k,v in next, DBG._commands do
			if k == v.name then
				all[#all+1] = "\t"..k
			end
		end
		table.sort(all)
		table.insert(all, 1, "All available commands:")
		return table.concat(all, "\n")
	end)

	DBG.newCommand("help", "s", function(s)
		local cmd = DBG._commands[s]
		if cmd then
			local name = cmd.name
			local all = {}
			local replace = {
				s = "<string>",
				n = "<number>",
				b = "<boolean>"
			}

			for i=1, #cmd do
				local v = cmd[i]
				if v.args == "" then
					all[#all+1] = "\t/"..name
				else
					local x = v.args:gsub("", " ")
					all[#all+1] = "\t/" .. name .. " " .. x:sub(2, #x-1):gsub(".", replace)
				end
			end

			table.sort(all)
			table.insert(all, 1, "[[ Help for '"..name.."' ]]\nSyntax:")
			if #cmd.alias > 0 then
				table.insert(all, "Aliases:")
				for i=1, #cmd.alias do
					table.insert(all, "\t/"..cmd.alias[i].." ...")
				end
			end

			return table.concat(all, "\n")
		elseif s == "me" then
			return ":You might need professional help if you ask a debugging tool..."
		else
			return ":Unknown command."
		end
	end)

	DBG.addSource()
end
