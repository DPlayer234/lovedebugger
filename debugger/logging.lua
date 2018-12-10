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

	local next, rawequal, select = next, rawequal, select
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
		local argc = select("#", ...)
		local args = {...}

		for i=1, argc do
			args[i] = DBG._validateUtf8(DBG._tostring(args[i]))
		end

		args[argc + 1] = "\n"

		local fullText = DBG._replaceTabs(table.concat(args, "\t"))

		if fullText ~= lastPrint then
			local time = love_timer.getTime()
			for s in fullText:gmatch(".-\n") do
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

			lastPrint = fullText
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

		return fullText
	end

	-- Replaces tabs in a string according to DBG.replaceTabs
	function DBG._replaceTabs(str)
		if not DBG.replaceTabs then return str end

		local nlPos = str:find("\n") or 0
		local tabPos = str:find("\t")
		if nlPos > tabPos then nlPos = 0 end
		while tabPos do
			local nnlPos
			repeat
				nlPos = nnlPos or nlPos
				nnlPos = str:find("\n", nlPos + 1)
			until not nnlPos or nnlPos > tabPos
			local new = DBG.replaceTabs - (tabPos - nlPos - 1) % DBG.replaceTabs
			if new == 0 then new = DBG.replaceTabs end
			str = str:sub(1, tabPos - 1) .. string.rep(" ", new) .. str:sub(tabPos + 1, #str)
			tabPos = str:find("\t", tabPos + new)
		end

		return str
	end

	DBG.lua_print = lua_print

	-- Prints text to the debugger console only
	function DBG.print(c, ...)
		proxyPrint(c, ...)
	end

	-- Prints stuff everywhere
	function DBG.allPrint(...)
		io_write(proxyPrint(DBG.colors.printNormal, ...))
	end

	print = DBG.allPrint

	-- Prints in color everywhere
	function DBG.printColor(c, text)
		return io_write(proxyPrint(c, text))
	end

	-- Prints a log message
	function DBG.printLog(text)
		return DBG.printColor(DBG.colors.printLog, text)
	end

	-- Prints information
	function DBG.printInfo(text)
		return DBG.printColor(DBG.colors.printInfo, text)
	end

	-- Prints an error
	function DBG.printError(text)
		return DBG.printColor(DBG.colors.printError, text)
	end

	-- Prints a warning
	function DBG.printWarning(text)
		return DBG.printColor(DBG.colors.printWarning, text)
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
