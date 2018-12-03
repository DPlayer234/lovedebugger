--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
local DBG = {}

DBG._PATH = (...):gsub("%.init$", "")

DBG[1] = "Modifications are at your"
DBG[2] = "own risk. HF!      -DPlay"

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
loadModule "func_index"
loadModule "adv_env"
loadModule "commands"
loadModule "error_handler"
loadModule "profile"
loadModule "persist"

local love = require "love"
local love_graphics = require "love.graphics"

-- Loading font in Lua path
do
	DBG.setFont(love_graphics.getFont())
	local s, lFont = pcall(require, DBG._PATH .. ".font")
	if s then pcall(DBG.setFont, lFont) end
end

-- Safe updating functions that won't cause an error ever
do
	local xpcall = xpcall

	function DBG.safeUpdate(dt)
		return xpcall(DBG.update, DBG.lua_print, dt)
	end

	local function popNPrint(errormsg)
		love_graphics.pop()
		DBG.lua_print(errormsg)
	end

	function DBG.safeDraw()
		return xpcall(DBG.draw, popNPrint)
	end
end

setmetatable(DBG, {
	__call = function(self)
		-- Auto-Injection
		self.registerHandlers()
		self.loadPersistent()

		local love_update = love.update
		local love_draw = love.draw
		local love_quit = love.quit

		love.update = love_update and function(...)
			self.safeUpdate(...)
			love_update(...)
		end or self.safeUpdate

		love.draw = love_draw and function(...)
			love_draw(...)
			self.safeDraw()
		end or self.safeDraw

		love.quit = love_quit and function(...)
			self.savePersistent()
			return love_quit()
		end or self.savePersistent

		return self
	end
})

DBG.hideFields(DBG, "^_")

DBG.addSource()

return DBG
