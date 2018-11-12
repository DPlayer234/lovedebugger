--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local debug = require "debug"
	local assert, setmetatable, next, type, ipairs, pairs, pcall, rawset, rawequal, setfenv, getfenv = assert, setmetatable, next, type, ipairs, pairs, pcall, rawset, rawequal, setfenv, getfenv

	DBG.MONITOR_UNDEFINED = -1
	DBG.MONITOR_CONSTANT  =  0
	DBG.MONITOR_DYNAMIC   =  1

	local MONITOR_FILE_NAME = "ENV.txt" --#const

	-- The monitored environment and output file
	local monitorEnvProxy, monitorEnv, monitorFile

	-- Monitors changes to the set global environment.
	-- Direct access (e.g. _G.myGlobalVar) are ignored.
	function DBG.monitorGlobal(options)
		local writeToInfo = love.filesystem.getInfo(MONITOR_FILE_NAME)
		if not writeToInfo then
			love.filesystem.write(MONITOR_FILE_NAME, "")
		elseif writeToInfo.type ~= "file" then
			error(MONITOR_FILE_NAME + " exists but is not a file.")
		end

		options = options and DBG._mapTable(options, function(k, v)
			if v ~= DBG.MONITOR_UNDEFINED and v ~= DBG.MONITOR_CONSTANT and v ~= DBG.MONITOR_DYNAMIC then
				error("'options' can only contain DBG.MONITOR_* enums as values.")
			end

			return v
		end) or {}

		DBG.stopMonitorGlobal(false)
		DBG._completeMonitorOptions(options, DBG._envRoot)
		local file = love.filesystem.newFile(MONITOR_FILE_NAME, "a")

		DBG.printColor(DBG.color.red, ("\tNow monitoring '%s' for changes.\nWill be logged to '%s'."):format(DBG._envRootName, MONITOR_FILE_NAME))

		DBG._setMonitorEnv(DBG._envRoot, file, options)
	end

	-- Completes the options for monitoring based on another table
	function DBG._completeMonitorOptions(options, with)
		for k, v in pairs(with) do
			if options[k] == nil then
				options[k] = DBG.MONITOR_CONSTANT
			end
		end

		setmetatable(options, {
			__index = function()
				return DBG.MONITOR_UNDEFINED
			end
		})
	end

	-- Sets the monitoring environment
	function DBG._setMonitorEnv(env, file, options)
		local traceback = debug.traceback

		local envProxy = DBG._cloneObject(env)
		setmetatable(envProxy, debug.getmetatable(env))

		for k, v in pairs(env) do
			rawset(env, k, nil)
		end

		monitorFile     = file
		monitorEnvProxy = envProxy
		monitorEnv      = env

		if env == DBG._envRoot then
			DBG.setEnv(envProxy, DBG._envRootName)
		end

		setmetatable(env, {
			__index = function(t, k)
				if options[k] < DBG.MONITOR_CONSTANT and DBG._notInDebugger() then
					local message = (":Undefined global '%s' was attempted to be accessed!"):format(k)
					DBG.printColor(DBG.color.blue, message)
					file:write(traceback(message, 2) .. "\n\n")
					file:flush()
				end

				return envProxy[k]
			end,
			__newindex = function(t, k, v)
				if (options[k] < DBG.MONITOR_CONSTANT or (options[k] == DBG.MONITOR_CONSTANT and envProxy[k] ~= nil)) and DBG._notInDebugger() then
					local message = (":Non-dynamic global '%s' was set to: %s"):format(k, v)
					DBG.printColor(DBG.color.blue, message)
					file:write(traceback(message, 2) .. "\n\n")
					file:flush()
				end

				envProxy[k] = v
			end
		})
	end

	-- Stops monitoring the global environment
	function DBG.stopMonitorGlobal(log)
		if DBG.doesMonitorGlobal() then
			monitorFile:close()
			monitorFile = nil

			if log or log == nil then
				DBG.printColor(DBG.color.red, "\tNo longer monitoring the global environment for changes.")
			end

			setmetatable(monitorEnv, debug.getmetatable(monitorEnvProxy))
			for k, v in pairs(monitorEnvProxy) do
				rawset(monitorEnv, k, v)
			end

			if monitorEnvProxy == DBG._envRoot then
				DBG.setEnv(monitorEnv, DBG._envRootName)
			end

			monitorEnvProxy, monitorEnv = nil
		end
	end

	function DBG.doesMonitorGlobal()
		return monitorFile ~= nil
	end

	-- Views locals at a certain point in code execution
	function DBG.viewLocals(src, inLine, var, key)
		if src == nil then
			debug.sethook()
			DBG.printColor(DBG.color.blue, "Disabled local viewer.")
		else
			local getinfo = debug.getinfo
			local getlocal = debug.getlocal
			local sethook = debug.sethook

			local storage, storeKey
			if key == nil then
				storage = DBG._envRoot
				storeKey = var or "_local"
			else
				storage = var
				storeKey = key or "_local"
			end

			if type(src) == "function" then
				src = getinfo(src, "S").source
			elseif type(src) == "string" then
				src = "@"..src
			else
				error("Argument #1 to DBG.viewLocals(src, inLine, var, key) must be a function or string!")
			end
			if type(inLine) ~= "number" then
				DBG.printError("You need to pass the line to check in!")
				return
			end

			DBG.printColor(DBG.color.blue, "Enabled local viewer.\nAny future passes on that line will now write a table!")

			sethook(function(event, line)
				if line == inLine and src == getinfo(2, "S").source then
					local locals = {}
					local i = 1
					local n, v = getlocal(2, i)
					while n or v do
						locals[n] = v
						i = i + 1
						n, v = getlocal(2, i)
					end
					storage[storeKey] = locals
				end
			end, "l")
		end
	end

	-- Gets the variables on the stack
	function DBG.getStack(a, b)
		local thread, stack
		if a ~= nil then
			if type(a) == "thread" then
				-- Coroutine
				thread, stack = a, b
			else
				stack = a
			end
		end

		assert(stack == nil or type(stack) == "number", "Argument #1 to DBG.getStack([thread], stack) must be a number or nil.")

		local getinfo, getlocal
		if thread then
			stack = stack or 0

			getinfo = function(depth, what)
				return debug.getinfo(thread, depth, what)
			end

			getlocal = function(depth, index)
				return debug.getlocal(thread, depth, index)
			end
		else
			stack = (stack or 1) + 1

			getinfo = debug.getinfo
			getlocal = debug.getlocal
		end

		local var = {}

		local function nonNilValue(value)
			return rawequal(value, nil) and DBG.fakeNil or value
		end

		local multiLocal = { __index = { type = "multiLocal" } }

		local i=0
		local stackInfo = getinfo(stack, "fn")
		while stackInfo do
			local this = {
				["**Function:"] = stackInfo.func,
				["**Function Name:"] = stackInfo.name
			}
			i = i + 1
			var[i] = this

			local l = 1
			while true do
				local name, value = getlocal(stack, l)
				if not name then break end
				if name:find("^%(") then
					if rawequal(this[name], nil) then
						this[name] = nonNilValue(value)
					elseif getmetatable(this[name]) ~= multiLocal then
						this[name] = setmetatable({ this[name] }, multiLocal)
					else
						this[name][#this[name]+1] = nonNilValue(value)
					end
				else
					this[name] = nonNilValue(value)
				end
				l = l + 1
			end

			stack = stack + 1
			stackInfo = getinfo(stack, "fn")
		end

		return var
	end

	DBG.addSource()
end
