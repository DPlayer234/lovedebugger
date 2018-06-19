--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local ERROR_UTF8 = ":ERROR (utf8):"

	local utf8 = require "utf8"
	local debug = require "debug"

	local string = string
	local tostring, pcall, type, unpack = tostring, pcall, type, unpack
	local rawget, rawequal = rawget, rawequal

	-- Creates a flat copy of a list
	function DBG._cloneList(t)
		return { unpack(t) }
	end

	-- P-called tostring
	function DBG._tostring(t)
		local s, r = pcall(tostring, t)
		return s and r or ":ERROR:"
	end

	local fromPattern = "%[\"[_a-zA-Z][_a-zA-Z0-9]-\"%]"
	local nicerPush = function(t) return "." .. t:sub(3, #t-2) end

	-- Returns a nicer environment path
	function DBG._nicerEnvPath(envPath)
		return envPath:gsub(fromPattern, nicerPush)
	end

	-- Checks whether a utf8 string is valid and either returns it, having replaced all
	-- null bytes with spaces or the error message
	function DBG._validateUtf8(s)
		return utf8.len(s) and s:gsub("%z", " ") or ERROR_UTF8
	end

	-- Makes sure to correctly format something for display
	function DBG._toDisplayString(value)
		return type(value) == "string" and string.format("%q", value):gsub("\\?\n", "\\n") or DBG._tostring(value)
	end

	-- Makes sure there's no line breaks in a string and by replacing them with spaces
	function DBG._toSingleLine(value)
		return (DBG._tostring(value):gsub("\n", " "))
	end

	-- Safely gets a value without calling anything
	function DBG.safeIndex(table, key, depth)
		depth = depth or 0
		if depth > 5 then return end -- Prevent endlessly looping
		local mt = debug.getmetatable(table)
		if type(mt) ~= "table" then -- No metatable
			if type(table) ~= "table" then return end -- Not a table
			return table[key] -- Return value
		end
		local index = rawget(mt, "__index")
		if type(index) == "table" then return DBG.safeIndex(index, key, depth + 1) end -- Get field from __index
		if type(table) == "table" then return rawget(table, key) end -- Get field from original table
	end

	-- Used to display alternative type
	function DBG.typeReal(v)
		if rawequal(v, DBG.fakeNil) then return "nil *" end
		local t = type(v)
		local tf = DBG.safeIndex(v, "type")
		if tf and tf ~= type then
			if type(tf) == "string" then return t .. ":" .. tf end
			local s, r = pcall(tf, v)
			if s and type(r) == "string" then return t .. ":" .. r end
		end
		return t
	end

	DBG.addSource()
end
