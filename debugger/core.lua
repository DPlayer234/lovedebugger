--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local ffi = require "ffi"
	local debug = require "debug"
	local love_graphics = require "love.graphics"

	local assert, pcall, next, type, rawequal = assert, pcall, next, type, rawequal
	local table = table

	DBG._LOADSTRING_SRC = "DBG_SRC_STRING"

	DBG._textTable = {}
	DBG._textPosition = 0

	DBG._envPath = "_G"
	DBG._yScroll = 1
	DBG._inputs = {}

	DBG._textInput = ""
	DBG._textTable = {}
	DBG._textPosition = 1
	DBG._lastSelect = 0
	DBG._lastInput = {}

	-- Gets the currently navigated to value
	function DBG._getDv(envPath)
		local s, dv = pcall(loadstring("local getmetatable=... return "..envPath, DBG._LOADSTRING_SRC), debug.getmetatable)
		if s then
			return dv
		else
			return nil
		end
	end

	-- Gets the currently navigated to value and the index if valid
	function DBG._getDvIndex(envPath)
		local dv = DBG._getDv(envPath)
		if type(dv) == "table" then
			return dv, DBG._sortedTable(dv)
		end
		if DBG._indexFunctions and type(dv) == "function" then
			return dv, DBG._sortedTable(dv.___allupvaluenames)
		end
		return dv
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

	-- This function will affect the order of the environment display.
	-- You may rewrite this: It should get a table and return an array with the KEYS of the origCallback table as its VALUES.
	-- E.g. DBG._sortedTable({ x = 5, y = 2, a = "test" }) -> { "a", "x", "y" }
	local function sortCont(a, b) if type(a) == type(b) then return a < b else return tostring(a) < tostring(b) end end
	local function pSortCont(a, b) local s, r = pcall(sortCont, a, b) return s and r end

	-- Sorts a table
	function DBG._sortedTable(t)
		local to = {}
		for k,v in next, t do
			to[#to+1] = k
		end
		pcall(table.sort, to, sortCont) -- <= Real Sorting
		return to
	end

	-- Returns whether the scope is outside of the DBG
	do
		local getinfo = debug.getinfo

		local sources = {
			[DBG._LOADSTRING_SRC] = true
		}

		function DBG.notInDebugger()
			return not sources[debug.getinfo(3, "S").source]
		end

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

	DBG.addSource()
end
