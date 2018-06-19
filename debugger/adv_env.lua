--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local debug = require "debug"
	local assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal = assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal

	DBG._indexFunctions = false
	DBG._prettyFunctions = false

	-- Up-Value-getter
	function DBG.allowFunctionIndex(prettyNames)
		DBG._indexFunctions = true
		DBG.printColor(DBG.color.red, "\tAllowing the indexing of functions!\nAccess to indexing is only allowed within the command line.")

		local filesystem = require("love.filesystem")
		local isFile = function(path)
			local info = filesystem.getInfo(path)
			return info and info.type == "file"
		end

		local upval = setmetatable({}, {__mode = "kv"})
		local ret = setmetatable({}, {__mode = "kv", __index = function()return{}end})
		local retn = setmetatable({}, {__mode = "kv"})

		local isVarName = function(name)
			return name:find("^[_a-zA-Z][_a-zA-Z0-9]*$") and true
		end

		local getlist = function(f)
			if upval[f] then
				return upval[f]
			else
				local fup = {}

				local i = 1
				local k, v = debug.getupvalue(f, i)
				while k do
					fup[isVarName(k) and k or i] = i
					i = i + 1
					k, v = debug.getupvalue(f, i)
				end

				upval[f] = fup
				return fup
			end
		end

		local funcMeta = {
			__index = function(f, k)
				if DBG.notInDebugger() then error("attempt to index a function value", 2) end

				local fup = getlist(f)

				if k == "___allupvalues" then
					local t = ret[f]
					local _
					for k,v in next, fup do _, t[k] = debug.getupvalue(f, v) end
					return t
				elseif k == "___allupvaluenames" then
					if retn[f] then
						return retn[f]
					else
						local t = {}
						for k,v in next, fup do t[k] = true end
						retn[f] = t
						return t
					end
				elseif k == "___code" then
					if debug.getinfo then
						local info = debug.getinfo(f, "S")
						local source = (info.source or ""):gsub("^@", "")
						if isFile(source) then
							local i = 0
							local codelines = {}
							for line in filesystem.lines(source) do
								i = i + 1
								-- linedefined, lastlinedefined, params
								if i >= info.linedefined then
									codelines[#codelines+1] = line
									if i >= info.lastlinedefined then
										break
									end
								end
							end

							return table.concat(codelines, "\n")
						else
							error("unable to find code file")
						end
					else
						error("Cannot get code... No JIT utils?")
					end
				elseif fup[k] then
					local k, v = debug.getupvalue(f, fup[k])
					return v
				else
					error("attempt to get invalid upvalue", 2)
				end
			end,
			__newindex = function(f, k, v)
				local fup = getlist(f)
				if fup[k] then
					debug.setupvalue(f, fup[k], v)
				else
					error("attempt to set invalid upvalue", 2)
				end
			end,
			--__metatable = false
		}

		if prettyNames and debug.getinfo then
			DBG._prettyFunctions = true

			local amount, bytes = 1, 5
			local hardnames = {
				[DBG.realPrint] = "print"
			}

			local indexed = {
				[package.loaded] = true,
				[package.preload] = true
			}

			local function addName(item, path)
				if indexed[item] or hardnames[item] then return end
				if type(item) == "table" then
					indexed[item] = true
					for k,v in next, item do
						addName(v, path.."."..k)
					end
				elseif type(item) == "function" then
					hardnames[item] = path
					amount = amount + 1
					bytes = bytes + #path
				end
			end

			for i,v in ipairs {
				"assert", "collectgarbage", "dofile", "error", "gcinfo", "getfenv", "getmetatable", "ipairs", "load", "loadfile", "loadstring",
				"module", "newproxy", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "require", "select",
				"setfenv", "setmetatable", "type", "tonumber", "tostring", "unpack", "xpcall",
				"coroutine", "debug", "io", "math", "os", "string", "table", "package"
			} do
				addName(_G[v], v)
			end

			for i,v in ipairs {
				"bit", "jit", "love"
			} do
				local s, r = pcall(require, v)
				if s then
					addName(r, v)
				end
			end

			do
				local ffi = require "ffi"

				addName(ffi, "ffi")
				addName(debug.getmetatable(ffi.new("int")), "<cdata>")
			end

			addName(DBG, DBG._PATH)

			local names = setmetatable({}, {
				__index = function(t, f)
					local v

					local info = debug.getinfo(f, "S")
					local source = (info.source or ""):gsub("^@", "")
					local linedefined = info.linedefined
					if isFile(source) and linedefined then
						local i = 0
						local defined
						for line in filesystem.lines(source) do
							i = i + 1
							-- linedefined, lastlinedefined, params
							if i >= linedefined then
								defined = " "..line.." "
								break
							end
						end
						if defined then
							v = defined:match("%)%-%-%[%[(.-)%]%]")
								or defined:match("[^_a-zA-Z0-9]function%s+([_a-zA-Z][%.%:_a-zA-Z0-9]*)[^_a-zA-Z0-9]")
								or defined:match("[^_a-zA-Z0-9]([_a-zA-Z][%.%:_a-zA-Z0-9]*)%s*=%s*%(*function[^_a-zA-Z0-9]")
							if not v then
								local __tostring = funcMeta.__tostring
								funcMeta.__tostring = nil
								v = DBG._tostring(f):match("0x%x+")
								funcMeta.__tostring = __tostring
							end
						end
					end

					local shortSrc = info.short_src
					local location =
						shortSrc == "[C]" and (" [C]") or
						(" (" .. shortSrc .. ":" .. DBG._tostring(linedefined) .. ")")

					if v or hardnames[f] then
						v = "function: "..(hardnames[f] or v)..location
						if hardnames[f] then hardnames[f] = nil end
					else
						local __tostring = funcMeta.__tostring
						funcMeta.__tostring = nil
						v = DBG._tostring(f) .. location
						funcMeta.__tostring = __tostring
					end

					t[f] = v
					return v
				end,
				__mode = "kv"
			})

			function funcMeta:__tostring()
				return names[self]
			end

			DBG.printColor(DBG.color.blue, "\tAdded " .. DBG._tostring(amount) .. " function names for predefined functions, totalling " .. DBG._tostring(bytes) .. " characters.")
		else
			DBG._prettyFunctions = false
		end

		debug.setmetatable(function() end, funcMeta)
	end

	-- Monitors changes to the global environment
	function DBG.monitorGlobal(writeTo)
		if type(writeTo) ~= "string" then writeTo = "_G (log).txt" end

		DBG.printColor(DBG.color.red, "\tNow monitoring the global environment for changes.\nWill be logged to '"..writeTo.."'.")

		local writeToInfo = love.filesystem.getInfo(writeTo)
		if not writeToInfo then
			love.filesystem.write(writeTo, "")
		elseif writeToInfo.type ~= "file" then
			error("Can only write log to files.")
		end

		local file = love.filesystem.newFile(writeTo, "a")

		local traceback = debug.traceback

		setmetatable(_G, {
			__newindex = function(t, k, v)
				if DBG.notInDebugger() then
					local msg = "New global defined: " .. DBG._tostring(k) .. "=" .. DBG._tostring(v) .. " (type " .. DBG.typeReal(v) .. ")"
					DBG.printColor(DBG.color.blue, msg)

					local tb = traceback(msg, 2)
					file:write(tb.."\n\n")
					file:flush()
				end
				rawset(t, k, v)
			end,
			__index = function(t, k)
				if DBG.notInDebugger() then
					local msg = "Trying to access undefined global: " .. DBG._tostring(k)
					DBG.printColor(DBG.color.blue, msg)

					local tb = traceback(msg, 2)
					file:write(tb.."\n\n")
					file:flush()
				end
				return nil
			end
		})
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
				storage = _G
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
				DBG.printColor(DBG.color.red, "You need to pass the line to check in!")
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

			local _getinfo = debug.getinfo
			local _getlocal = debug.getlocal

			getinfo = function(depth, what)
				return _getinfo(thread, depth, what)
			end

			getlocal = function(depth, index)
				return _getlocal(thread, depth, index)
			end
		else
			stack = (stack or 1) + 1

			getinfo = debug.getinfo
			getlocal = debug.getlocal
		end

		local var = {}

		local function realvalue(value)
			return rawequal(value, nil) and DBG.fakeNil or value
		end

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
						this[name] = realvalue(value)
					elseif type(this[name]) ~= "table" then
						this[name] = { this[name] }
					else
						this[name][#this[name]+1] = realvalue(value)
					end
				else
					this[name] = realvalue(value)
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
