--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local string = string
	local pcall, loadstring, unpack, type = pcall, loadstring, unpack, type

	-- Handle the title management
	local titleManager = {}

	if love.window then
		titleManager.getTitle = love.window.getTitle
		titleManager.setTitle = love.window.setTitle
		titleManager.titleUpdated = false

		local title = titleManager.getTitle()
		local updated = false

		titleManager.getRegularTitle = --[[]]function() return title end

		love.window.getTitle = titleManager.getRegularTitle
		love.window.setTitle = --[[]]function(new)
			local oftype = type(new)
			if type(new) == "string" then
				title = new
			elseif type(new) == "number" then
				title = DBG._tostring(new)
			else
				error("Bad argument #1 to '?' (string expected, got " .. DBG.typeReal(new) .. ")", 2)
			end
			titleManager.titleUpdated = true
		end
	else
		titleManager.getTitle = --[[]]function()return""end
		titleManager.setTitle = --[[]]function()end
		titleManager.titleUpdated = false
	end

	DBG._titleManager = titleManager

	-- Handling the variable display
	DBG._getAdditionalInfo = function() end

	DBG._infoTitleFormat = "%s [%d FPS] [%.1f KB] [%.6f s.]"
	function DBG._infoTitle(title, fps, ram, time)
		local s, r = pcall(string.format, DBG._infoTitleFormat, title, fps, ram, time, DBG._getAdditionalInfo())
		return r
	end

	DBG._infoBoxFormat = "%d FPS\n~%.1f KB\n%.6f s."
	function DBG._infoBox(fps, ram, time)
		local s, r = pcall(string.format, DBG._infoBoxFormat, fps, ram, time, DBG._getAdditionalInfo())
		return r
	end

	DBG._origInfoTitleFormat = DBG._infoTitleFormat
	DBG._origInfoBoxFormat = DBG._infoBoxFormat

	-- Modifies the variable display
	function DBG.varDisplay(...)
		DBG._infoTitleFormat, DBG._infoBoxFormat = DBG._origInfoTitleFormat, DBG._origInfoBoxFormat
		if ... then
			local varList = ""
			local varFunc = {}
			local args = {...}

			for i=1, #args do
				local v = args[i]

				DBG._infoTitleFormat = DBG._infoTitleFormat .. " [" .. v[1] .. "]"
				DBG._infoBoxFormat = DBG._infoBoxFormat .. "\n" .. v[1]
				varList = varList .. "v" .. DBG._tostring(i) .. (i < #args and "," or "")
				varFunc[i] = v[2]
			end

			local code = [[
				local pcall,]] .. varList .. [[ = ...
				local function vars()
					return ]] .. varList:gsub(",", "(),") .. [[()
				end
				return function()
					local s,]] .. varList .. [[ = pcall(vars)
					return ]] .. varList .. [[
				end
			]]
			DBG._getAdditionalInfo = loadstring(code, DBG._LOADSTRING_SRC)(pcall, unpack(varFunc))
			DBG.printColor(DBG.color.yellow, ":Set custom Var. Display.")
		else
			DBG._getAdditionalInfo = function() end
			DBG.printColor(DBG.color.yellow, ":Reset Var. Display.")
		end
	end

	DBG.addSource()
end
