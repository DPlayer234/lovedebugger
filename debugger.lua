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
local ffi = require "ffi"

local love = require "love"
local love_keyboard = require "love.keyboard"
local love_mouse = require "love.mouse"
local love_graphics = require "love.graphics"
local love_event = require "love.event"
local love_timer = require "love.timer"

local collectgarbage = collectgarbage
local setmetatable, getmetatable = setmetatable, debug.getmetatable
local rawset, rawget, rawequal = rawset, rawget, rawequal

local string, math = string, math
local table_insert, table_remove, table_concat, table_sort = table.insert, table.remove, table.concat, table.sort
local utf8_len, utf8_codes, utf8_char, utf8_offset = utf8.len, utf8.codes, utf8.char, utf8.offset

-- This is used for any loadstring that is considered to be within the debugger
local DEBUGGER_LOADSTRING = "DEBUGGER"
local ERROR_UTF8 = ":ERROR (utf8):"

-- Fake nil value inserted where nil is needed.
-- Basically, just an explicit nil (fakeNil == nil -> true)
local fakeNil
do
	ffi.cdef "struct nil {};"

	ffi.metatype("struct nil", {
		__eq = function(a, b)
			return rawequal(a, nil) or rawequal(b, nil) or rawequal(a, b)
		end,
		__tostring = function()
			return "nil"
		end
	})

	fakeNil = ffi.new("struct nil")
end

local type = type
local pcall, xpcall = pcall, xpcall
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
	if type(mt) ~= "table" then -- No metatable
		if type(table) ~= "table" then return end -- Not a table
		return table[key] -- Return value
	end
	local index = rawget(mt, "__index")
	if type(index) == "table" then return safeIndex(index, key, depth + 1) end -- Get field from __index
	if type(table) == "table" then return rawget(table, key) end -- Get field from original table
end

-- Used to display alternative type
local typeReal = function(v)
	if rawequal(v, fakeNil) then return "nil *" end
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
	assert(typeReal(nfont) == "userdata:Font", ":Not a font.")

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

-- Checks whether a utf8 string is valid and either returns it, having replaced all
-- null bytes with spaces or the error message
local function validateUtf8(s)
	return utf8_len(s) and s:gsub("%z", " ") or ERROR_UTF8
end

-- Makes sure to correctly format something for display
local function toDisplayString(value)
	return type(value) == "string" and string.format("%q", value):gsub("\\?\n", "\\n") or tostring(value)
end

-- Makes sure there's no line breaks in a string and by replacing them with spaces
local function toSingleLine(value)
	return (tostring(value):gsub("\n", " "))
end

-- Print something to the local console
local lastPrint, printedTimes
local function proxyPrint(c, ...)
	local args = {...}
	local top = 0
	for i,v in next, args do
		args[i] = validateUtf8(tostring(v))
		if debugger.replaceTabs then
			args[i] = args[i]:gsub("\t", debugger.replaceTabs)
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

	local t = table_concat(args, debugger.replaceTabs or "\t")

	if t ~= lastPrint then
		local time = love_timer.getTime()
		for s in t:gmatch("[^\n]*\n") do
			table_insert(lg, c)
			table_insert(lg, s)

			table_insert(lgtemp, c)
			table_insert(lgtemp, s)

			table_insert(lgtime, time)
		end

		while #lg > 2 and #lg*0.5 > love_graphics.getHeight()/fheight - 1 do
			table_remove(lg, 1)
			table_remove(lg, 1)
		end

		while #lgtemp > 2 and #lgtemp*0.5 > love_graphics.getHeight()/fheight - 1 do
			table_remove(lgtemp, 1)
			table_remove(lgtemp, 1)
		end

		lastPrint = t
		printedTimes = 1
	else
		printedTimes = printedTimes + 1
		if printedTimes == 2 then
			lg[#lg] = "(2x) "..lg[#lg]
		else
			lg[#lg] = lg[#lg]:gsub("^%(%d+x%)", "("..tostring(printedTimes).."x)")
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

-- Prints stuff everywhere
function debugger.allPrint(...)
	realPrint(...)
	return proxyPrint(color.white, ...)
end

print = debugger.allPrint

-- Prints in color everywhere
local function printColor(c, text)
	realPrint(text)
	return proxyPrint(c, text)
end

-- Clearing print calls
function debugger.clear()
	for k,v in next, lg do lg[k] = nil end
	debugger.tempClear()
end

-- Clears the temporary display only
function debugger.tempClear()
	for k,v in next, lgtemp do lgtemp[k] = nil end
	for k,v in next, lgtime do lgtime[k] = nil end
end

-- This function will affect the order of the environment display.
-- You may rewrite this: It should get a table and return an array with the KEYS of the origCallback table as its VALUES.
-- E.g. sortedTable({ x = 5, y = 2, a = "test" }) -> { "a", "x", "y" }
local function sortCont(a, b) if type(a) == type(b) then return a < b else return tostring(a) < tostring(b) end end
local function pSortCont(a, b) local s, r = pcall(sortCont, a, b) return s and r end

local function sortedTable(t)
	local to = {}
	for k,v in next, t do
		to[#to+1] = k
	end
	pcall(table_sort, to, sortCont) -- <= Real Sorting
	return to
end

local display = "_G"
local yScroll = 1
local textPosition = 1
local inputs = {}

local active = false
local textinput = ""
local texttable = {}
local lastselect = 0
local lastinput = {}
local commands = {}

local indexFunctions, prettyFunctions = false, false

-- Gets the currently navigated to value
local function getDv(display)
	local s, dv = pcall(loadstring("local getmetatable=... return "..display, DEBUGGER_LOADSTRING), getmetatable)
	if s then
		return dv
	else
		return nil
	end
end

-- Gets the currently navigated to value and the index if valid
local function getDvIndex(display)
	local dv = getDv(display)
	if type(dv) == "table" then
		return dv, sortedTable(dv)
	end
	if indexFunctions and type(dv) == "function" then
		return dv, sortedTable(dv.___allupvaluenames)
	end
	return dv
end

-- Storing origCallback callbacks/overriding them to be used
local realKeyboard, realMouse, fakeKeyboard, fakeMouse

debugger.callbacks = {
	keypressed = function(key, scancode, isrepeat)
		inputs[key] = true
		if key == "backspace" then
			if texttable[textPosition-1] then
				table_remove(texttable, textPosition-1)
				textPosition = textPosition - 1
			end
			while realKeyboard.isDown("lctrl", "rctrl") and texttable[textPosition-1] and texttable[textPosition-1]:find("%a") do
				table_remove(texttable, textPosition-1)
				textPosition = textPosition - 1
			end
		elseif key == "delete" then
			if texttable[textPosition] then
				table_remove(texttable, textPosition)
			end
			while realKeyboard.isDown("lctrl", "rctrl") and texttable[textPosition] and texttable[textPosition]:find("%a") do
				table_remove(texttable, textPosition)
			end
		end
	end,
	textinput = function(text)
		if text == "\n" or text == "\r" then text = " " end
		if font:hasGlyphs(text) then
			table_insert(texttable, textPosition, text)
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

local updateEvents = {}
local updateTime = 0
local monitorTable

-- Update Function
local fromPattern = "%[\"[_a-zA-Z][_a-zA-Z0-9]-\"%]"
local nicerPush = function(t) return "." .. t:sub(3, #t-2) end
function debugger.update(dt)
	assert(type(dt) == "number", "Argument #1 to debugger.update(dt) must be a number!")

	-- Removing text from the temporary output
	if #lgtime > 0 then
		local ctime = love_timer.getTime()
		if lgtime[1] + debugger.textfade < ctime then
			table_remove(lgtemp, 1)
			table_remove(lgtemp, 1)
			table_remove(lgtime, 1)
		end
	end

	if active then
		monitorTable:update()

		-- Clearing the prompt
		if inputs[debugger.clearPrompt] then
			texttable = {}
			textPosition = 1
		end

		-- Getting previous inputs
		if inputs.up then
			if lastselect < #lastinput then
				if lastselect == 0 and #texttable > 0 then
					table_insert(lastinput, 1, texttable)
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

		-- Clipboard
		if (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("v")) or (realKeyboard.isDown("lctrl", "rctrl") and inputs.v) or inputs.insert) and love.system then
			local cbt = love.system.getClipboardText()
			if type(cbt) == "string" then
				for p,c in utf8_codes(cbt) do
					debugger.callbacks.textinput(utf8_char(c))
				end
			end
		elseif (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("c")) or (realKeyboard.isDown("lctrl", "rctrl") and inputs.c)) and love.system then
			love.system.setClipboardText(table_concat(texttable, ""))
		end

		-- Handling console execution.
		if inputs["return"] and #texttable > 0 then
			textinput = table_concat(texttable, "")

			-- Storing current input to be reused
			table_insert(lastinput, 1, texttable)
			lastselect = 0
			if #lastinput > debugger.maxStorage then
				table_remove(lastinput, #lastinput)
			end

			texttable = {}
			textPosition = 1
			if textinput:find("^[/\\!:%.%*]") then
				-- A command. Has to be.
				local args = {}
				local inString, string = false, nil
				for match in textinput:gmatch("%S+") do
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

				local one = table_remove(args, 1)
				local command = commands[one:sub(2, #one)]
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
						elseif v.args:find(pattern) then
							this = v
							break
						end
					end

					if this then
						local i = 0
						for c in this.args:gmatch(".") do
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
			else
				-- Attempting return to print that on the screen
				printColor(color.yellow, ">> " .. textinput)

				local r = { loadstring("local getmetatable=...;return "..textinput, DEBUGGER_LOADSTRING) }
				if not r[1] then
					r = { loadstring("local getmetatable=...;"..textinput, DEBUGGER_LOADSTRING) }
				end
				if r[1] then
					r = { pcall(r[1], getmetatable) }
				end
				if r[1] == true then
					local max = 0
					for i,v in next, r do if i > max then max = i end end
					if max > 1 then
						r[1] = ":Return values"
						for i=2, max do
							local v = r[i]
							r[i] = "[" .. tostring(i-1) .. "] (" .. validateUtf8(typeReal(v)) .. ") " .. validateUtf8(toSingleLine(toDisplayString(v)))
						end
						if #r > 0 then
							printColor(color.yellow, table_concat(r, "\n\t"))
						end
					end
				else
					printColor(color.red, ":ERROR:" .. tostring(r[2]))
				end
			end
		end

		-- Other crap with the environment (mostly navigation)
		local dv, index = getDvIndex(display)

		if (inputs.m1 or inputs.m2) then
			if love_mouse.getX() >= math.ceil(love_graphics.getWidth()*debugger.printArea) then
				local nid = math.floor(love_mouse.getY()/fheight-2)
				local shift = realKeyboard.isDown("lshift", "rshift")

				if nid >= 0 then
					-- Clicked on a variable
					if index and index[nid+yScroll] then
						local ntext = index[nid+yScroll]

						-- Getting variable name:
						local ndisplay = ""
						local ntype = type(ntext)
						if ntype ~= "string" and ntype ~= "number" then ntext = tostring(ntext) end
						if display == "_G" then
							ndisplay = ntext
						else
							ndisplay = display .. "[" .. toSingleLine(toDisplayString(ntext)) .. "]"
						end

						local dv = getDv(ndisplay)
						if type(dv) == "table" and inputs.m1 then
							-- LMB
							-- Navigating to another table
							display = ndisplay
							yScroll = 1
						elseif shift then
							-- Holding Shift
							if inputs.m2 then
								-- RMB
								-- Navigating to its metatable
								local m = getmetatable(dv)

								if type(m) == "table" then
									display = "getmetatable("..ndisplay..")"
									yScroll = 1
								end
							elseif indexFunctions and type(dv) == "function" then
								-- LMB
								-- Navigating to a function's upvalues
								display = ndisplay
								yScroll = 1
							end
						else
							-- Copying the variable name to the prompt
							for p,c in utf8_codes(ndisplay:gsub(fromPattern, nicerPush)) do
								debugger.callbacks.textinput(utf8_char(c))
							end
						end
					else
						-- Copying the variable name to the prompt
						for p,c in utf8_codes(display:gsub(fromPattern, nicerPush)) do
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
							yScroll = 1
						end
					else
						repeat
							-- Navigating to its parent
							local s = display

							if s:find("^getmetatable%(.*%)$") then
								display = s:sub(14, #s-1)
							elseif s:find("%(%)$") then
								display = s:sub(1, #s-2)
							else
								local e, _e = s:find("%[")
								if e then s = s:sub(e+1, #s) end
								local r = 0
								while e do
									r = r + e
									e, _e = s:find("%[")
									if e then s = s:sub(e+1, #s) end
								end

								if r > 0 then
									display = display:sub(1, r-1)
								else
									display = "_G"
								end
							end
						until display == "_G" or select(2, getDvIndex(display))

						yScroll = 1
					end
				end
			end
		end

		-- Scrolling the environment
		if inputs.mpos and index then
			yScroll = yScroll + 4
			if yScroll > #index then
				yScroll = #index
			end
		elseif inputs.mneg and index then
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
	table_sort(updateEvents, function(a, b)
		return a.prio > b.prio
	end)

	for i=1, #updateEvents do
		if updateEvents[i] == this then
			return i
		end
	end
end

-- Draw Function(s)

local function countString(str, patt)
	local _, c = str:gsub(patt, "")
	return c
end

-- Printing the Lua prompt
local function promptPrint(w, h, fheight)
	local prompt = table_concat(texttable)
	local width = font:getWidth(prompt)
	local x = width < w and 0 or w-width
	love_graphics.print(prompt, x, h-fheight)
	if love_timer.getTime()%0.5 >= 0.25 then
		if textPosition > #texttable then
			love_graphics.rectangle("fill", font:getWidth(prompt), h-fheight, font:getWidth(" "), fheight)
		else
			love_graphics.rectangle("fill",
				font:getWidth(table_concat(texttable, "", 1, textPosition-1))+x,
				h-fheight,
				font:getWidth(table_concat(texttable, "", textPosition, textPosition))-1, fheight)
		end
	end
end

local getAdditionalInfo = function() end

local infoTitleFormat = "%s [%d FPS] [%.1f KB] [%.6f s.]"
local function infoTitle(title, fps, ram, time)
	local s, r = pcall(string.format, infoTitleFormat, title, fps, ram, time, getAdditionalInfo())
	return r
end

local infoBoxFormat = "%d FPS\n~%.1f KB\n%.6f s."
local function infoBox(fps, ram, time)
	local s, r = pcall(string.format, infoBoxFormat, fps, ram, time, getAdditionalInfo())
	return r
end

local __infoTitleFormat, __infoBoxFormat = infoTitleFormat, infoBoxFormat
-- Drawing everything
function debugger.draw()
	-- Storing the current graphics state and resetting it
	love_graphics.push("all")
	love_graphics.origin()
	love_graphics.setFont(font)
	love_graphics.setScissor()
	love_graphics.setShader()
	love_graphics.setBlendMode("alpha")
	love_graphics.setColorMask(true, true, true, true)
	love_graphics.setWireframe(false)

	local ram = collectgarbage("count")
	fheight = math.abs(font:getHeight()*font:getLineHeight())
	local w, h = love_graphics.getDimensions()

	if active then
		-- Prompt and Environment is opened
		local tt = math.ceil(w*debugger.printArea)

		local _, wrap = font:getWrap(lg, tt)
		local hlg = #wrap*fheight

		local dv, index = getDvIndex(display)
		local vartype = typeReal(dv):gsub(" ", " ")
		if indexFunctions and vartype == "function" then
			dv = dv.___allupvalues
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
			printData[indexData] = arg:sub(1, 150)
			indexData = indexData + 1
		end

		local maxLines = math.ceil(h/fheight)

		if index then
			-- Indexable
			for i=1, #index do
				if i >= yScroll and i <= maxLines + yScroll - 4 then
					local k = index[i]
					local v = dv[k]

					addType(validateUtf8(typeReal(v)))
					addName(validateUtf8(toSingleLine(k)))
					addData(validateUtf8(toSingleLine(toDisplayString(v))))
				elseif i > maxLines + yScroll - 4 then
					break
				end
			end

			addType("\t>>>\n")
			addName("")
		else
			addType(tostring(dv):gsub(" ", " ").."\n\t>>>\n")
		end

		-- Variable Path
		local path = (display == "_G" and "..." or "> "..display):gsub("getmetatable%(", "Meta("):gsub("%[\"", " > "):gsub("\"%]", ""):gsub(" ", " ")
		if font:getWidth("\t"..path) > w-tt then
			while font:getWidth("\t…"..path) > w-tt do
				local byteoffset = utf8_offset(path, 2)
				if byteoffset then
					path = path:sub(byteoffset, #path)
				else
					break
				end
			end
			path = "…"..path
		end

		local stringType = table_concat(printType, " \n")
		local stringName = table_concat(printName, " \n")
		local stringData = table_concat(printData, "\n")

		local header = string.format("\t%s\n\tType: %s %03dy\t", path, vartype, yScroll)
		if not debugger.useTitleBar then
			header = header .. " ~"..math.floor(ram+0.5).." KB "..love_timer.getFPS().." FPS"
		end
		local hprinted = countString(stringType, "\n")*fheight

		-- Printed text and Prompt
		love_graphics.setColor(color.bgActive)
		love_graphics.rectangle("fill", 0, 0, tt-1, hlg)
		love_graphics.rectangle("fill", 0, math.ceil(h-fheight), w, fheight)

		love_graphics.setColor(color.fgActive)
		if debugger.printArea > 0 then
			love_graphics.setScissor(0, 0, tt-1, hlg)
			love_graphics.printf(lg, 0, 0, tt, "left")
			love_graphics.setScissor()
		end

		pcall(promptPrint, w, h, fheight)

		-- Environment Display
		if debugger.printArea < 1 then
			local wt = w - tt
			local wh = math.ceil(h-fheight-1)
			local tw = math.ceil(wt * 0.25)
			local nw = math.ceil(wt * 0.25)

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
		local tt = math.ceil(w*debugger.printArea)-1

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
end

function debugger.isActive()
	return active
end

-- Returns whether the scope is outside of the debugger
local notInDebugger
do
	local getinfo = debug.getinfo

	local sources = {
		[DEBUGGER_LOADSTRING] = true
	}

	function notInDebugger()
		return not sources[debug.getinfo(3, "S").source]
	end

	function debugger.addSource(func)
		sources[debug.getinfo(func or 2, "S").source] = true
	end

	debugger.addSource()
end

-- The monitor table can be expanded to access variables
-- Simply add a string containing the path to access.
do
	local updateList = {}

	local errorMeta = {
		__index = {
			type = "error"
		},
		__tostring = function(self)
			return "error: " .. self.errormsg
		end
	}

	monitorTable = setmetatable({}, {
		__index = {
			update = function(t)
				for k, v in pairs(updateList) do
					local ok, value = pcall(v)
					if ok then
						if rawequal(value, nil) then
							rawset(t, k, fakeNil)
						else
							rawset(t, k, value)
						end
					else
						rawset(t, k, setmetatable({ errormsg = value }, errorMeta))
					end
				end
			end,
			type = "monitor"
		},
		__newindex = function(t, k, v)
			if type(v) == "function" then
				updateList[k] = v
			elseif type(v) == "string" then
				local func = assert(loadstring("return (" .. v .. ")", DEBUGGER_LOADSTRING))

				updateList[k] = func
			else
				error("Can only add functions and strings to update list.")
			end
		end,
		__tostring = function(self)
			return "table: <monitor>"
		end
	})

	debugger.monitorTable = monitorTable
end

function debugger.getMonitorTable()
	return monitorTable
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
					local source = (info.source or ""):gsub("^@", "")
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

						return table_concat(codelines, "\n")
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
			"coroutine", "debug", "io", "math", "os", "string", "table", "package"
		} do
			addName(_G[v], v)
		end

		for i,v in ipairs {
			"bit", "jit", "love"
		} do
			local s, r = pcall(require, v)
			if s then
				addName(r, v)
			end
		end

		do
			local ffi = require "ffi"

			addName(ffi, "ffi")
			addName(getmetatable(ffi.new("int")), "<cdata>")
		end

		addName(debugger, "debugger")

		local names = setmetatable({}, {
			__index = function(t, f)
				local v

				local info = getinfo(f, "S")
				local source = (info.source or ""):gsub("^@", "")
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
		return rawequal(value, nil) and fakeNil or value
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
				if rawequal(this[name], nil) then
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
		getAdditionalInfo = loadstring(code, DEBUGGER_LOADSTRING)(pcall, unpack(varFunc))
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
		countString,
		sortCont,
		pSortCont,
		sortedTable,
		getDv,
		getDvIndex,
		promptPrint,
		infoTitle,
		infoBox,
		notInDebugger,
		cloneList,
		validateUtf8,
		toSingleLine,
		toDisplayString,
		printColor,
		rfalse,
		nicerPush,
		_tostring,
		safeIndex,
		typeReal,
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
	display = s:gsub("%.([^%[%]\"'%(%)%{%}%.]*)", function(t) return string.format("[%q]", t) end)
	yScroll = 1
	return ":Moved to " .. display .. "."
end)
debugger.newCommand("loc", "", function() return ":Currently at " .. display:gsub(fromPattern, nicerPush) end)

debugger.newCommand("help", "", function()
	local all = {}
	for k,v in next, commands do
		if k == v.name then
			all[#all+1] = "\t"..k
		end
	end
	table_sort(all)
	table_insert(all, 1, "All available commands:")
	return table_concat(all, "\n")
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
				local x = v.args:gsub("", " ")
				all[#all+1] = "\t/" .. name .. " " .. x:sub(2, #x-1):gsub(".", replace)
			end
		end

		table_sort(all)
		table_insert(all, 1, "[[ Help for '"..name.."' ]]\nSyntax:")
		if #cmd.alias > 0 then
			table_insert(all, "Aliases:")
			for i=1, #cmd.alias do
				table_insert(all, "\t/"..cmd.alias[i].." ...")
			end
		end

		return table_concat(all, "\n")
	elseif s == "me" then
		return ":You might need professional help if you ask a debugging tool..."
	else
		return ":Unknown command."
	end
end)

debugger["0 - Don't screw with"] = true -- !!!
debugger["1 - the variables or"] = true -- !!!
debugger["2 - it may break!"]    = true -- !!!

do
	-- Safe updating functions that won't cause an error
	function debugger.safeUpdate(dt)
		return xpcall(debugger.update, realPrint, dt)
	end

	local function popNPrint(errormsg)
		love.graphics.pop()
		realPrint(errormsg)
	end

	function debugger.safeDraw()
		return xpcall(debugger.draw, popNPrint)
	end
end

setmetatable(debugger, {
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

	graphics.reset()
	debugger.setActive(false) debugger.setActive(true)

	local dt = 0
	timer.step()

	-- Loop. Is exited when the 'quit' event is triggered.
	return function()
		event.pump()
		for name, a,b,c,d,e,f in event.poll() do
			if name == "quit" then
				return a or 0
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
