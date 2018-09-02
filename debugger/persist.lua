--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local utf8 = require "utf8"
	local love_filesystem = require "love.filesystem"

	local HISTORY_PATH = "HISTORY" --#const

	-- Runs the given function within it's own identity
	function DBG._inOwnIdentity(func)
		local identity = love_filesystem.getIdentity()
		love_filesystem.setIdentity(DBG.identity)
		xpcall(func, DBG.printError)
		love_filesystem.setIdentity(identity)
	end

	-- Splits a string into a char array
	local function toCharArray(string)
		local chars = {}
		for p, c in utf8.codes(string) do
			chars[#chars + 1] = utf8.char(c)
		end
		return chars
	end

	-- Saves the persistent state
	local function savePersistent()
		local hFile = assert(love_filesystem.newFile(HISTORY_PATH, "w"))

		local history = DBG.getHistory()

		for i=1, #history do
			hFile:write(history[i])
			hFile:write("\r\n")
		end

		hFile:close()
	end

	-- Loads the persistent state
	local function loadPersistent()
		if love_filesystem.getInfo("history", "file") == nil then return end

		local hFile = assert(love_filesystem.newFile(HISTORY_PATH, "r"))

		for line in hFile:lines() do
			DBG._lastInput[#DBG._lastInput + 1] = toCharArray(line)
		end

		hFile:close()
	end

	-- Saves the persistent state
	function DBG.savePersistent()
		DBG._inOwnIdentity(savePersistent)
	end

	-- Loads the persistent state
	function DBG.loadPersistent()
		DBG._inOwnIdentity(loadPersistent)
	end
end
