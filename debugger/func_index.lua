--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local debug = require "debug"
	local assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal = assert, setmetatable, next, type, ipairs, pairs, pcall, rawequal

	local indexFunctions = false
	local prettyFunctions = false

	DBG.FUNCTION_CODE = "DBG.FUNCTION_CODE"
	DBG.FUNCTION_UPVALUES = "DBG.FUNCTION_UPVALUES"
	DBG.FUNCTION_UPVALUE_NAMES = "DBG.FUNCTION_UPVALUE_NAMES"

	-- Up-Value-getter
	function DBG.allowFunctionIndex(prettyNames)
		DBG.printInfo(":Allowing the indexing of functions! Access to indexing is only allowed within the command line.")
		indexFunctions = true

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
				if DBG._notInDebugger() then error("attempt to index a function value", 2) end

				local fup = getlist(f)

				if k == DBG.FUNCTION_UPVALUES then
					local t = ret[f]
					local _
					for k,v in next, fup do _, t[k] = debug.getupvalue(f, v) end
					return t
				elseif k == DBG.FUNCTION_UPVALUE_NAMES then
					if retn[f] then
						return retn[f]
					else
						local t = {}
						for k,v in next, fup do t[k] = true end
						retn[f] = t
						return t
					end
				elseif k == DBG.FUNCTION_CODE then
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

			for i,v in ipairs {
				"assert", "collectgarbage", "dofile", "error", "gcinfo", "getfenv", "getmetatable", "ipairs", "load", "loadfile", "loadstring",
				"module", "newproxy", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "require", "select",
				"setfenv", "setmetatable", "type", "tonumber", "tostring", "unpack", "xpcall",
				"coroutine", "debug", "io", "math", "os", "string", "table", "package"
			} do
				addName(DBG._envRoot[v], v)
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
						v = "function: " .. (hardnames[f] or v) .. location
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

			DBG.printInfo(":Added " .. DBG._tostring(amount) .. " function names for predefined functions, totalling " .. DBG._tostring(bytes) .. " characters.")
		else
			prettyFunctions = false
		end

		debug.setmetatable(function() end, funcMeta)
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
