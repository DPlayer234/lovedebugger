--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local utf8 = require "utf8"
	local love_filesystem = require "love.filesystem"

	local HISTORY_NAME = "DBG_HISTORY" --#const
	local SAVE_DIR = love.filesystem.getSaveDirectory()
	local CUR_IDENTITY = love.filesystem.getIdentity()
	local HISTORY_PATH = SAVE_DIR:sub(1, #SAVE_DIR - #CUR_IDENTITY) .. HISTORY_NAME

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
		love_filesystem.createDirectory("")
		local hFile = assert(io.open(HISTORY_PATH, "wb"))

		local history = DBG.getHistory()

		for i=1, #history do
			hFile:write(history[i])
			hFile:write("\r\n")
		end

		hFile:close()
	end

	-- Loads the persistent state
	local function loadPersistent()
		local hFile = io.open(HISTORY_PATH, "rb")

		if not hFile then return end

		for line in hFile:lines() do
			DBG._lastInput[#DBG._lastInput + 1] = toCharArray(line:gsub("[\r\n]*", ""))
		end

		hFile:close()
	end

	-- Saves the persistent state
	function DBG.savePersistent()
		xpcall(savePersistent, DBG.printError)
	end

	-- Loads the persistent state
	function DBG.loadPersistent()
		xpcall(loadPersistent, DBG.printError)
	end
end
