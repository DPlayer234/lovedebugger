--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local debug = require "debug"

	local assert, type, next, tonumber, pcall, unpack, next = assert, type, next, tonumber, pcall, unpack, next
	local string, table = string, table

	local commands = {}

	-- Creates a new command
	function DBG.newCommand(name, args, help, func)
		assert(type(name) == "string", "Argument #1 to DBG.newCommand(...) must be a string!")
		assert(type(args) == "string", "Argument #2 to DBG.newCommand(...) must be a string!")
		if func == nil then help, func = "---", help end
		assert(type(help) == "string", "Argument #3 to DBG.newCommand(...) must be a string!")
		assert(type(func) == "function" or debug.getmetatable(func) and rawget(debug.getmetatable(func), "__call"), "Argument #4 to DBG.newCommand(...) must be callable!")

		if commands[name] == nil then
			commands[name] = { name = name, alias = {} }
		elseif commands[name].name ~= name then
			error(":Cannot add alternative syntax to alias '" .. DBG._tostring(name) .. "' of command '" .. DBG._tostring(commands[name].name) .. "'.")
		end
		local c = {
			args = args,
			help = help,
			func = func
		}
		commands[name][#commands[name]+1] = c
	end

	-- Aliases a command
	function DBG.aliasCommand(name, as)
		assert(type(name) == "string", "Argument #1 to DBG.aliasCommand(name, as) must be a string!")
		assert(type(as)   == "string", "Argument #2 to DBG.aliasCommand(name, as) must be a string!")

		assert(commands[name] ~= nil, ":Command '"..name.."' doesn't exist!")
		assert(commands[as] == nil, ":Command '"..as.."' exists already.")

		commands[as] = commands[name]
		commands[name].alias[#commands[name].alias+1] = as
	end

	-- Executes Lua code as the console would
	function DBG.executeLuaCode(luaCode)
		-- Attempting return to print that on the screen
		DBG.printLog(">> " .. luaCode)

		local r = { DBG.loadString("return " .. luaCode) }
		if not r[1] then
			r = { DBG.loadString(luaCode) }
		end
		if r[1] then
			r = { pcall(r[1]) }
		end
		if r[1] == true then
			local max = 0
			for i,v in next, r do if i > max then max = i end end
			if max > 1 then
				r[1] = ":Return values"
				for i=2, max do
					local v = r[i]
					r[i] = "[" .. DBG._tostring(i-1) .. "] (" .. DBG._validateUtf8(DBG.typeReal(v)) .. ") " .. DBG._validateUtf8(DBG._toSingleLine(DBG._toDisplayString(v)))
				end
				if #r > 0 then
					DBG.printLog(table.concat(r, "\n\t"))
				end
			end
		else
			DBG.printError(":" .. DBG._tostring(r[2]))
		end
	end

	-- Executes a command
	function DBG.executeCommand(command)
		local args = {}
		local inString, string = false, nil
		for match in command:gmatch("%S+") do
			if inString then
				if match:find("\"$") then
					args[#args+1] = string .. " " .. match:sub(1, #match-1)
					inString, string = false, nil
				else
					string = string .. " " .. match
				end
			elseif match:find("^\".*[^\"]$") then
				inString, string = true, match:sub(2, #match)
			else
				args[#args+1] = match
			end
		end

		local one = table.remove(args, 1)
		local command = commands[one:sub(2, #one)]
		if command then
			local pattern = "^"
			for i=1, #args do
				local v = args[i]
				if tonumber(v) then
					pattern = pattern.."[bns]"
				elseif v == "true" or v == "false" then
					pattern = pattern.."[bs]"
				else
					pattern = pattern.."s"
				end
			end
			pattern = pattern.."$"

			local this
			for i=1, #command do
				local v = command[i]
				if pattern == "" then
					if v.args == "" then
						this = v
						break
					end
				elseif v.args:find(pattern) then
					this = v
					break
				end
			end

			if this then
				local i = 0
				for c in this.args:gmatch(".") do
					i = i + 1
					if c == "n" then
						args[i] = tonumber(args[i])
					elseif c == "b" then
						args[i] = args[i] ~= "false" and args[i] ~= "0"
					end
				end

				local s,out = pcall(this.func, unpack(args))
				if s then
					DBG.printLog(out or ":Executed.")
				else
					DBG.printError(":" .. DBG._tostring(out))
				end
			else
				DBG.printError(":Incorrect arguments.")
			end
		else
			DBG.printError(":Unknown command. Add commands with DBG.newCommand(name, args, function)")
		end
	end

	-- Adding some default commands!
	DBG.newCommand("index", "" , "Enables function indexing.", DBG.allowFunctionIndex)
	DBG.newCommand("index", "b", "Enables function indexing, indicating whether or not pretty names are wanted.", DBG.allowFunctionIndex)

	DBG.newCommand("global", "" , "Enables env monitoring.", DBG.monitorGlobal)

	DBG.newCommand("local", "sn", "Enables local viewing in a specific file and line number.", DBG.viewLocals)
	DBG.newCommand("local", "", "Disables local viewing.", DBG.viewLocals)

	-- Screen Clearing
	DBG.newCommand("clear", "", "Clears the output.", DBG.clear)

	-- Quick navigation
	DBG.newCommand("to", "", "Navigates to the environment root.", function()
		DBG.navigateTo(DBG._envRootName)
		return ":Moved to " .. DBG.getNiceEnvPath() .. "."
	end)

	DBG.newCommand("to", "s", "Navigates to a specific table.", function(s)
		DBG.navigateTo(s)
		return ":Moved to " .. DBG.getNiceEnvPath() .. "."
	end)

	DBG.newCommand("loc", "", "Prints the current navigation path.", function() return ":Currently at " .. DBG.getNiceEnvPath() end)

	local function tableIt(names, maxLength)
		local tabled = {}
		local spacing = maxLength + 2
		for i=1, #names, 3 do
			local n0 = names[i]
			local n1 = names[i + 1]
			local n2 = names[i + 2]

			local res = "\t" .. n0
			if n1 then res = res .. (" "):rep(spacing - #n0) .. n1 end
			if n2 then res = res .. (" "):rep(spacing - #n1) .. n2 end
			tabled[#tabled + 1] = res
		end

		return table.concat(tabled, "\n")
	end

	-- Help about commands
	DBG.newCommand("help", "", "Displays a list of available commands.", function()
		local names = {}
		local maxLength = 0
		for k, v in next, commands do
			if k == v.name then
				names[#names + 1] = k
				maxLength = math.max(#k, maxLength)
			end
		end
		table.sort(names)

		return ":All available commands\n" .. tableIt(names, maxLength)
	end)

	DBG.newCommand("help", "s", "Displays help for a specific command.", function(s)
		local cmd = commands[s]
		if cmd then
			local name = cmd.name
			local all = { ":Help for '"..name.."'" }
			local replace = {
				s = "<string>",
				n = "<number>",
				b = "<boolean>"
			}

			for i=1, #cmd do
				local v = cmd[i]
				if v.args == "" then
					all[#all + 1] = "/" .. name
				else
					local x = v.args:gsub("", " ")
					all[#all + 1] = "/" .. name .. " " .. x:sub(2, #x-1):gsub(".", replace)
				end
				all[#all + 1] = "\t" .. v.help
			end

			if #cmd.alias > 0 then
				table.insert(all, ":Aliases")
				local names = {}
				local maxLength = 0
				for i=1, #cmd.alias do
					names[i] = cmd.alias[i]
					maxLength = math.max(#names[i], maxLength)
				end
				table.sort(names)
				table.insert(all, tableIt(names, maxLength))
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
