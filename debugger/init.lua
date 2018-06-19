--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
local DBG = {}

DBG._PATH = (...):gsub("%.init$", "")

DBG.NOTE1 = "Fields prefixed with '_'"
DBG.NOTE2 = "are internal and undocumented."
DBG.NOTE3 = "Use or modify them at your own"
DBG.NOTE4 = "risk.                  --DPlay"

local function loadModule(mod)
	return require(DBG._PATH .. "." .. mod)(DBG)
end

-- Load all submodules
loadModule "core"
loadModule "config"
loadModule "display"
loadModule "logging"
loadModule "utility"
loadModule "input"
loadModule "update"
loadModule "draw"
loadModule "adv_env"
loadModule "commands"
loadModule "error_handler"
loadModule "profile"

local love = require "love"
local love_graphics = require "love.graphics"

do
	-- Loading font in lua path
	DBG.setFont(love_graphics.getFont())
	local s, lFont = pcall(require, DBG._PATH .. ".font")
	if s then pcall(DBG.setFont, lFont) end
end

do
	-- Safe updating functions that won't cause an error ever
	local xpcall = xpcall

	function DBG.safeUpdate(dt)
		return xpcall(DBG.update, DBG.realPrint, dt)
	end

	local function popNPrint(errormsg)
		love_graphics.pop()
		DBG.realPrint(errormsg)
	end

	function DBG.safeDraw()
		return xpcall(DBG.draw, popNPrint)
	end
end

setmetatable(DBG, {
	__call = function(self)
		-- Auto-Injection
		self.registerHandlers()

		local love_update = love.update
		local love_draw = love.draw

		love.update = love_update and function(...)
			self.safeUpdate(...)
			love_update(...)
		end or self.safeUpdate

		love.draw = love_draw and function(...)
			love_draw(...)
			self.safeDraw()
		end or self.safeDraw

		return self
	end
})

DBG.addSource()

return DBG
