--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local ffi = require "ffi"
	local utf8 = require "utf8"
	local debug = require "debug"
	local love_graphics = require "love.graphics"

	local assert, pcall, next, type, rawequal, select, load, setmetatable = assert, pcall, next, type, rawequal, select, load, setmetatable
	local table = table

	DBG._LOAD_SRC = "DBG_SRC_STRING"
	DBG._DEFAULT_ENV_ROOT_NAME = "_ENV"

	DBG._envRootName = DBG._DEFAULT_ENV_ROOT_NAME
	DBG._loadEnv = _G
	DBG._envRoot = _G

	DBG._textTable = {}
	DBG._textPosition = 0

	DBG._envNav = {}
	DBG._yScroll = 1

	DBG._ram = 0

	DBG._textTable = {}
	DBG._textPosition = 1
	DBG._lastSelect = 0
	DBG._lastInput = {}

	DBG._hidden = setmetatable({}, { __mode = "k" })

	DBG._accessCache = setmetatable({}, { __mode = "v" })
	DBG._accessCacheUse = setmetatable({}, { __mode = "k" })
	DBG._accessCacheCount = 0

	-- Returns the current environment root.
	function DBG.getEnv()
		return DBG._envRoot, DBG._envRootName
	end

	-- Sets the root environment
	function DBG.setEnv(env, envName)
		assert(type(env) == "table", "Argument #1 to DBG.setEnv(env, envName) must be a table!")
		if envName ~= nil then
			assert(type(envName) == "string", "Argument #2 to DBG.setEnv(env, envName) must be a string or nil!")
			assert(DBG.isVariableName(envName), "Argument #2 to DBG.setEnv(env, envName) must be a valid variable name!")

			DBG._envRootName = envName or DBG._DEFAULT_ENV_ROOT_NAME
		end

		DBG._envRoot = env

		DBG._loadEnv = setmetatable({
			META = debug.getmetatable,
			CACHE = DBG._fetchFromCache,
			[DBG._envRootName] = env
		}, {
			__index = env,
			__newindex = env
		})

		DBG._envNav = {}
	end

	-- Gets a copy of the navigation list
	function DBG._getEnvNavCopy()
		return DBG._cloneList(DBG._envNav)
	end

	-- Gets the currently navigated to value
	function DBG._getNavValue(nav)
		local navValue = DBG._envRoot
		local ok

		for i=1, #nav do
			ok, navValue = pcall(DBG._subGetNavValue, navValue, nav[i])
			if not ok then return nil end
		end

		return navValue
	end

	-- Gets the currently navigated to value and the index if valid
	function DBG._getNavValueSort(nav)
		local navValue = DBG._getNavValue(nav)
		if type(navValue) == "table" then
			return DBG._sortAsEnv(navValue), navValue
		elseif DBG.isFunctionIndexAllowed() and type(navValue) == "function" then
			return navValue[DBG.FUNCTION_UPVALUE_MAP], navValue
		end
		return nil, navValue
	end

	-- Gets the next entry in the DV based on the current DV and nav[i]
	function DBG._subGetNavValue(cdv, navI)
		if navI.meta then
			return debug.getmetatable(cdv)
		end
		return cdv[navI.key]
	end

	-- Loads a string with the debugger's environment
	function DBG.loadString(code)
		return load(code, DBG._LOAD_SRC, "t", DBG._loadEnv)
	end

	-- Hide fields of a certain table via pattern in the environment display
	function DBG.hideFields(table, pattern)
		assert(type(pattern) == "string" or pattern == nil, ":Argument #2 to DBG.hideFields(table, pattern) must be a string or nil!")
		DBG._hidden[table] = pattern
	end

	-- Sets the used font
	function DBG.setFont(nfont)
		assert(DBG.typeReal(nfont) == "userdata:Font", ":Not a font.")

		DBG._font = nfont
		DBG._fontHeight = DBG._font:getHeight() * DBG._font:getLineHeight()
	end

	-- Returns the used font
	function DBG.getFont()
		return DBG._font
	end

	local function lt(a, b) return a < b end

	-- This function will affect the order of the environment display.
	DBG.envSortFunc = function(a, b)
		local tva, tvb = type(a.value), type(b.value)
		if tva ~= tvb then
			if tva == "function" then
				return false
			elseif tvb == "function" then
				return true
			end
		end

		local tka, tkb = type(a.key), type(b.key)
		if tka == tkb then
			local s, r = pcall(lt, a.key, b.key)
			return s and r
		end
		return tka < tkb
	end

	-- Sorts a table
	function DBG._sortAsEnv(t)
		local to = DBG._untable(t)
		if DBG._hidden[t] then
			local hidden = DBG._hidden[t]

			for i=#to, 1, -1 do
				local k = to[i].key
				if type(k) == "string" and k:find(hidden) ~= nil then
					table.remove(to, i)
				end
			end
		end

		table.sort(to, DBG.envSortFunc)
		return to
	end

	-- Adds a value to the access cache
	function DBG._addToCache(value)
		if DBG._accessCacheUse[value] then
			return DBG._accessCacheUse[value]
		end

		local index = DBG._accessCacheCount
		DBG._accessCache[index] = value
		DBG._accessCacheUse[value] = index
		DBG._accessCacheCount = DBG._accessCacheCount + 1
		return index
	end

	-- Returns a value in the access cache based on its index
	function DBG._fetchFromCache(index)
		return DBG._accessCache[index]
	end

	-- Clears the access cache
	function DBG._clearCache()
		for index, _ in pairs(DBG._accessCache) do
			DBG._accessCache[index] = nil
		end

		for value, _ in pairs(DBG._accessCacheUse) do
			DBG._accessCacheUse[value] = nil
		end

		DBG._accessCacheCount = 0
	end

	-- Navigates one element relative to the current one
	function DBG.navigate(action, arg)
		DBG._navigate(DBG._envNav, action, arg)
		DBG._yScroll = 1
	end

	-- Navigates to an environment path
	function DBG.navigateTo(envPath)
		local nav = {}
		for s in envPath:gmatch("[^%.]+") do
			DBG._navigate(nav, "key", s)
		end
		DBG._replaceEnvNav(nav)
	end

	-- Navigates a specific navigation by a certain action
	function DBG._navigate(nav, action, arg)
		if action == "key" then
			nav[#nav + 1] = { key = arg }
		elseif action == "meta" then
			nav[#nav + 1] = { meta = true }
		elseif action == "parent" then
			nav[#nav] = nil
		else
			error("Unknown navigation action.")
		end
	end

	-- Replaces the environment navigation
	function DBG._replaceEnvNav(nav)
		DBG._envNav = nav
		DBG._yScroll = 1
	end

	-- Copies text to the console
	function DBG._copyTextToConsole(text)
		for p, c in utf8.codes(text) do
			DBG.callbacks.textinput(utf8.char(c))
		end
	end

	-- Returns the command history as a list of strings
	function DBG.getHistory()
		local history = {}

		for i=1, #DBG._lastInput do
			history[i] = DBG._lastInput[i]
		end

		return history
	end

	-- Returns the current text in the prompt
	function DBG._getPromptText()
		return table.concat(DBG._textTable, "")
	end

	-- Sets the current text in the prompt
	function DBG._setPromptText(str)
		DBG._textTable = DBG._toCharArray(str)
		DBG._textPosition = #DBG._textTable + 1
	end

	do
		local getinfo = debug.getinfo

		local sources = {
			[DBG._LOAD_SRC] = true
		}

		-- Returns whether the scope is outside of the DBG
		function DBG._notInDebugger()
			return not sources[debug.getinfo(3, "S").source]
		end

		-- Adds the file the given function or it was called in to the debugger sources.
		function DBG.addSource(func)
			sources[debug.getinfo(func or 2, "S").source] = true
		end
	end

	-- Fake nil value inserted where nil is needed.
	-- Basically, just an explicit nil (fakeNil == nil -> true)
	do
		ffi.cdef "struct nil {};"

		ffi.metatype("struct nil", {
			__eq = function(a, b)
				return rawequal(a, nil) or rawequal(b, nil) or rawequal(a, b)
			end,
			__tostring = function()
				return "nil"
			end
		})

		DBG.fakeNil = ffi.new("struct nil")
	end

	DBG.setEnv(_G)
	DBG.addSource()
end
