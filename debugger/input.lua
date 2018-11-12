--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local love_keyboard = require "love.keyboard"
	local love_mouse = require "love.mouse"

	local realKeyboard, realMouse, fakeKeyboard, fakeMouse

	local _inputs = {}

	function DBG.isDown(inputId)
		return _inputs[inputId]
	end

	function DBG._clearInputs()
		_inputs = {}
	end

	DBG.callbacks = {
		-- Key-press callback
		keypressed = function(key, scancode, isrepeat)
			_inputs[key] = true
			if key == "backspace" then
				-- Removing text to the left
				if DBG._textTable[DBG._textPosition-1] then
					table.remove(DBG._textTable, DBG._textPosition-1)
					DBG._textPosition = DBG._textPosition - 1
				end

				while realKeyboard.isDown("lctrl", "rctrl") and DBG._textTable[DBG._textPosition-1] and DBG._textTable[DBG._textPosition-1]:find("%w") do
					table.remove(DBG._textTable, DBG._textPosition-1)
					DBG._textPosition = DBG._textPosition - 1
				end
			elseif key == "delete" then
				-- Removing text to the right
				if DBG._textTable[DBG._textPosition] then
					table.remove(DBG._textTable, DBG._textPosition)
				end

				while realKeyboard.isDown("lctrl", "rctrl") and DBG._textTable[DBG._textPosition] and DBG._textTable[DBG._textPosition]:find("%w") do
					table.remove(DBG._textTable, DBG._textPosition)
				end
			end
		end,

		-- Textinput callback
		textinput = function(text)
			if text == "\n" or text == "\r" then text = " " end
			if DBG._font:hasGlyphs(text) then
				table.insert(DBG._textTable, DBG._textPosition, text)
				DBG._textPosition = DBG._textPosition + 1
			end
		end,

		-- Empty key-release
		keyreleased = function() end,

		-- Mouse-press callback
		mousepressed = function(x, y, button, istouch)
			if not istouch then
				_inputs["m"..DBG._tostring(button)] = true
			end
		end,

		-- Empty mouse-release
		mousereleased = function() end,

		-- Empty mouse-movement
		mousemoved = function() end,

		-- Mouse-wheel movement callback
		wheelmoved = function(x, y)
			if y > 0 then
				_inputs.mneg = y
			elseif y < 0 then
				_inputs.mpos = -y
			end
		end
	}

	do
		local registeredHandlers = false

		-- Registers the handlers to the default love.handlers
		function DBG.registerHandlers()
			if registeredHandlers then return end

			registeredHandlers = true

			for event, debuggerFunc in pairs(DBG.callbacks) do
				local loveHandler = love.handlers[event]

				if event == "keypressed" then
					love.handlers[event] = function(...)
						if ... == DBG.activate then
							DBG.setActive(not DBG.isActive())
						end
						if DBG.isActive() then
							return debuggerFunc(...)
						else
							if ... == DBG.clearPrompt then
								DBG.doTempPrint = not DBG.doTempPrint
							end
							return loveHandler(...)
						end
					end
				else
					love.handlers[event] = function(...)
						return (DBG.isActive() and debuggerFunc or loveHandler)(...)
					end
				end
			end
		end
	end

	-- Making sure inputs are not sent to the game while the console is in use.
	realKeyboard = {
		isDown = love_keyboard.isDown,
		isScancodeDown = love_keyboard.isScancodeDown,
		setKeyRepeat = love_keyboard.setKeyRepeat,
		hasKeyRepeat = love_keyboard.hasKeyRepeat,
		setTextInput = love_keyboard.setTextInput,
		hasTextInput = love_keyboard.hasTextInput
	}

	realMouse = {
		isDown = love_mouse.isDown,
		setVisible = love_mouse.setVisible,
		isVisible = love_mouse.isVisible,
	}

	DBG._keyboard = realKeyboard
	DBG._mouse = realMouse

	local mousevisible = false
	local keyrepeat = false
	local hastextinput = false
	local rfalse = function() return false end

	fakeKeyboard = {
		isDown = rfalse,
		isScancodeDown = rfalse,
		setKeyRepeat = function(rep)
			if type(rep) == "boolean" then
				keyrepeat = rep
			end
		end,
		hasKeyRepeat = function()
			return keyrepeat
		end,
		setTextInput = function(new)
			hastextinput = new
		end,
		hasTextInput = function()
			return hastextinput
		end
	}

	fakeMouse = {
		isDown = rfalse,
		setVisible = function(visible)
			if type(visible) == "boolean" then
				mousevisible = visible
			end
		end,
		isVisible = function()
			return mousevisible
		end
	}

	local active = false

	-- Setting the current status of the DBG
	function DBG.setActive(status)
		status = status and true
		if status ~= active then
			active = status
			if active then
				-- Enabling
				mousevisible = love_mouse.isVisible()
				love_mouse.setVisible(true)
				keyrepeat = love_keyboard.hasKeyRepeat()
				love_keyboard.setKeyRepeat(true)
				hastextinput = love_keyboard.hasTextInput()
				love_keyboard.setTextInput(true)

				for k,v in next, fakeKeyboard do
					love_keyboard[k] = v
				end
				for k,v in next, fakeMouse do
					love_mouse[k] = v
				end
			else
				-- Disabling
				for k,v in next, realKeyboard do
					love_keyboard[k] = v
				end
				for k,v in next, realMouse do
					love_mouse[k] = v
				end

				love_mouse.setVisible(mousevisible)
				love_keyboard.setKeyRepeat(keyrepeat)
				love_keyboard.setTextInput(hastextinput)
			end
		end
	end

	-- Returns the activity status of the DBG
	function DBG.isActive()
		return active
	end

	DBG.addSource()
end
