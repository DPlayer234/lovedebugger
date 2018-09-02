--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	-- If you want to use the DBG as an error-handler.
	-- Will probably fail if the error was a stack overflow.
	-- Can also be used as a pseudo-breakpoint by calling in within your code:
	-- To continue, try to close the application.
	function DBG.errorhandler(message, stack)
		message = message or ""
		stack = stack or 2

		local debug = require "debug"
		local love = require "love"
		local timer = require "love.timer"
		local event = require "love.event"
		local graphics = require "love.graphics"
		local window = require "love.window"

		local xpcall, print = xpcall, print

		-- Get traceback message
		_stackTraceback = debug.traceback(message, stack)
		DBG.printError(_stackTraceback)

		-- Get locals on stack
		_stackLocals = DBG.getStack(stack)
		if not DBG.isFunctionIndexAllowed() then
			DBG.allowFunctionIndex(true)
		end

		if not window.isOpen() then
			-- Open a window if there is none
			local w, h = love.window.getDesktopDimensions()
			love.window.setMode(w * (2/3), h * (2/3), { resizable = true })
		end

		graphics.reset()
		DBG.setActive(false) DBG.setActive(true)

		local dt = 0
		timer.step()

		-- Loop. Is exited when the 'quit' event is triggered.
		return function()
			event.pump()
			for name, a,b,c,d,e,f in event.poll() do
				if name == "quit" then
					return a or 0
				elseif DBG.callbacks[name] then
					xpcall(DBG.callbacks[name], print, a, b, c, d, e, f)
				end
			end
			dt = timer.step()

			xpcall(DBG.update, print, dt)
			if graphics.isActive() then
				graphics.clear(0.00, 0.35, 0.70)
				if not xpcall(DBG.draw, print) then love.graphics.pop() end
				graphics.present()
			end

			timer.sleep(0.01)
		end
	end

	-- Alias
	DBG.errhand = DBG.errorhandler

	DBG.addSource()
end
