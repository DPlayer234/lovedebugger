--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local love_graphics = require "love.graphics"
	local love_timer = require "love.timer"

	local next, rawequal = next, rawequal
	local table, math = table, math

	local lg, lgTemp, lgTime = {}, {}, {}

	-- Print something to the local console
	local lastPrint, printedTimes
	local function proxyPrint(c, ...)
		local args = {...}
		local top = 0
		for i,v in next, args do
			args[i] = DBG._validateUtf8(DBG._tostring(v))
			if DBG.replaceTabs then
				args[i] = args[i]:gsub("\t", DBG.replaceTabs)
			end
			if i > top then top = i end
		end
		for i=1, top do
			if rawequal(args[i], nil) then
				args[i] = "nil"
			end
		end

		if #args < 1 then args[1] = "nil" end
		args[#args+1] = "\n"

		local t = table.concat(args, DBG.replaceTabs or "\t")

		if t ~= lastPrint then
			local time = love_timer.getTime()
			for s in t:gmatch(".-\n") do
				table.insert(lg, c)
				table.insert(lg, s)

				table.insert(lgTemp, c)
				table.insert(lgTemp, s)

				table.insert(lgTime, time)
			end

			lastPrint = t
			printedTimes = 1
		else
			printedTimes = printedTimes + 1
			if printedTimes == 2 then
				lg[#lg] = "(2x) "..lg[#lg]
			else
				lg[#lg] = lg[#lg]:gsub("^%(%d+x%)", "("..DBG._tostring(printedTimes).."x)")
			end
			if #lgTemp > 1 then
				lgTemp[#lgTemp] = lg[#lg]
				lgTime[#lgTime] = love_timer.getTime()
			else
				lgTemp[1] = lg[#lg-1]
				lgTemp[2] = lg[#lg]
				lgTime[1] = love_timer.getTime()
			end
		end
	end

	local realPrint = print
	DBG.print = proxyPrint
	DBG.realPrint = realPrint

	-- Prints stuff everywhere
	function DBG.allPrint(...)
		realPrint(...)
		return proxyPrint(DBG.color.white, ...)
	end

	print = DBG.allPrint

	-- Prints in color everywhere
	function DBG.printColor(c, text)
		realPrint(text)
		return proxyPrint(c, text)
	end

	-- Clearing print calls
	function DBG.clear()
		for k,v in next, lg do lg[k] = nil end
		DBG.tempClear()
	end

	-- Clears the temporary display only
	function DBG.tempClear()
		for k,v in next, lgTemp do lgTemp[k] = nil end
		for k,v in next, lgTime do lgTime[k] = nil end
	end

	-- Fades the text in the temporary log out
	function DBG._tempFade()
		local ctime = love_timer.getTime()
		while #lgTime > 0 and lgTime[1] + DBG.textFade < ctime do
			table.remove(lgTemp, 1)
			table.remove(lgTemp, 1)
			table.remove(lgTime, 1)
		end
	end

	DBG._lg = lg
	DBG._lgTemp = lgTemp
	DBG._lgTime = lgTime

	DBG.addSource()
end
