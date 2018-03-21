--[[
Copyright © 2017 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]

local debugger = {}
local profile

debugger.activate     = "f4"   -- Löve KeyConstant of the key used to open the console. (Default: 'f4')
debugger.clearPrompt  = "f5"   -- Löve KeyConstant of the key used to clear the Lua prompt and toggle 'debugger.doTempPrint'. (Default: 'f5')
debugger.textfade     = 7      -- Time it takes for text to fade away after its 'print' call in seconds.
debugger.printArea    = 2/3    -- Screen Area where the prints are displayed (ratio 0.0-1.0). (Default: 2/3)
debugger.doTempPrint  = true   -- Whether or not to print to the screen if the console is closed.
debugger.maxStorage   = 100    -- How many console inputs are stored to be reused (by using 'Up' and 'Down' arrow keys). (Default: 100)
debugger.useTitleBar  = true   -- Whether or not to print FPS, Lua Ram Usage and update time to the window title bar. (Default: true)
debugger.replaceTabs  = "    " -- Replace tab character in prints with the specified string.

debugger.color = {             -- Various colors used
	-- Active:
	bgActive = {0.00,0.00,0.00,0.50},
	fgActive = {1.00,1.00,1.00,1.00},
	fgActive2= {0.80,0.80,1.00,1.00},
	-- Not Active:
	bgNotActive = {0.00,0.00,0.00,0.35},
	fgNotActive = {1.00,1.00,1.00,0.70},
	-- Other:
	white = {1.00,1.00,1.00},
	black = {0.00,0.00,0.00},
	red   = {1.00,0.35,0.35},
	blue  = {0.35,0.35,1.00},
	green = {0.35,1.00,0.35},
	yellow= {1.00,0.80,0.15},
}

-- Call debugger.setFont(Font:Löve-Font-Object) to set the font used by the debugger; default is the font set during initialization.
-- debugger.print(...) will print text to the debugger's console exclusively.
-- Controller/Joystick inputs won't be disabled, so feel free to use a controller while testing/debugging.
local require = require

local debug = require "debug"
local utf8 = require "utf8"
local love = require "love"
local love_keyboard = require "love.keyboard"
local love_mouse = require "love.mouse"
local love_graphics = require "love.graphics"
local love_event = require "love.event"
local love_timer = require "love.timer"

local collectgarbage = collectgarbage
local setmetatable, getmetatable = setmetatable, debug.getmetatable
local rawset, rawget = rawset, rawget

local table, string, math = table, string, math
local insert, remove, concat, sort = table.insert, table.remove, table.concat, table.sort
local floor, ceil, abs = math.floor, math.ceil, math.abs
local sub, gsub, gmatch, format, find = string.sub, string.gsub, string.gmatch, string.format, string.find
local utf8_len, utf8_codes, utf8_char, utf8_offset = utf8.len, utf8.codes, utf8.char, utf8.offset

-- Fake nil value inserted where nil is needed.
local fakeNil
do
	local fakeNilMeta = {
		__tostring = function() return "nil" end,
		type = function() return "*nil" end
	}
	fakeNilMeta.__index = fakeNilMeta
	fakeNil = setmetatable({}, fakeNilMeta)
end

local type = type
local pcall = pcall
local loadstring = loadstring or load
local pairs, next, ipairs = pairs, next, ipairs
local _tostring, tonumber = tostring, tonumber
local error = error
local tostring = function(t)
	local s, r = pcall(_tostring, t)
	return s and r or ":ERROR:"
end

-- Safely gets a value without calling anything
local function safeIndex(table, key, depth)
	depth = depth or 0
	if depth > 5 then return end -- Prevent endlessly looping
	local mt = getmetatable(table)
	if mt == nil then -- No metatable
		if type(table) ~= "table" then return end -- Not a table
		return table[key] -- Return value
	end
	local index = rawget(mt, "__index")
	if type(index) == "table" then return safeIndex(index, key, depth + 1) end -- Get field from __index
	if type(table) == "table" then return rawget(table, key) end -- Get field from original table
end

-- Used to display alternative type
local typeReal = function(v)
	local t = type(v)
	local tf = safeIndex(v, "type")
	if tf and tf ~= type then
		if type(tf) == "string" then return t .. ":" .. tf end
		local s, r = pcall(tf, v)
		if s and type(r) == "string" then return t .. ":" .. r end
	end
	return t
end

debugger.fakeNil = fakeNil
debugger.safeIndex = safeIndex
debugger.typeReal = typeReal

-- Dependencies, yes, I require those. *BADUM-TSS*
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
			title = tostring(new)
		else
			error("Bad argument #1 to '?' (string expected, got "..typeReal(new)..")", 2)
		end
		titleManager.titleUpdated = true
	end
else
	titleManager.getTitle = --[[]]function()return""end
	titleManager.setTitle = --[[]]function()end
	titleManager.titleUpdated = false
end

local function cloneList(t)
	local n = {}
	for i=1, #t do
		n[i] = t[i]
	end
	return n
end

-- Setting the font
local font, fheight
function debugger.setFont(nfont)
	assert( typeReal(nfont) == "userdata:Font", ":Not a font." )

	font = nfont
	fheight = font:getHeight()*font:getLineHeight()
end
function debugger.getFont()
	return font
end

do
	-- Loading font in lua path
	debugger.setFont(love_graphics.getFont())
	local s, lFont = pcall(require, "debugger_font")
	if s then pcall(debugger.setFont, lFont) end
end

-- Print Calls / Wrapping the 'regular' print
local lg = {}
local lgtemp = {}
local lgtime = {}
local color = debugger.color

local function checkUtf8(s) return utf8_len(s) and true end
local function getLines(sf)
	local nl = 0
	for i=1, #sf do
		local v = sf[i]
		if type(v) == "string" then
			local _, n = gsub(v, "\n", "\n")
			nl = nl + n
		end
	end
	return nl
end

local lastPrint, printedTimes
local function proxyPrint(c, ...)
	local args = {...}
	local top = 0
	for i,v in next, args do
		args[i] = gsub(tostring(v), "[%z\r]", "")
		local valid = checkUtf8(args[i])
		if not valid then
			args[i] = ":ERROR: (utf8)"
		elseif debugger.replaceTabs then
			args[i] = gsub(args[i], "\t", debugger.replaceTabs)
		end
		if i > top then top = i end
	end
	for i=1, top do
		if args[i] == nil then
			args[i] = "nil"
		end
	end

	if #args < 1 then args[1] = "nil" end
	args[#args+1] = "\n"

	local t = concat(args, debugger.replaceTabs or "\t")

	if t ~= lastPrint then
		local time = love_timer.getTime()
		for s in gmatch(t, "[^\n]*\n") do
			insert(lg, c)
			insert(lg, s)

			insert(lgtemp, c)
			insert(lgtemp, s)

			insert(lgtime, time)
		end

		while #lg > 2 and #lg*0.5 > love_graphics.getHeight()/fheight - 1 do
			remove(lg, 1)
			remove(lg, 1)
		end

		while #lgtemp > 2 and #lgtemp*0.5 > love_graphics.getHeight()/fheight - 1 do
			remove(lgtemp, 1)
			remove(lgtemp, 1)
		end

		lastPrint = t
		printedTimes = 1
	else
		printedTimes = printedTimes + 1
		if printedTimes == 2 then
			lg[#lg] = "(2x) "..lg[#lg]
		else
			lg[#lg] = gsub(lg[#lg], "^%(%d+x%)", "("..tostring(printedTimes).."x)")
		end
		if #lgtemp > 1 then
			lgtemp[#lgtemp] = lg[#lg]
			lgtime[#lgtime] = love_timer.getTime()
		else
			lgtemp[1] = lg[#lg-1]
			lgtemp[2] = lg[#lg]
			lgtime[1] = love_timer.getTime()
		end
	end
end

local realPrint = print
debugger.print = proxyPrint
debugger.realPrint = realPrint

function debugger.allPrint(...)
	realPrint(...)
	return proxyPrint(color.white, ...)
end

print = debugger.allPrint

local function printColor(c, text)
	realPrint(text)
	return proxyPrint(c, text)
end

-- Clearing print calls
function debugger.clear()
	for k,v in next, lg do lg[k] = nil end
	debugger.tempClear()
end

function debugger.tempClear()
	for k,v in next, lgtemp do lgtemp[k] = nil end
	for k,v in next, lgtime do lgtime[k] = nil end
end

-- This function will affect the order of the environment display.
-- You may rewrite this: It should get a table and return an array with the KEYS of the origCallback table as its VALUES.
-- E.g. sortedTable({ x = 5, y = 2, a = "test" }) -> { "a", "x", "y" }
local function sortCont(a, b) if type(a) == type(b) then return a<b else return tostring(a)<tostring(b) end end
local function sortedTable(t, to)
	local tx
	if to then
		for k,v in next, to do to[k] = nil end
		tx = to
	else
		tx = {}
	end

	for k,v in next, t do
		tx[#tx+1] = k
	end
	pcall(sort, tx, sortCont) -- <= Real Sorting
	return tx
end

local display = "_G"
local yScroll = 1
local textPosition = 1
local inputs = {}
local index = {}

local active = false
local textinput = ""
local texttable = {}
local lastselect = 0
local lastinput = {}
local commands = {}

-- Storing origCallback callbacks/overriding them to be used
local realKeyboard, realMouse, fakeKeyboard, fakeMouse

debugger.callbacks = {
	keypressed = function(key, scancode, isrepeat)
		inputs[key] = true
		if key == "backspace" then
			if texttable[textPosition-1] then
				remove(texttable, textPosition-1)
				textPosition = textPosition - 1
			end
			while realKeyboard.isDown("lctrl", "rctrl") and texttable[textPosition-1] and find(texttable[textPosition-1], "%a") do
				remove(texttable, textPosition-1)
				textPosition = textPosition - 1
			end
		elseif key == "delete" then
			if texttable[textPosition] then
				remove(texttable, textPosition)
			end
			while realKeyboard.isDown("lctrl", "rctrl") and texttable[textPosition] and find(texttable[textPosition], "%a") do
				remove(texttable, textPosition)
			end
		end
	end,
	textinput = function(text)
		if text == "\n" or text == "\r" then text = " " end
		if font:hasGlyphs(text) then
			insert(texttable, textPosition, text)
			textPosition = textPosition + 1
		end
	end,
	keyreleased = function() end,
	mousepressed = function(x, y, button, istouch)
		if not istouch then
			inputs["m"..tostring(button)] = true
		end
	end,
	mousereleased = function() end,
	mousemoved = function() end,
	wheelmoved = function(x, y)
		if y > 0 then
			inputs.mneg = y
		elseif y < 0 then
			inputs.mpos = -y
		end
	end
}

do
	local registeredHandlers = false
	-- Registers the handlers to the default love.handlers
	function debugger.registerHandlers()
		if registeredHandlers then return end
		registeredHandlers = true
		for event, debuggerFunc in pairs(debugger.callbacks) do
			local loveHandler = love.handlers[event]

			if event == "keypressed" then
				love.handlers[event] = function(...)
					if ... == debugger.activate then
						debugger.setActive(not active)
					end
					if active then
						return debuggerFunc(...)
					else
						if ... == debugger.clearPrompt then
							debugger.doTempPrint = not debugger.doTempPrint
						end
						return loveHandler(...)
					end
				end
			else
				love.handlers[event] = function(...)
					return (active and debuggerFunc or loveHandler)(...)
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

-- Setting the current status of the debugger
function debugger.setActive(status)
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

local indexFunctions, prettyFunctions = false, false
local updateEvents = {}

local updateTime = 0
-- Update Function
local fromPattern = "%[\"[_a-zA-Z][_a-zA-Z0-9]-\"%]"
local nicerPush = function(t) return "."..sub(t, 3, #t-2) end
function debugger.update(dt)
	assert(type(dt) == "number", "Argument #1 to debugger.update(dt) must be a number!")

	if #lgtime > 0 then
		local ctime = love_timer.getTime()
		if lgtime[1] + debugger.textfade < ctime then
			remove(lgtemp, 1)
			remove(lgtemp, 1)
			remove(lgtime, 1)
		end
	end

	if active then
		if inputs[debugger.clearPrompt] then
			texttable = {}
			textPosition = 1
		end
		-- Getting previous inputs
		if inputs.up then
			if lastselect < #lastinput then
				if lastselect == 0 and #texttable > 0 then
					insert(lastinput, 1, texttable)
					lastselect = 2
				else
					lastselect = lastselect + 1
				end
				texttable = cloneList(lastinput[lastselect])
				textPosition = #texttable+1
			end
		elseif inputs.down then
			if lastselect > 0 then
				lastselect = lastselect - 1
				if lastselect == 0 then
					texttable = {}
				else
					texttable = cloneList(lastinput[lastselect])
				end
				textPosition = #texttable+1
			end
		end

		if (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("v")) or (realKeyboard.isDown("lctrl", "rctrl") and inputs.v) or inputs.insert) and love.system then
			local cbt = love.system.getClipboardText()
			if type(cbt) == "string" then
				for p,c in utf8_codes(cbt) do
					debugger.callbacks.textinput(utf8_char(c))
				end
			end
		elseif (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("c")) or (realKeyboard.isDown("lctrl", "rctrl") and inputs.c)) and love.system then
			love.system.setClipboardText(concat(texttable, ""))
		end

		if inputs["return"] and #texttable > 0 then
			-- Handling console execution.
			textinput = concat(texttable, "")

			-- Storing current input to be reused
			insert(lastinput, 1, texttable)
			lastselect = 0
			if #lastinput > debugger.maxStorage then
				remove(lastinput, #lastinput)
			end

			texttable = {}
			textPosition = 1
			if find(textinput, "^[/\\!:%.%*]") then
				-- A command. Has to be.
				local args = {}
				local inString, string = false, nil
				for match in gmatch(textinput, "%S+") do
					if inString then
						if match:find("\"$") then
							args[#args+1] = string .. " " .. match:sub(1, #match-1)
							inString, string = false, nil
						else
							string = string .. " " .. match
						end
					elseif match:find("^\".*[^\"]$") then
						inString, string = true, match:sub(2, #match)
					else
						args[#args+1] = match
					end
				end

				local one = remove(args, 1)
				local command = commands[sub(one, 2, #one)]
				if command then
					local pattern = "^"
					for i=1, #args do
						local v = args[i]
						if tonumber(v) then
							pattern = pattern.."[bns]"
						elseif v == "true" or v == "false" then
							pattern = pattern.."[bs]"
						else
							pattern = pattern.."s"
						end
					end
					pattern = pattern.."$"

					local this
					for i=1, #command do
						local v = command[i]
						if pattern == "" then
							if v.args == "" then
								this = v
								break
							end
						elseif find(v.args, pattern) then
							this = v
							break
						end
					end

					if this then
						local i = 0
						for c in gmatch(this.args, ".") do
							i = i + 1
							if c == "n" then
								args[i] = tonumber(args[i])
							elseif c == "b" then
								args[i] = args[i] ~= "false" and args[i] ~= "0"
							end
						end

						local s,out = pcall(this.func, unpack(args))
						if s then
							printColor(color.yellow, out or ":Executed.")
						else
							printColor(color.red, ":ERROR:"..tostring(out))
						end
					else
						printColor(color.red, ":ERROR:Incorrect arguments...")
					end
				else
					printColor(color.red, ":ERROR:Unknown command. Add commands with debugger.newCommand(name, args, function)")
				end
			elseif textinput:match("[_a-zA-Z0-9%.%[%]\"']+%s*=[^=].*") == textinput then
				-- Probably Variable assignment
				local success, err = pcall(loadstring("local getmetatable=...;"..textinput, "prompt"), getmetatable)
				if success then
					printColor(color.yellow, ":Set variable "..textinput)
				else
					printColor(color.red, ":ERROR:"..tostring(err))
				end
			else
				-- Attempting return to print that on the screen
				local f = loadstring("local getmetatable=...;return "..textinput, "prompt")
				if not f then
					f = loadstring("local getmetatable=...;"..textinput, "prompt")
				end
				local r = { pcall(f, getmetatable) }
				if r[1] == true then
					if #r > 1 then
						local max = 0
						for i,v in next, r do if i > max then max = i end end
						r[1] = ":Return values"
						for i=2, max do
							local v = r[i]
							if v == nil then
								r[i] = "["..tostring(i-1).."] (nil)"
							else
								r[i] = "["..tostring(i-1).."] ("..typeReal(v)..") "..tostring(v)
							end
						end
						if #r > 0 then
							printColor(color.yellow, concat(r, "\n\t"))
						end
					end
				else
					printColor(color.red, ":ERROR:"..tostring(r[2]))
				end
			end
		end

		-- Other crap with the environment (mostly navigation)
		local s, dv = pcall(loadstring("local getmetatable=... return "..display), getmetatable)

		if type(dv) == "table" then
			index = sortedTable(dv, index)
		elseif indexFunctions and type(dv) == "function" then
			index = sortedTable(dv.___allupvaluenames, index)
		end
		if not s then dv = nil end

		if (inputs.m1 or inputs.m2) then
			if love_mouse.getX() >= ceil(love_graphics.getWidth()*debugger.printArea) then
				local nid = floor(love_mouse.getY()/fheight-2)
				local shift = realKeyboard.isDown("lshift", "rshift")

				if nid >= 0 then
					-- Clicked on a variable
					local ntext = index[nid+yScroll]
					if ntext and (type(dv) == "table" or (indexFunctions and type(dv) == "function")) then
						-- Getting variable name:
						local ndisplay = ""
						local ntype = type(ntext)
						if ntype ~= "string" and ntype ~= "number" then ntext = tostring(ntext) end
						if display == "_G" then
							ndisplay = ntext
						else
							ndisplay = display.."["..(ntype=="string" and format("%q", ntext) or tostring(ntext)).."]"
						end

						local s, dv = pcall(loadstring("local getmetatable=... return "..ndisplay), getmetatable)
						if s and type(dv) == "table" and inputs.m1 then
							-- LMB
							-- Navigating to another table
							display = ndisplay
							index = sortedTable(dv, index)

							yScroll = 1
						elseif shift then
							-- Holding Shift
							if inputs.m2 then
								-- RMB
								-- Navigating to its metatable
								local m = getmetatable(dv)

								if type(m) == "table" then
									display = "getmetatable("..ndisplay..")"
									index = sortedTable(m, index)
									yScroll = 1
								end
							elseif indexFunctions and type(dv) == "function" then
								-- LMB
								-- Navigating to a function's upvalues
								display = ndisplay
								index = sortedTable(dv.___allupvalues, index)

								yScroll = 1
							end
						else
							-- Copying the variable name to the prompt
							for p,c in utf8_codes(gsub(ndisplay, fromPattern, nicerPush)) do
								debugger.callbacks.textinput(utf8_char(c))
							end
						end
					else
						-- Copying the variable name to the prompt
						for p,c in utf8_codes(gsub(display, fromPattern, nicerPush)) do
							debugger.callbacks.textinput(utf8_char(c))
						end
					end
				else
					-- Clicked on the top
					if inputs.m2 then
						-- Navigating to the currently indexed variable's metatable
						local m = getmetatable(dv)

						if type(m) == "table" then
							display = "getmetatable("..display..")"
							index = sortedTable(m, index)
							yScroll = 1
						end
					else
						-- Navigating to its parent
						local s = display

						if find(s, "^getmetatable%(.*%)$") then
							display = sub(s, 14, #s-1)
						elseif find(s, "%(%)$") then
							display = sub(s, 1, #s-2)
						else
							local e, _e = find(s, "%[")
							if e then s = sub(s, e+1, #s) end
							local r = 0
							while e do
								r = r + e
								e, _e = find(s, "%[")
								if e then s = sub(s, e+1, #s) end
							end

							if r > 0 then
								display = sub(display, 1, r-1)
							else
								display = "_G"
							end
						end

						local s, dv = pcall(loadstring("local getmetatable=... return "..display), getmetatable)
						if s then
							if type(dv) == "table" then
								index = sortedTable(dv, index)
							elseif indexFunctions and type(dv) == "function" then
								index = sortedTable(dv.___allupvalues, index)
							end
						end

						yScroll = 1
					end
				end
			end
		end

		-- Scrolling the environment
		if inputs.mpos then
			yScroll = yScroll + 4
			if yScroll > #index then
				yScroll = #index
			end
		elseif inputs.mneg then
			yScroll = yScroll - 4
			if yScroll < 1 then
				yScroll = 1
			end
		end

		-- Scrolling the cursor through the text
		if inputs.right and textPosition <= #texttable then
			textPosition = textPosition + 1
		elseif inputs.left and textPosition > 1 then
			textPosition = textPosition - 1
		end

		for k,v in next, inputs do
			inputs[k] = nil
		end
	end

	for i=1, #updateEvents do
		local s, r = pcall(updateEvents[i].func, dt)
		if not s then
			printColor(color.red, ":ERROR:"..tostring(r))
		end
	end

	if profile ~= nil and profile.running then
		profile.frame = profile.frame + 1
		if profile.frame % profile.interval == 0 then
			profile.addReport()
			profile.lib.reset()
		end
	end

	updateTime = love_timer.getTime()
end

function debugger.addUpdate(func, prio)
	local this = {
		func = func,
		prio = prio or 0
	}

	updateEvents[#updateEvents+1] = this
	sort(updateEvents, function(a, b)
		return a.prio > b.prio
	end)

	for i=1, #updateEvents do
		if updateEvents[i] == this then
			return i
		end
	end
end

local function count(str, patt)
	local _, c = gsub(str, patt, "")
	return c
end

-- Draw Function(s)

local reppatt = "[\r\n\t\v\\%z\"]"
local rep = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\\"] = "\\\\", ["\0"] = "\\0", ["\""] = "\\\"" }
-- Printing the Lua prompt
local function promtPrint(w, h, fheight)
	local prompt = concat(texttable)
	local width = font:getWidth(prompt)
	local x = width < w and 0 or w-width
	love_graphics.print(prompt, x, h-fheight)
	if love_timer.getTime()%0.5 >= 0.25 then
		if textPosition > #texttable then
			love_graphics.rectangle("fill", font:getWidth(prompt), h-fheight, font:getWidth(" "), fheight)
		else
			love_graphics.rectangle("fill", font:getWidth(concat(texttable, "", 1, textPosition-1))+x, h-fheight, font:getWidth(concat(texttable, "", textPosition, textPosition))-1, fheight)
		end
	end
end

local getAdditionalInfo = function() end

local infoTitleFormat = "%s [%d FPS] [%.1f KB] [%.6f s.]"
local function infoTitle(title, fps, ram, time)
	local s, r = pcall(format, infoTitleFormat, title, fps, ram, time, getAdditionalInfo())
	return r
end

local infoBoxFormat = "%d FPS\n~%.1f KB\n%.6f s."
local function infoBox(fps, ram, time)
	local s, r = pcall(format, infoBoxFormat, fps, ram, time, getAdditionalInfo())
	return r
end

local __infoTitleFormat, __infoBoxFormat = infoTitleFormat, infoBoxFormat
-- Drawing everything
function debugger.draw()
	-- Storing the current graphics state and resetting it
	love_graphics.push()
	love_graphics.origin()

	local ram = collectgarbage("count")

	fheight = abs(font:getHeight()*font:getLineHeight())

	local oldfont = love_graphics.getFont()
	love_graphics.setFont(font)

	local xs, ys, ws, hs = love_graphics.getScissor()
	love_graphics.setScissor()

	local oldshader = love_graphics.getShader()
	love_graphics.setShader()

	local blendmode, alphablendmode = love_graphics.getBlendMode()
	love_graphics.setBlendMode("alpha")

	local rm, gm, bm, am = love_graphics.getColorMask()
	love_graphics.setColorMask(true, true, true, true)

	local wireframe = love_graphics.isWireframe()
	love_graphics.setWireframe(false)

	local r, g, b, a = love_graphics.getColor()
	local w, h = love_graphics.getDimensions()

	if active then
		-- Prompt and Environment is opened
		local tt = ceil(w*debugger.printArea)

		local _, wrap = font:getWrap(lg, tt)
		local hlg = #wrap*fheight

		local varprint
		local success, v = pcall(loadstring("local getmetatable=... return "..display), getmetatable)
		local vartype
		if success and v then
			varprint = v
			vartype = type(varprint)
			if indexFunctions and vartype == "function" then
				varprint = v.___allupvalues
			end
		else
			varprint = "Invalid path"
			vartype = "nil"
		end

		local printType, indexType = {}, 1
		local printName, indexName = {}, 1
		local printData, indexData = {}, 1

		local function addType(arg)
			printType[indexType] = arg
			indexType = indexType + 1
		end
		local function addName(arg)
			printName[indexName] = arg
			indexName = indexName + 1
		end
		local function addData(arg)
			printData[indexData] = sub(arg, 1, 150)
			indexData = indexData + 1
		end

		local maxLines = ceil(h/fheight)

		if vartype == "table" or (indexFunctions and vartype == "function") then
			-- Indexable
			local order = index
			for i=1, #order do
				if i >= yScroll and i <= maxLines + yScroll - 4 then
					local k = order[i]
					local v = varprint[k]

					addType(typeReal(v))

					local name = gsub(tostring(k), reppatt, rep)
					if checkUtf8(name) then
						addName(name)
					else
						addName(":ERROR: (utf8)")
					end

					local data
					if type(v) == "string" then
						data = '"'..gsub(v, reppatt, rep)..'"'
					else
						data = gsub(tostring(v), reppatt, rep)
					end
					if checkUtf8(data) then
						addData(data)
					else
						addData(":ERROR: (utf8)")
					end
				elseif i > maxLines + yScroll - 4 then
					break
				end
			end

			addType("\t>>>\n")
			addName("")
		else
			addType(gsub(tostring(varprint), " ", " ").."\n\t>>>\n")
		end

		-- Variable Path
		local path = gsub(gsub(gsub(gsub((display == "_G" and "..." or "> "..display), "getmetatable%(", "Meta("), "%[\"", " > "), "\"%]", ""), " ", " ")
		if font:getWidth("\t"..path) > w-tt then
			while font:getWidth("\t…"..path) > w-tt do
				local byteoffset = utf8_offset(path, 2)
				if byteoffset then
					path = sub(path, byteoffset, #path)
				else
					break
				end
			end
			path = "…"..path
		end

		local stringType = concat(printType, " \n")
		local stringName = concat(printName, " \n")
		local stringData = concat(printData, "\n")

		local header = ("\t%s\n\tType: %s %03dy\t"):format(path, typeReal(varprint):gsub(" ", " "), yScroll)
		if not debugger.useTitleBar then
			header = header .. " ~"..floor(ram+0.5).." KB "..love_timer.getFPS().." FPS"
		end
		local hprinted = count(stringType, "\n")*fheight

		-- Printed text and Prompt
		love_graphics.setColor(color.bgActive)
		love_graphics.rectangle("fill", 0, 0, tt-1, hlg)
		love_graphics.rectangle("fill", 0, ceil(h-fheight), w, fheight)

		love_graphics.setColor(color.fgActive)
		if debugger.printArea > 0 then
			love_graphics.setScissor(0, 0, tt-1, hlg)
			love_graphics.printf(lg, 0, 0, tt, "left")
			love_graphics.setScissor()
		end

		pcall(promtPrint, w, h, fheight)

		-- Environment Display
		if debugger.printArea < 1 then
			local wt = w - tt
			local wh = ceil(h-fheight-1)
			local tw = ceil(wt * 0.25)
			local nw = ceil(wt * 0.25)

			love_graphics.setScissor(tt, 0, wt, wh)

			love_graphics.setColor(color.bgActive)
			love_graphics.rectangle("fill", tt, 0, wt, hprinted+fheight*2)

			love_graphics.setColor(color.fgActive2)
			love_graphics.printf(header, tt, 0, wt, "justify")

			love_graphics.setColor(color.fgActive)

			love_graphics.setScissor(tt, 0, tw, wh)
			love_graphics.print(stringType, tt, fheight*2)

			love_graphics.setScissor(tt + tw + nw, 0, wt - tw - nw, wh)
			love_graphics.print(stringData, tt + tw + nw, fheight*2)

			love_graphics.setScissor(tt + tw, 0, nw, wh)
			love_graphics.setColor(color.fgActive2)
			love_graphics.print(stringName, tt + tw, fheight*2)
		end
	elseif debugger.doTempPrint then
		-- Printing the print calls
		local updateDif = love_timer.getTime() - updateTime
		local tt = ceil(w*debugger.printArea)-1

		local _, wrap = font:getWrap(lgtemp, tt)
		local hlg = #wrap*fheight
		local tw, wrap, infoText

		love_graphics.setColor(color.bgNotActive)
		love_graphics.rectangle("fill", 0, 0, tt, hlg)
		if not debugger.useTitleBar then
			infoText = infoBox(love_timer.getFPS(), ram, updateDif)
			tw, wrap = font:getWrap(infoText, w)
			love_graphics.rectangle("fill", w-tw, 0, tw, #wrap*fheight)
		end

		love_graphics.setColor(color.fgNotActive)
		if debugger.printArea > 0 then
			love_graphics.printf(lgtemp, 0, 0, tt, "left")
		end
		if not debugger.useTitleBar then
			love_graphics.printf(infoText, w-tw, 0, tw, "right")
		end
	elseif not debugger.useTitleBar then
		-- Not printing the print calls
		local updateDif = love_timer.getTime() - updateTime
		local infoText = infoBox(love_timer.getFPS(), ram, updateDif)
		local tw, wrap = font:getWrap(infoText, w)

		love_graphics.setColor(color.bgNotActive)
		love_graphics.rectangle("fill", w-tw, 0, tw, #wrap*fheight)

		love_graphics.setColor(color.fgNotActive)
		love_graphics.printf(infoText, w-tw, 0, tw, "right")
	end

	if debugger.useTitleBar then
		titleManager.setTitle(infoTitle(titleManager.getRegularTitle(), love_timer.getFPS(), ram, love_timer.getTime()-updateTime))
	elseif titleManager.titleUpdated then
		titleManager.setTitle(titleManager.getRegularTitle())
		titleManager.titleUpdated = false
	end

	-- Returning the graphics state
	love_graphics.pop()
	love_graphics.setFont(oldfont)
	love_graphics.setScissor(xs, ys, ws, hs)
	love_graphics.setColor(r, g, b, a)
	love_graphics.setShader(oldshader)
	love_graphics.setBlendMode(blendmode, alphablendmode)
	love_graphics.getColorMask(rm, gm, bm, am)
	love_graphics.setWireframe(wireframe)
end

function debugger.isActive()
	return active
end

local notInDebugger
do
	local traceback = debug.traceback

	local codepath = traceback():match("^stack traceback:%s*(.-):")
	local allowed = "[string \"prompt\"]:1:"

	function notInDebugger()
		local tb = traceback("", 3)

		if find(tb, codepath, 1, true) then return false end
		if find(tb, allowed , 1, true) then return false end
		return true
	end
end

-- Up-Value-getter
function debugger.allowFunctionIndex(desc)
	indexFunctions = true
	printColor(color.red, "\tAllowing the indexing of functions!\nAccess to indexing is only allowed within the command line.")

	local getupvalue = debug.getupvalue
	local setupvalue = debug.setupvalue
	local traceback  = debug.traceback
	local getinfo = debug.getinfo

	local filesystem = require("love.filesystem")
	local isFile = function(path)
		local info = filesystem.getInfo(path)
		return info and info.type == "file"
	end
	local lines = filesystem.lines

	local upval = setmetatable({}, {__mode = "kv"})
	local ret = setmetatable({}, {__mode = "kv", __index=function()return{}end})
	local retn = setmetatable({}, {__mode = "kv"})
	local getlist = function(f)
		if upval[f] then
			return upval[f]
		else
			local fup = {}

			local i = 1
			local k, v = getupvalue(f, i)
			while k do
				fup[k] = i
				i = i + 1
				k, v = getupvalue(f, i)
			end

			upval[f] = fup
			return fup
		end
	end

	local funcMeta = {
		__index = function(f, k)
			if notInDebugger() then error("attempt to index a function value", 2) end

			local fup = getlist(f)

			if k == "___allupvalues" then
				local t = ret[f]
				local _
				for k,v in next, fup do _, t[k] = getupvalue(f, v) end
				return t
			elseif k == "___allupvaluenames" then
				if retn[f] then
					return retn[f]
				else
					local t = {}
					for k,v in next, fup do t[k] = true end
					retn[f] = t
					return t
				end
			elseif k == "___code" then
				if getinfo then
					local info = getinfo(f, "S")
					local source = gsub((info.source or ""), "^@", "")
					if isFile(source) then
						local i = 0
						local codelines = {}
						for line in lines(source) do
							i = i + 1
							-- linedefined, lastlinedefined, params
							if i >= info.linedefined then
								codelines[#codelines+1] = line
								if i >= info.lastlinedefined then
									break
								end
							end
						end

						return concat(codelines, "\n")
					else
						error("unable to find code file")
					end
				else
					error("Cannot get code... No JIT utils?")
				end
			elseif fup[k] then
				local k, v = getupvalue(f, fup[k])
				return v
			else
				error("attempt to get invalid upvalue", 2)
			end
		end,
		__newindex = function(f, k, v)
			local fup = getlist(f)
			if fup[k] then
				setupvalue(f, fup[k], v)
			else
				error("attempt to set invalid upvalue", 2)
			end
		end,
		--__metatable = false
	}

	if desc and getinfo then
		prettyFunctions = true

		local amount, bytes = 1, 5
		local hardnames = {
			[realPrint] = "print"
		}

		local indexed = {
			[package.loaded] = true,
			[package.preload] = true
		}

		local function addName(item, path)
			if indexed[item] or hardnames[item] then return end
			if type(item) == "table" then
				indexed[item] = true
				for k,v in next, item do
					addName(v, path.."."..k)
				end
			elseif type(item) == "function" then
				hardnames[item] = path
				amount = amount + 1
				bytes = bytes + #path
			end
		end

		for i,v in ipairs {
			"assert", "collectgarbage", "dofile", "error", "gcinfo", "getfenv", "getmetatable", "ipairs", "load", "loadfile", "loadstring",
			"module", "newproxy", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "require", "select",
			"setfenv", "setmetatable", "type", "tonumber", "tostring", "unpack", "xpcall",
			"bit", "coroutine", "debug", "io", "jit", "love", "math", "os", "string", "table", "package"
		} do
			addName(_G[v], v)
		end

		addName(debugger, "debugger")

		local names = setmetatable({}, {
			__index = function(t, f)
				local v

				local info = getinfo(f, "S")
				local source = gsub((info.source or ""), "^@", "")
				local linedefined = info.linedefined
				if isFile(source) and linedefined then
					local i = 0
					local defined
					for line in lines(source) do
						i = i + 1
						-- linedefined, lastlinedefined, params
						if i >= linedefined then
							defined = " "..line.." "
							break
						end
					end
					if defined then
						v = defined:match("%)%-%-%[%[(.-)%]%]")
							or defined:match("[^_a-zA-Z0-9]function%s+([_a-zA-Z][%.%:_a-zA-Z0-9]*)[^_a-zA-Z0-9]")
							or defined:match("[^_a-zA-Z0-9]([_a-zA-Z][%.%:_a-zA-Z0-9]*)%s*=%s*%(*function[^_a-zA-Z0-9]")
						if not v then
							local __tostring = funcMeta.__tostring
							funcMeta.__tostring = nil
							v = tostring(f):match("0x%x+")
							funcMeta.__tostring = __tostring
						end
					end
				end

				local shortSrc = info.short_src
				local location =
					shortSrc == "[C]" and (" [C]") or
					(" ("..shortSrc..":"..tostring(linedefined)..")")

				if v or hardnames[f] then
					v = "function: "..(hardnames[f] or v)..location
					if hardnames[f] then hardnames[f] = nil end
				else
					local __tostring = funcMeta.__tostring
					funcMeta.__tostring = nil
					v = tostring(f)..location
					funcMeta.__tostring = __tostring
				end

				t[f] = v
				return v
			end,
			__mode = "kv"
		})
		function funcMeta:__tostring()
			return names[self]
		end

		printColor(color.blue, "\tAdded "..tostring(amount).." function names for predefined functions, totalling "..tostring(bytes).." characters.")
	else
		prettyFunctions = false
	end

	debug.setmetatable(function()end, funcMeta)
end

function debugger.monitorGlobal(writeTo)
	if type(writeTo) ~= "string" then writeTo = "_G (log).txt" end

	printColor(color.red, "\tNow monitoring the global environment for changes.\nWill be logged to '"..writeTo.."'.")

	local writeToInfo = love.filesystem.getInfo(writeTo)
	if not writeToInfo then
		love.filesystem.write(writeTo, "")
	elseif writeToInfo.type ~= "file" then
		error("Can only write log to files.")
	end

	local file = love.filesystem.newFile(writeTo, "a")

	local traceback = debug.traceback

	setmetatable(_G, {
		__newindex = function(t, k, v)
			if notInDebugger() then
				local msg = "New global defined: "..tostring(k).."="..tostring(v).." (type "..typeReal(v)..")"
				printColor(color.blue, msg)

				local tb = traceback(msg, 2)
				file:write(tb.."\n\n")
				file:flush()
			end
			rawset(t, k, v)
		end,
		__index = function(t, k)
			if notInDebugger() then
				local msg = "Trying to access undefined global: "..tostring(k)
				printColor(color.blue, msg)

				local tb = traceback(msg, 2)
				file:write(tb.."\n\n")
				file:flush()
			end
			return nil
		end
	})
end

function debugger.viewLocals(src, inLine, var, key)
	if src == nil then
		debug.sethook()
		printColor(color.blue, "Disabled local viewer.")
	else
		local getinfo = debug.getinfo
		local getlocal = debug.getlocal
		local sethook = debug.sethook

		local storage, storeKey
		if key == nil then
			storage = _G
			storeKey = var or "_local"
		else
			storage = var
			storeKey = key or "_local"
		end

		if type(src) == "function" then
			src = getinfo(src, "S").source
		elseif type(src) == "string" then
			src = "@"..src
		else
			error("Argument #1 to debugger.viewLocals(src, inLine, var, key) must be a function or string!")
		end
		if type(inLine) ~= "number" then
			printColor(color.red, "You need to pass the line to check in!")
			return
		end

		printColor(color.blue, "Enabled local viewer.\nAny future passes on that line will now write a table!")

		sethook(function(event, line)
			if line == inLine and src == getinfo(2, "S").source then
				local locals = {}
				local i = 1
				local n, v = getlocal(2, i)
				while n or v do
					locals[n] = v
					i = i + 1
					n, v = getlocal(2, i)
				end
				storage[storeKey] = locals
			end
		end, "l")
	end
end

function debugger.getStack(a, b)
	local thread, stack
	if a ~= nil then
		if type(a) == "thread" then
			-- Coroutine
			thread, stack = a, b
		else
			stack = a
		end
	end

	assert(stack == nil or type(stack) == "number", "Argument #1 to debugger.getStack([thread], stack) must be a number or nil.")

	local getinfo, getlocal
	if thread then
		stack = stack or 0

		local _getinfo = debug.getinfo
		local _getlocal = debug.getlocal

		getinfo = function(depth, what)
			return _getinfo(thread, depth, what)
		end

		getlocal = function(depth, index)
			return _getlocal(thread, depth, index)
		end
	else
		stack = (stack or 1) + 1

		getinfo = debug.getinfo
		getlocal = debug.getlocal
	end

	local var = {}

	local function realvalue(value)
		return value == nil and fakeNil or value
	end

	local i=0
	local stackInfo = getinfo(stack, "fn")
	while stackInfo do
		local this = {
			["**Function:"] = stackInfo.func,
			["**Function Name:"] = stackInfo.name
		}
		i = i + 1
		var[i] = this

		local l = 1
		while true do
			local name, value = getlocal(stack, l)
			if not name then break end
			if name:find("^%(") then
				if this[name] == nil then
					this[name] = realvalue(value)
				elseif type(this[name]) ~= "table" then
					this[name] = { this[name] }
				else
					this[name][#this[name]+1] = realvalue(value)
				end
			else
				this[name] = realvalue(value)
			end
			l = l + 1
		end

		stack = stack + 1
		stackInfo = getinfo(stack, "fn")
	end

	return var
end

function debugger.varDisplay(...)
	infoTitleFormat, infoBoxFormat = __infoTitleFormat, __infoBoxFormat
	if ... then
		local varList = ""
		local varFunc = {}
		local args = {...}

		for i=1, #args do
			local v = args[i]

			infoTitleFormat = infoTitleFormat .. " [" .. v[1] .. "]"
			infoBoxFormat = infoBoxFormat .. "\n" .. v[1]
			varList = varList .. "v" .. tostring(i) .. (i < #args and "," or "")
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
		getAdditionalInfo = loadstring(code)(pcall, unpack(varFunc))
		printColor(color.yellow, ":Set custom Var. Display.")
	else
		getAdditionalInfo = function() end
		printColor(color.yellow, ":Reset Var. Display.")
	end
end

function debugger.setProfiler(profileLib, reportPath)
	assert(profile == nil, ":Profiler already set.")
	if type(reportPath) ~= "string" then reportPath = "profiler.txt" end

	local _profile = {
		lib = profileLib,
		frame = 0, interval = 100,
		sort = "time", rows = 20,
		running = false
	}

	if (love.filesystem.getInfo(reportPath) or { type = "file" }).type ~= "file" then
		error("Report Path cannot be a file.")
	end

	local reportFile
	function _profile.addReport()
		reportFile:write(profile.lib.report(profile.sort, profile.rows).."\n")
	end

	function debugger.startProfiler()
		if profile.running then
			return ":Profiler already running."
		else
			profile.frame = 0
			profileLib.start()

			local reportFileInfo = love.filesystem.getInfo(reportPath)
			if not reportFileInfo then
				love.filesystem.write(reportPath, "")
			elseif reportFileInfo.type ~= "file" then
				error("Report file path cannot be a file.")
			end

			reportFile = love.filesystem.newFile(reportPath, "a")

			profile.running = true

			return ":Started the profiler"
		end
	end

	function debugger.stopProfiler()
		if profile.running then
			profileLib.stop()

			profile.running = false

			reportFile:flush()
			reportFile:close()
			reportFile = nil

			return ":Stopped the profiler."
		else
			return ":Profiler wasn't running."
		end
	end

	function debugger.setProfilerInterval(interval)
		assert(type(interval) == "number", ":Argument #1 to debugger.setProfilerInterval(interval) has to be a number.")
		profile.interval = interval

		return ":Set report interval to "..tostring(interval).." frame(s)."
	end

	function debugger.setProfilerReportArgs(sort, rows)
		assert(sort == "time" or sort == "call" or sort == nil, ":Argument #1 to debugger.setProfilerReportArgs(sort, rows) has to be 'time' or 'call'.")
		assert(type(rows) == "number" and rows > 0 or rows == nil, ":Argument #2 to debugger.setProfilerReportArgs(sort, rows) has to be a number.")

		profile.sort = sort or "time"
		profile.rows = rows or 20

		return ":Set report arguments to '"..profile.sort.."' (sort) and "..tostring(profile.rows).." (rows)."
	end

	debugger.newCommand("pstart", "", debugger.startProfiler)
	debugger.newCommand("pstop", "", debugger.stopProfiler)
	debugger.newCommand("pinterval", "n", debugger.setProfilerInterval)
	debugger.newCommand("preport", "sn", debugger.setProfilerReportArgs)
	debugger.newCommand("preport", "s", debugger.setProfilerReportArgs)
	debugger.newCommand("preport", "", debugger.setProfilerReportArgs)

	profileLib.hookall("Lua")

	local function unhook(table)
		for k,v in next, table do
			if type(v) == "function" then
				profileLib.unhook(v)
			end
		end
	end

	-- Unhook debugger functions
	unhook(debugger)
	unhook(debugger.callbacks)
	unhook(fakeKeyboard)
	unhook(fakeMouse)
	unhook(titleManager)
	unhook {
		tostring,
		count,
		sortCont,
		sortedTable,
		promtPrint,
		infoTitle,
		infoBox,
		notInDebugger,
		cloneList,
		checkUtf8,
		getLines,
		printColor,
		rfalse,
		nicerPush,
		getmetatable(debugger).__call
	}

	if indexFunctions and prettyFunctions then
		-- If the profiler given is not compatible, this will crash!
		-- I don't take any responsibility for that.
		local _defined = profileLib.hook._defined

		setmetatable(_defined, {
			__newindex = function(t, k, v)
				if v ~= nil then
					rawset(t, k, (tostring(k):gsub("function: ", "")))
				end
			end
		})
	end

	profile = _profile
end

function debugger.newCommand(name, args, func)
	assert(type(name) == "string", "Argument #1 to debugger.newCommand(name, args, func) must be a string!")
	assert(type(args) == "string", "Argument #2 to debugger.newCommand(name, args, func) must be a string!")
	assert(type(func) == "function" or getmetatable(func) and rawget(getmetatable(func), "__call"), "Argument #3 to debugger.newCommand(name, args, func) must be callable!")

	if commands[name] == nil then
		commands[name] = { name = name, alias = {} }
	elseif commands[name].name ~= name then
		error(":Cannot add alternative syntax to alias '"..tostring(name).."' of command '"..tostring(commands[name].name).."'.")
	end
	local c = {
		args = args,
		func = func
	}
	commands[name][#commands[name]+1] = c
end

function debugger.aliasCommand(name, as)
	assert(type(name) == "string", "Argument #1 to debugger.aliasCommand(name, as) must be a string!")
	assert(type(as)   == "string", "Argument #2 to debugger.aliasCommand(name, as) must be a string!")

	assert(commands[name] ~= nil, ":Command '"..name.."' doesn't exist!")
	assert(commands[as] == nil, ":Command '"..as.."' exists already.")

	commands[as] = commands[name]
	commands[name].alias[#commands[name].alias+1] = as
end

-- Adding some default commands!
debugger.newCommand("index", "" , debugger.allowFunctionIndex)
debugger.newCommand("index", "b", debugger.allowFunctionIndex)

debugger.newCommand("global", "" , debugger.monitorGlobal)
debugger.newCommand("global", "s", debugger.monitorGlobal)

debugger.newCommand("local", "sn", debugger.viewLocals)
debugger.newCommand("local", "", debugger.viewLocals)
-- Screen Clearing
debugger.newCommand("clear", "", debugger.clear)
-- Quick navigation
debugger.newCommand("to", "", function()
	display = "_G"
	yScroll = 1
	return ":Moved to "..display.."."
end)
debugger.newCommand("to", "s", function(s)
	display = gsub(s, "%.([^%[%]\"'%(%)%{%}%.]*)",
	function(t) return "[\""..t.."\"]" end)
	yScroll = 1
	return ":Moved to "..display.."."
end)
debugger.newCommand("loc", "", function() return ":Currently at "..gsub(display, fromPattern, nicerPush) end)

debugger.newCommand("help", "", function()
	local all = {}
	for k,v in next, commands do
		if k == v.name then
			all[#all+1] = "\t"..k
		end
	end
	sort(all)
	insert(all, 1, "All available commands:")
	return concat(all, "\n")
end)
debugger.newCommand("help", "s", function(s)
	local cmd = commands[s]
	if cmd then
		local name = cmd.name
		local all = {}
		local replace = {
			s = "<string>",
			n = "<number>",
			b = "<boolean>"
		}

		for i=1, #cmd do
			local v = cmd[i]
			if v.args == "" then
				all[#all+1] = "\t/"..name
			else
				local x = gsub(v.args, "", " ")
				all[#all+1] = "\t/"..name.." "..gsub(sub(x, 2, #x-1), ".", replace)
			end
		end

		sort(all)
		insert(all, 1, "[[ Help for '"..name.."' ]]\nSyntax:")
		if #cmd.alias > 0 then
			insert(all, "Aliases:")
			for i=1, #cmd.alias do
				insert(all, "\t/"..cmd.alias[i].." ...")
			end
		end

		return concat(all, "\n")
	elseif s == "me" then
		return ":You might need professional help if you ask a debugging tool..."
	else
		return ":Unknown command."
	end
end)

debugger["0 - Don't screw with"] = true -- !!!
debugger["1 - the variables or"] = true -- !!!
debugger["2 - it may break!"]    = true -- !!!

setmetatable(debugger, {
	__call = function(self)
		-- Auto-Injection
		self.registerHandlers()

		local __update = love.update
		local __draw = love.draw

		loadstring([[
			local self, love, __update, __draw, pcall, realPrint = ...

			if __update then
				function love.update(...)
					local s, r = pcall(self.update, ...)
					if not s then
						realPrint(r)
					end

					__update(...)
				end
			else
				function love.update(...)
					local s, r = pcall(self.update, ...)
					if not s then
						realPrint(r)
					end
				end
			end

			if __draw then
				function love.draw(...)
					__draw(...)

					local s, r = pcall(self.draw)
					if not s then
						love.graphics.pop()
						realPrint(r)
					end
				end
			else
				function love.draw(...)
					local s, r = pcall(self.draw)
					if not s then
						love.graphics.pop()
						realPrint(r)
					end
				end
			end
		]], "run_injection")(self, love, __update, __draw, pcall, realPrint)

		return self
	end
})

-- If you want to use the debugger as an error-handler.
-- Will probably fail if the error was a stack overflow.
-- Can also be used as a pseudo-breakpoint by calling in within your code:
-- To continue, try to close the application.
function debugger.errorhandler(message, stack)
	message = message or ""
	stack = stack or 2

	local love = require "love"
	local timer = require "love.timer"
	local event = require "love.event"
	local graphics = require "love.graphics"
	local window = require "love.window"

	-- Get traceback message
	_stackTraceback = debug.traceback(message, stack)
	printColor(color.red, _stackTraceback)

	-- Get locals on stack
	_stackLocals = debugger.getStack(stack)
	if not indexFunctions then
		debugger.allowFunctionIndex(true)
	end

	if not window.isOpen() then
		-- Open a window if there is none
		local w, h = love.window.getDesktopDimensions()
		love.window.setMode(w * (2/3), h * (2/3), { resizable = true })
	end

	debugger.setActive(false) debugger.setActive(true)

	local dt = 0
	timer.step()

	-- Loop. Is exited when the 'quit' event is triggered.
	return function()
		event.pump()
		for name, a,b,c,d,e,f in event.poll() do
			if name == "quit" then
				return true, a
			elseif debugger.callbacks[name] then
				xpcall(debugger.callbacks[name], print, a, b, c, d, e, f)
			end
		end
		dt = timer.step()

		xpcall(debugger.update, print, dt)
		if graphics.isActive() then
			graphics.clear(0.00, 0.35, 0.70)
			if not xpcall(debugger.draw, print) then love.graphics.pop() end
			graphics.present()
		end

		timer.sleep(0.01)
	end
end

-- Alias
debugger.errhand = debugger.errorhandler

return debugger
