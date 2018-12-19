--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local love_filesystem = require("love.filesystem")
	local debug = require "debug"
	local assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal = assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal

	local isFile = function(path)
		local info = love_filesystem.getInfo(path)
		return info and info.type == "file"
	end

	local indexFunctions = false
	local prettyFunctions = false

	DBG.FUNCTION_CODE = 0
	DBG.FUNCTION_UPVALUES = 1
	DBG.FUNCTION_UPVALUE_MAP = 2

	-- Up-Value-getter
	function DBG.allowFunctionIndex(prettyNames)
		DBG.printInfo(":Allowing the indexing of functions! Access to indexing is only allowed within the command line.")
		indexFunctions = true

		local upvalueIds = setmetatable({}, { __mode = "k" })

		local selfFillingMeta = {
			__mode = "k",
			__index = function(t, k)
				local v = {}
				t[k] = v
				return v
			end
		}

		local upvalues = setmetatable({}, selfFillingMeta)
		local upvalueMaps = setmetatable({}, selfFillingMeta)

		local isVarName = DBG.isVariableName

		-- Gets a list with all up-values of the function
		local function getUpvalueIds(f)
			if upvalueIds[f] then
				return upvalueIds[f]
			else
				local fUpIds = {}

				local i = 1
				local k, v = debug.getupvalue(f, i)
				while k do
					fUpIds[isVarName(k) and k or i] = i
					i = i + 1
					k, v = debug.getupvalue(f, i)
				end

				upvalueIds[f] = fUpIds
				return fUpIds
			end
		end

		-- Gets a table with all up-values of the function (name: value)
		local function getUpvalues(f)
			local fUpIds = getUpvalueIds(f)
			local t = upvalues[f]
			for name, id in next, fUpIds do
				name, t[name] = debug.getupvalue(f, id)
			end
			return t
		end

		-- Gets a list with all up-values of the function as key-value pairs
		local function getUpvalueMap(f)
			local fUpIds = getUpvalueIds(f)
			local t = upvalueMaps[f]
			for name, id in next, fUpIds do
				local name, value = debug.getupvalue(f, id)
				t[id] = { key = name, value = value }
			end
			table.sort(t, DBG.envSortFunc)
			return t
		end

		-- Gets the code of a function
		local function getCode(f)
			if debug.getinfo then
				local info = debug.getinfo(f, "S")
				local source = (info.source or ""):gsub("^@", "")
				if isFile(source) then
					local i = 0
					local codelines = {}
					for line in love_filesystem.lines(source) do
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
		end

		-- Gets an upvalue by name
		local function getUpvalue(f, name)
			local fUpIds = getUpvalueIds(f)
			if fUpIds[name] then
				local k, v = debug.getupvalue(f, fUpIds[name])
				return v
			else
				error("attempt to get invalid upvalue", 2)
			end
		end

		local funcMeta = {
			__index = function(f, k)
				if DBG._notInDebugger() then error("attempt to index a function value", 2) end

				if type(k) == "string" then
					return getUpvalue(f, k)
				elseif k == DBG.FUNCTION_UPVALUES then
					return getUpvalues(f)
				elseif k == DBG.FUNCTION_UPVALUE_MAP then
					return getUpvalueMap(f)
				elseif k == DBG.FUNCTION_CODE then
					return getCode(f)
				else
					error("invalid function index operation", 2)
				end
			end,
			__newindex = function(f, k, v)
				local fUpIds = getUpvalueIds(f)
				if fUpIds[k] then
					debug.setupvalue(f, fUpIds[k], v)
				else
					error("attempt to set invalid upvalue", 2)
				end
			end,
			--__metatable = false
		}

		if prettyNames then
			DBG._addPrettyFunctionNames(funcMeta)
		else
			prettyFunctions = false
		end

		debug.setmetatable(function() end, funcMeta)
	end

	-- Registers the pretty function name __tostring method
	function DBG._addPrettyFunctionNames(funcMeta)
		prettyFunctions = true

		local amount, bytes = 1, 5
		local hardnames = {
			[DBG.lua_print] = "print"
		}

		local indexed = {
			[DBG._envRoot] = true,
			[package.loaded] = true,
			[package.preload] = true
		}

		local function addName(item, path)
			if indexed[item] or hardnames[item] then return end
			if type(item) == "table" then
				indexed[item] = true
				for k, v in next, item do
					if type(k) == "string" then
						addName(v, path .. "." .. k)
					end
				end
			elseif type(item) == "function" then
				hardnames[item] = path
				amount = amount + 1
				bytes = bytes + #path
			end
		end

		for i, v in ipairs {
			"assert", "collectgarbage", "dofile", "error", "gcinfo", "getfenv", "getmetatable", "ipairs", "load", "loadfile", "loadstring",
			"module", "newproxy", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "require", "select",
			"setfenv", "setmetatable", "type", "tonumber", "tostring", "unpack", "xpcall",
			"coroutine", "debug", "io", "math", "os", "string", "table", "package"
		} do
			addName(DBG._envRoot[v], v)
		end

		for i, v in ipairs {
			"bit", "jit", "love", "ffi"
		} do
			local s, r = pcall(require, v)
			if s then
				addName(r, v)
			end
		end

		addName(debug.getmetatable(DBG.fakeNil), "<cdata>")

		addName(DBG, DBG._PATH)

		local names = setmetatable({}, {
			__index = function(t, f)
				local name

				local info = debug.getinfo(f, "S")
				local source = (info.source or ""):gsub("^@", "")
				local linedefined = info.linedefined
				if linedefined == 0 then
					return ("function: \"%s\""):format(source)
				elseif isFile(source) and linedefined then
					local i = 0
					local defined
					for line in love_filesystem.lines(source) do
						i = i + 1
						-- linedefined, lastlinedefined, params
						if i >= linedefined then
							defined = " "..line.." "
							break
						end
					end
					if defined then
						name = defined:match("%)%-%-%[%[(.-)%]%]")
							or defined:match("[^_a-zA-Z0-9]function%s+([_a-zA-Z][%.%:_a-zA-Z0-9]*)[^_a-zA-Z0-9]")
							or defined:match("[^_a-zA-Z0-9]([_a-zA-Z][%.%:_a-zA-Z0-9]*)%s*=%s*%(*function[^_a-zA-Z0-9]")
					end
				end

				local shortSrc = info.short_src
				local location =
					shortSrc == "[C]" and "[C]" or
					("(" .. shortSrc .. ":" .. DBG._tostring(linedefined) .. ")")

				if name or hardnames[f] then
					name = ("function: %s %s"):format(hardnames[f] or name, location)
					hardnames[f] = nil
				else
					name = ("function: %p %s"):format(f, location)
				end

				t[f] = name
				return name
			end,
			__mode = "kv"
		})

		function funcMeta:__tostring()
			return names[self]
		end

		DBG.printInfo(":Added " .. DBG._tostring(amount) .. " function names for predefined functions, totalling " .. DBG._tostring(bytes) .. " characters.")
	end

	-- Disallows function indexing
	function DBG.disallowFunctionIndex()
		DBG.printInfo(":Indexing functions has been disabled.")

		indexFunctions = false
		prettyFunctions = false

		debug.setmetatable(function() end, nil)
	end

	-- Returns whether function indexing is allowed
	function DBG.isFunctionIndexAllowed()
		return indexFunctions
	end

	-- Returns whether there are pretty function names
	function DBG.hasPrettyFunctionNames()
		return prettyFunctions
	end

	DBG.addSource()
end
