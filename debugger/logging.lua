--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local love_graphics = require "love.graphics"
	local love_timer = require "love.timer"
	local io = require "io"

	local next, rawequal = next, rawequal
	local table, math, string = table, math, string

	local lua_print = print
	local io_write = io.write

	local logged = {}
	local loggedTemp, loggedTempTime = {}, {}

	local MAXIMUM_LOG_ENTRIES = 200 --#const
	local MAXIMUM_LOG_ENTRIES_x2 = MAXIMUM_LOG_ENTRIES * 2 --#const

	-- Print something to the local console
	local lastPrint, printedTimes
	local function proxyPrint(c, ...)
		local args = {...}
		local top = 0
		for i, v in next, args do
			args[i] = DBG._validateUtf8(DBG._tostring(v))
			if i > top then top = i end
		end
		for i=1, top do
			if rawequal(args[i], nil) then
				args[i] = "nil"
			end
		end

		if #args < 1 then args[1] = "nil" end
		args[#args + 1] = "\n"

		local t = table.concat(args, "\t")
		local tabPos = 1
		while DBG.replaceTabs do
			tabPos = t:find("\t", tabPos)
			if not tabPos then break end
			local new = DBG.replaceTabs - (tabPos - 1) % DBG.replaceTabs
			if new == 0 then new = DBG.replaceTabs end
			t = t:sub(1, tabPos - 1) .. string.rep(" ", new) .. t:sub(tabPos + 1, #t)
			tabPos = tabPos + new
		end

		if t ~= lastPrint then
			local time = love_timer.getTime()
			for s in t:gmatch(".-\n") do
				logged[#logged + 1] = c
				logged[#logged + 1] = s

				loggedTemp[#loggedTemp + 1] = c
				loggedTemp[#loggedTemp + 1] = s

				loggedTempTime[#loggedTempTime + 1] = time
			end

			while #logged > MAXIMUM_LOG_ENTRIES_x2 do
				table.remove(logged, 1)
				table.remove(logged, 1)
			end

			while #loggedTemp > MAXIMUM_LOG_ENTRIES_x2 do
				table.remove(loggedTemp, 1)
				table.remove(loggedTemp, 1)

				table.remove(loggedTempTime, 1)
			end

			lastPrint = t
			printedTimes = 1
		else
			printedTimes = printedTimes + 1
			if printedTimes == 2 then
				logged[#logged] = "(2x) "..logged[#logged]
			else
				logged[#logged] = logged[#logged]:gsub("^%(%d+x%)", "("..DBG._tostring(printedTimes).."x)")
			end
			if #loggedTemp > 1 then
				loggedTemp[#loggedTemp] = logged[#logged]
				loggedTempTime[#loggedTempTime] = love_timer.getTime()
			else
				loggedTemp[1] = logged[#logged - 1]
				loggedTemp[2] = logged[#logged]
				loggedTempTime[1] = love_timer.getTime()
			end
		end

		return t
	end

	local function proxyPrintNR(c, ...)
		proxyPrint(c, ...)
	end

	DBG.print = proxyPrintNR
	DBG.lua_print = lua_print

	-- Prints stuff everywhere
	function DBG.allPrint(...)
		io_write(proxyPrint(DBG.color.white, ...))
	end

	print = DBG.allPrint

	-- Prints in color everywhere
	function DBG.printColor(c, text)
		io_write(proxyPrint(c, text))
	end

	-- Prints a log message
	function DBG.printLog(text)
		DBG.printColor(DBG.color.yellow, text)
	end

	-- Prints an error
	function DBG.printError(text)
		DBG.printColor(DBG.color.red, text)
	end

	-- Clearing print calls
	function DBG.clear()
		for k,v in next, logged do logged[k] = nil end
		DBG.tempClear()
	end

	-- Clears the temporary display only
	function DBG.tempClear()
		for k,v in next, loggedTemp do loggedTemp[k] = nil end
		for k,v in next, loggedTempTime do loggedTempTime[k] = nil end
	end

	-- Fades the text in the temporary log out
	function DBG._tempFade()
		local ctime = love_timer.getTime()
		while #loggedTempTime > 0 and loggedTempTime[1] + DBG.textFade < ctime do
			table.remove(loggedTemp, 1)
			table.remove(loggedTemp, 1)

			table.remove(loggedTempTime, 1)
		end
	end

	DBG._logged = logged
	DBG._loggedTemp = loggedTemp
	DBG._loggedTempTime = loggedTempTime

	DBG.addSource()
end
