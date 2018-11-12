--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local utf8 = require "utf8"
	local debug = require "debug"
	local love = require "love"
	local love_timer = require "love.timer"
	local love_mouse = require "love.mouse"
	local love_graphics = require "love.graphics"
	local love_system = require "love.system"

	local table, math = table, math
	local assert, type, tonumber, pcall = assert, type, tonumber, pcall

	DBG._updateEvents = {}
	DBG._updateTime = 0

	-- Returns the value in a table
	local function exget(table, key)
		return table[key]
	end

	-- Allows copying from or pasting to the console
	function DBG._handleClipboard()
		if ((DBG.isDown("lctrl") or DBG.isDown("rctrl")) and DBG._keyboard.isDown("v"))
		or (DBG._keyboard.isDown("lctrl", "rctrl") and DBG.isDown("v")) or DBG.isDown("insert") then
			local cbt = love_system.getClipboardText()
			if type(cbt) == "string" then
				DBG._copyTextToConsole(cbt)
			end
		elseif ((DBG.isDown("lctrl") or DBG.isDown("rctrl")) and DBG._keyboard.isDown("c"))
		or (DBG._keyboard.isDown("lctrl", "rctrl") and DBG.isDown("c")) then
			love_system.setClipboardText(table.concat(DBG._textTable, ""))
		end
	end

	-- For cycling through the last inputs to the console
	function DBG._handleConsoleCycle()
		if DBG.isDown("up") then
			if DBG._lastSelect < #DBG._lastInput then
				if DBG._lastSelect == 0 and #DBG._textTable > 0 then
					table.insert(DBG._lastInput, 1, DBG._textTable)
					DBG._lastSelect = 2
				else
					DBG._lastSelect = DBG._lastSelect + 1
				end
				DBG._textTable = DBG._cloneList(DBG._lastInput[DBG._lastSelect])
				DBG._textPosition = #DBG._textTable+1
			end
		elseif DBG.isDown("down") then
			if DBG._lastSelect > 0 then
				DBG._lastSelect = DBG._lastSelect - 1
				if DBG._lastSelect == 0 then
					DBG._textTable = {}
				else
					DBG._textTable = DBG._cloneList(DBG._lastInput[DBG._lastSelect])
				end
				DBG._textPosition = #DBG._textTable+1
			end
		end
	end

	-- For moving the cursor through the written text
	function DBG._handleCursorMovement()
		if DBG.isDown("right") and DBG._textPosition <= #DBG._textTable then
			DBG._textPosition = DBG._textPosition + 1
		elseif DBG.isDown("left") and DBG._textPosition > 1 then
			DBG._textPosition = DBG._textPosition - 1
		end
	end

	-- Handling console execution.
	function DBG._handleConsoleExecution()
		if DBG.isDown("return") and #DBG._textTable > 0 then
			local textInput = table.concat(DBG._textTable, "")

			-- Storing current input to be reused
			table.insert(DBG._lastInput, 1, DBG._textTable)
			DBG._lastSelect = 0
			if #DBG._lastInput > DBG.maxStorage then
				table.remove(DBG._lastInput, #DBG._lastInput)
			end

			DBG._textTable = {}
			DBG._textPosition = 1

			if textInput:find("^[/\\!:%.%*]") then
				-- A command. Has to be.
				DBG.executeCommand(textInput)
			else
				DBG.executeLuaCode(textInput)
			end
		end
	end

	-- Handles the environment
	function DBG._handleEnvUpdate()
		local dv, index = DBG._getDvIndex(DBG._envNav)

		if (DBG.isDown("m1") or DBG.isDown("m2")) and love_mouse.getX() >= love_graphics.getWidth() * DBG.printWidth then
			local newId = math.floor(love_mouse.getY() / DBG._fontHeight - 2)

			if newId >= 0 then
				-- Clicked on a variable
				if index and index[newId + DBG._yScroll] then
					local newKey = index[newId + DBG._yScroll]

					-- Getting the value we're trying to navigate to
					local ok, newValue = pcall(exget, dv, newKey)

					if not ok then
						-- Something went wrong, ignore.
					elseif type(newValue) == "table" and DBG.isDown("m1") then
						-- Navigating to another table
						DBG.navigate("key", newKey)
					elseif DBG._keyboard.isDown("lshift", "rshift") then
						-- Holding Shift
						if DBG.isDown("m2") and debug.getmetatable(newValue) ~= nil then
							-- RMB -> Navigate to potential metatable
							DBG.navigate("key", newKey)
							DBG.navigate("meta")
						elseif DBG.isFunctionIndexAllowed() and type(newValue) == "function" then
							-- Otherwise -> Navigating to a function's upvalues
							DBG.navigate("key", newKey)
						end
					else
						-- Copying the variable name to the prompt
						local pNav = DBG._getEnvNavCopy()
						DBG._navigate(pNav, "key", newKey)
						DBG._copyTextToConsole(DBG.getEnvPath(pNav))
					end
				else
					-- Copying the variable name to the prompt
					DBG._copyTextToConsole(DBG.getEnvPath())
				end
			else
				-- Clicked on the top
				if not DBG.isDown("m2") then
					DBG.navigate("parent")
				elseif debug.getmetatable(dv) ~= nil then
					-- Navigating to the currently indexed variable's metatable
					DBG.navigate("meta")
				end
			end
		end

		-- Scrolling the environment
		if DBG.isDown("mpos") and index then
			DBG._yScroll = DBG._yScroll + 4
			if DBG._yScroll > #index then
				DBG._yScroll = #index
			end
		elseif DBG.isDown("mneg") and index then
			DBG._yScroll = DBG._yScroll - 4
			if DBG._yScroll < 1 then
				DBG._yScroll = 1
			end
		end
	end

	-- Updates the DBG
	function DBG.update(dt)
		assert(type(dt) == "number", "Argument #1 to DBG.update(dt) must be a number!")

		DBG._tempFade()

		if DBG.isActive() then
			-- Clearing the prompt
			if DBG.isDown(DBG.clearPrompt) then
				DBG._textTable = {}
				DBG._textPosition = 1
			end

			DBG._handleConsoleCycle()
			DBG._handleCursorMovement()
			DBG._handleClipboard()

			local dv, index = DBG._handleEnvUpdate()

			DBG._handleConsoleExecution()

			DBG._clearInputs()
		end

		for i=1, #DBG._updateEvents do
			local s, r = pcall(DBG._updateEvents[i].func, dt)
			if not s then
				DBG.printError(":ERROR:" .. DBG._tostring(r))
			end
		end

		DBG._updateProfiler()

		DBG._updateTime = love_timer.getTime()
	end

	-- Adds a function to the update loop
	local updateEventId = 0

	function DBG.addUpdate(func, prio)
		updateEventId = updateEventId + 1

		local this = {
			func = func,
			prio = prio or 0,
			id = updateEventId
		}

		DBG._updateEvents[#DBG._updateEvents+1] = this
		table.sort(DBG._updateEvents, function(a, b)
			return a.prio > b.prio
		end)

		return updateEventId
	end

	-- Removes a function by ID from the update loop
	function DBG.removeUpdate(id)
		for i=1, #DBG._updateEvents do
			if DBG._updateEvents[i].id == id then
				table.remove(DBG._updateEvents, i)
				return
			end
		end
	end

	DBG.addSource()
end
