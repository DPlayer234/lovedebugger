--[[
Copyright © 2017 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]

local debugger = {}

debugger.activate    = "f4" -- Löve KeyConstant of the key used to open the console. (Default: 'f4')
debugger.clearPrompt = "f5" -- Löve KeyConstant of the key used to clear the Lua prompt and toggle 'debugger.doTempPrint'. (Default: 'f5')
debugger.textfade    = 7    -- Time it takes for text to fade away after its 'print' call in seconds.
debugger.printArea   = 2/3  -- Screen Area where the prints are displayed (ratio 0.0-1.0). (Default: 2/3)
debugger.doTempPrint = true -- Whether or not to print to the screen if the console is closed.
debugger.maxStorage  = 100  -- How many console inputs are stored to be reused (by using 'Up' and 'Down' arrow keys). (Default: 100)
debugger.useTitleBar = true -- Whether or not to print FPS, Lua Ram Usage and update time to the window title bar. (Default: true)
debugger.replaceTabs ="    "-- Replace tab character in prints with the specified string.

debugger.color = {          -- Various colors used
	-- Active:
	bgActive = {  0,  0,  0,127},
	fgActive = {255,255,255,255},
	fgActive2= {200,200,255,255},
	-- Not Active:
	bgNotActive = {  0,  0,  0, 85},
	fgNotActive = {255,255,255,170},
	-- Other:
	white = {255,255,255},
	black = {  0,  0,  0},
	red   = {255, 85, 85},
	blue  = { 85, 85,255},
	green = { 85,255, 85},
	yellow= {255,205, 40},
}

-- Call debugger.setFont(Font:Löve-Font-Object) to set the font used by the debugger; default is the font set during initialization.
-- debugger.print(...) will print text to the debugger's console exclusively.
-- Controller/Joystick inputs won't be disabled, so feel free to use a controller while testing/debugging.
local require = require

local debug = require("debug")
local utf8 = require("utf8")
local love = require("love")
if not love.keyboard then require("love.keyboard") end
if not love.mouse then require("love.mouse") end
if not love.graphics then require("love.graphics") end
if not love.event then require("love.event") end

local collectgarbage = collectgarbage
local setmetatable, getmetatable = setmetatable, debug.getmetatable
local rawset, rawget = rawset, rawget

local table, string, math = table, string, math
local insert, remove, concat, sort = table.insert, table.remove, table.concat, table.sort
local floor, ceil, abs = math.floor, math.ceil, math.abs
local sub, gsub, gmatch, format, find = string.sub, string.gsub, string.gmatch, string.format, string.find
local utf8_len, utf8_codes, utf8_char, utf8_offset = utf8.len, utf8.codes, utf8.char, utf8.offset

local type = type
local pcall = pcall
local loadstring = loadstring or load
local pairs, ipairs = pairs, ipairs
local _tostring, tonumber = tostring, tonumber
local tostring = function(t)
	local s, r = pcall(_tostring, t)
	return s and r or ":ERROR:"
end
local error = error

-- Dependencies, yes, I require those. *BADUM-TSS*
local dep = {getFPS=nil, getTime=nil}
if love.timer then
	dep.getFPS = love.timer.getFPS
	dep.getTime = love.timer.getTime
else
	local time = 0
	dep.getFPS = --[[]]function() return 0/0 end
	dep.getTime = --[[]]function() time = time + 1/60 return time end
end
if love.window then
	dep.getTitle = love.window.getTitle
	dep.setTitle = love.window.setTitle
	dep.titleUpdated = false

	local title = dep.getTitle()
	local updated = false
	dep.getRegularTitle = --[[]]function() return title end
	love.window.getTitle = dep.getRegularTitle
	love.window.setTitle = --[[]]function(new)
		local oftype = type(new)
		if type(new) == "string" then
			title = new
		elseif type(new) == "number" then
			title = tostring(new)
		else
			error("Bad argument #1 to '?' (string expected, got "..type(new)..")", 2)
		end
		dep.titleUpdated = true
	end
else
	dep.getTitle = --[[]]function()return""end
	dep.setTitle = --[[]]function()end
	dep.titleUpdated = false
end

local function cloneList(t)
	local n = {}
	for i,v in ipairs(t) do
		n[i] = v
	end
	return n
end

-- Setting the font
local font, fheight
function debugger.setFont(nfont)
	if nfont.type and nfont:type() == "Font" then
		font = nfont
		fheight = font:getHeight()*font:getLineHeight()
	else
		error(":Not a font.")
	end
end
function debugger.getFont()
	return font
end

do
	debugger.setFont(love.graphics.getFont())
	local s, lFont = pcall(require, "debugger_font")
	if s then debugger.setFont(lFont) end
end

-- Print Calls / Wrapping the 'regular' print
local realPrint = print

local lg = {}
local lgtemp = {}
local lgtime = {}
local color = debugger.color

local function checkUtf8(s) return utf8_len(s) and true end
local function getLines(sf)
	local nl = 0
	for i,v in ipairs(sf) do
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
	for i,v in pairs(args) do
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
		local time = dep.getTime()
		for s in gmatch(t, "[^\n]*\n") do
			insert(lg, c)
			insert(lg, s)

			insert(lgtemp, c)
			insert(lgtemp, s)

			insert(lgtime, time)
		end

		while #lg > 2 and #lg*0.5 > love.graphics.getHeight()/fheight - 1 do
			remove(lg, 1)
			remove(lg, 1)
		end

		while #lgtemp > 2 and #lgtemp*0.5 > love.graphics.getHeight()/fheight - 1 do
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
			lgtime[#lgtime] = dep.getTime()
		else
			lgtemp[1] = lg[#lg-1]
			lgtemp[2] = lg[#lg]
			lgtime[1] = dep.getTime()
		end
	end
end

debugger.print = proxyPrint
debugger.realPrint = realPrint

function print(...)
	realPrint(...)
	proxyPrint(color.white, ...)
end

local function printColor(c, ...)
	realPrint(...)
	proxyPrint(c, ...)
end

-- Clearing print calls
function debugger.clear()
	for k,v in pairs(lg) do lg[k] = nil end
	debugger.tempClear()
end

function debugger.tempClear()
	for k,v in pairs(lgtemp) do lgtemp[k] = nil end
	for k,v in pairs(lgtime) do lgtime[k] = nil end
end

-- This function will affect the order of the environment display.
-- You may rewrite this: It should get a table and return an array with the KEYS of the original table as its VALUES.
-- E.g. sortedTable({ x = 5, y = 2, a = "test" }) -> { "a", "x", "y" }
local function sortCont(a, b) if type(a) == type(b) then return a<b else return tostring(a)<tostring(b) end end
local function sortedTable(t, to)
	local tx
	if to then
		for k,v in pairs(to) do to[k] = nil end
		tx = to
	else
		tx = {}
	end

	for k,v in pairs(t) do
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

-- Storing original callbacks/overriding them to be used
local realKeyboard, realMouse, fakeKeyboard, fakeMouse

local override, original = {}, {}
local realKeypressed
local initOver, callbacks
function debugger.setOverrides(cb)
	if initOver then
		-- Removing old callbacks
		callbacks.keypressed = realKeypressed

		for k,v in pairs(original) do
			callbacks[k] = v ~= "" and v or nil
		end
	else
		initOver = true
	end
	callbacks = cb

	-- Overrides/Preventing game inputs while the console is opened.
	local keypressed = function(key, scancode, isrepeat)
		inputs[key] = true
		if active then
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
		end
	end

	if cb.keypressed then
		realKeypressed = cb.keypressed
		cb.keypressed = function(...)
			keypressed(...)
			if not active then
				realKeypressed(...)
			end
		end
	else
		realKeypressed = nil
		cb.keypressed = keypressed
	end

	override = {
		textinput = function(text)
			if text == "\n" or text == "\r" then text = " " end
			if font:hasGlyphs(text) then
				insert(texttable, textPosition, text)
				textPosition = textPosition + 1
			end
		end,

		keyreleased = function() end,

		mousepressed = function(x, y, button, istouch)
			inputs["m"..tostring(button)] = true
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

	original = {}
	for k,v in pairs(override) do
		original[k] = cb[k] or ""
	end
end

-- Making sure inputs are not sent to the game while the console is in use.
realKeyboard = {
	isDown = love.keyboard.isDown,
	isScancodeDown = love.keyboard.isScancodeDown,
	setKeyRepeat = love.keyboard.setKeyRepeat,
	hasKeyRepeat = love.keyboard.hasKeyRepeat,
	setTextInput = love.keyboard.setTextInput,
	hasTextInput = love.keyboard.hasTextInput
}
realMouse = {
	isDown = love.mouse.isDown,
	setVisible = love.mouse.setVisible,
	isVisible = love.mouse.isVisible,
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
	if status ~= active then
		active = not active
		if active then
			-- Enabling
			mousevisible = love.mouse.isVisible()
			love.mouse.setVisible(true)
			keyrepeat = love.keyboard.hasKeyRepeat()
			love.keyboard.setKeyRepeat(true)
			hastextinput = love.keyboard.hasTextInput()
			love.keyboard.setTextInput(true)

			if inputs[debugger.activate] and callbacks.keyreleased then
				callbacks.keyreleased(debugger.activate,love.keyboard.getScancodeFromKey(debugger.activate))
			end

			for k,v in pairs(override) do
				callbacks[k] = v
			end
			for k,v in pairs(fakeKeyboard) do
				love.keyboard[k] = v
			end
			for k,v in pairs(fakeMouse) do
				love.mouse[k] = v
			end
		else
			-- Disabling
			for k,v in pairs(original) do
				if v == "" then
					callbacks[k] = nil
				else
					callbacks[k] = v
				end
			end
			for k,v in pairs(realKeyboard) do
				love.keyboard[k] = v
			end
			for k,v in pairs(realMouse) do
				love.mouse[k] = v
			end

			love.mouse.setVisible(mousevisible)
			love.keyboard.setKeyRepeat(keyrepeat)
			love.keyboard.setTextInput(hastextinput)
		end
	end
end

local indexFunctions = false
local updateEvents = {}

local updateTime = 0
-- Update Function
local fromPattern = "%[\"[_a-zA-Z][_a-zA-Z0-9]-\"%]"
local nicerPush = function(t) return "."..sub(t, 3, #t-2) end
function debugger.update(dt)
	if inputs[debugger.activate] then
		debugger.setActive()
	end

	if #lgtime > 0 then
		local ctime = dep.getTime()
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
					override.textinput(utf8_char(c))
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
							pattern = pattern.."[ns]"
						elseif v == "true" or v == "false" then
							pattern = pattern.."[bs]"
						else
							pattern = pattern.."s"
						end
					end
					pattern = pattern.."$"

					local this
					for i,v in ipairs(command) do
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
								if args[i] == "true" then
									args[i] = true
								elseif args[i] == "false" then
									args[i] = false
								end
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
						--for i,v in ipairs(r) do r[i] = type(v)..":"..tostring(v) end
						local max = 0
						for i,v in pairs(r) do if i > max then max = i end end
						for i=2, max do r[i-1] = r[i] r[i] = nil end
						for i=1, max-1 do
							local v = r[i]
							if v == nil then
								r[i] = tostring(i)..":nil"
							else
								r[i] = tostring(i)..":"..type(v)..":"..tostring(v)
							end
						end
						if #r > 0 then
							printColor(color.yellow, ":"..concat(r, "\t:"))
						end
					end
				else
					printColor(color.red, ":ERROR:"..tostring(r[2]))
				end
			end
		end

		-- Scrolling the environment
		if inputs.mpos then
			yScroll = yScroll + 4
		elseif inputs.mneg then
			if yScroll > 1 then
				yScroll = yScroll - 4
			end
		end

		-- Scrolling the cursor through the text
		if inputs.right and textPosition <= #texttable then
			textPosition = textPosition + 1
		elseif inputs.left and textPosition > 1 then
			textPosition = textPosition - 1
		end

		-- Other crap with the environment (mostly navigation)
		local s, dv = pcall(loadstring("local getmetatable=... return "..display), getmetatable)

		if type(dv) == "table" then
			index = sortedTable(dv, index)
		elseif indexFunctions and type(dv) == "function" then
			index = sortedTable(dv.___allupvalues, index)
		end
		if not s then dv = nil end

		if (inputs.m1 or inputs.m2) then
			if love.mouse.getX() >= ceil(love.graphics.getWidth()*debugger.printArea) then
				local nid = floor(love.mouse.getY()/fheight-2)
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
								override.textinput(utf8_char(c))
							end
						end
					else
						-- Copying the variable name to the prompt
						for p,c in utf8_codes(gsub(display, fromPattern, nicerPush)) do
							override.textinput(utf8_char(c))
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
	else
		if inputs[debugger.clearPrompt] then
			debugger.doTempPrint = not debugger.doTempPrint
		end
	end

	for k,v in pairs(inputs) do
		inputs[k] = nil
	end

	for i=1, #updateEvents do
		local s, r = pcall(updateEvents[i].func, dt)
		if not s then
			printColor(color.red, ":ERROR:"..tostring(r))
		end
	end

	updateTime = dep.getTime()
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
local lgraphics = love.graphics
-- If there only was something like an import statement...
local graphics_print, graphics_printf, graphics_rectangle, graphics_push, graphics_origin, graphics_setFont, graphics_getFont, graphics_setScissor, graphics_getScissor, graphics_setShader, graphics_getShader, graphics_setBlendMode, graphics_getBlendMode, graphics_setColorMask, graphics_getColorMask, graphics_setWireframe, graphics_isWireframe, graphics_setColor, graphics_getColor, graphics_getDimensions, graphics_pop = lgraphics.print, lgraphics.printf, lgraphics.rectangle, lgraphics.push, lgraphics.origin, lgraphics.setFont, lgraphics.getFont, lgraphics.setScissor, lgraphics.getScissor, lgraphics.setShader, lgraphics.getShader, lgraphics.setBlendMode, lgraphics.getBlendMode, lgraphics.setColorMask, lgraphics.getColorMask, lgraphics.setWireframe, lgraphics.isWireframe, lgraphics.setColor, lgraphics.getColor, lgraphics.getDimensions, lgraphics.pop

local reppatt = "[\r\n\t\v\\%z\"]"
local rep = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\\"] = "\\\\", ["\0"] = "\\0", ["\""] = "\\\"" }
-- Printing the Lua prompt
local function promtPrint(w, h, fheight)
	local prompt = concat(texttable)
	local width = font:getWidth(prompt)
	local x = width < w and 0 or w-width
	graphics_print(prompt, x, h-fheight)
	if dep.getTime()%0.5 >= 0.25 then
		if textPosition > #texttable then
			graphics_rectangle("fill", font:getWidth(prompt), h-fheight, font:getWidth(" "), fheight)
		else
			graphics_rectangle("fill", font:getWidth(concat(texttable, "", 1, textPosition-1))+x, h-fheight, font:getWidth(concat(texttable, "", textPosition, textPosition))-1, fheight)
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
	graphics_push()
	graphics_origin()

	local ram = collectgarbage("count")

	fheight = abs(font:getHeight()*font:getLineHeight())

	local oldfont = graphics_getFont()
	graphics_setFont(font)

	local xs, ys, ws, hs = graphics_getScissor()
	graphics_setScissor()

	local oldshader = graphics_getShader()
	graphics_setShader()

	local blendmode, alphablendmode = graphics_getBlendMode()
	graphics_setBlendMode("alpha")

	local rm, gm, bm, am = graphics_getColorMask()
	graphics_setColorMask(true, true, true, true)

	local wireframe = graphics_isWireframe()
	graphics_setWireframe(false)

	local r, g, b, a = graphics_getColor()
	local w, h = graphics_getDimensions()

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
			for i,v in ipairs(order) do
				if i >= yScroll and i <= maxLines + yScroll - 4 then
					local k = order[i]
					local v = varprint[k]

					local t = type(v)
					addType(t)

					local name = gsub(tostring(k), reppatt, rep)
					if checkUtf8(name) then
						addName(name)
					else
						addName(":ERROR: (utf8)")
					end

					local data
					if t == "string" then
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

		local header
		if debugger.useTitleBar then
			header = "\t"..path.."\n\tType: "..vartype
		else
			header = "\t"..path.."\n\tType: "..vartype.." ~"..floor(ram+0.5).." KB "..dep.getFPS().." FPS"
		end
		local hprinted = count(stringType, "\n")*fheight

		-- Printed text and Prompt
		graphics_setColor(color.bgActive)
		graphics_rectangle("fill", 0, 0, tt-1, hlg)
		graphics_rectangle("fill", 0, ceil(h-fheight), w, fheight)

		graphics_setColor(color.fgActive)
		if debugger.printArea > 0 then
			graphics_setScissor(0, 0, tt-1, hlg)
			graphics_printf(lg, 0, 0, tt, "left")
			graphics_setScissor()
		end

		pcall(promtPrint, w, h, fheight)

		-- Environment Display
		if debugger.printArea < 1 then
			graphics_setScissor(tt, 0, w-tt, ceil(h-fheight-1))

			graphics_setColor(color.bgActive)
			graphics_rectangle("fill", tt, 0, w-tt, hprinted+fheight*2)

			graphics_setColor(color.fgActive)
			local wt = font:getWrap(stringType, (w-tt)/2)
			local wt2 = font:getWrap(stringName, (w-tt)/2-wt)
			graphics_print(stringType, tt, fheight*2)
			graphics_print(stringData, tt+wt+wt2, fheight*2)
			graphics_setColor(color.fgActive2)
			graphics_printf(header, tt, 0, w-tt, "justify")
			graphics_print(stringName, tt+wt, fheight*2)
		end
	elseif debugger.doTempPrint then
		-- Printing the print calls
		local updateDif = dep.getTime() - updateTime
		local tt = ceil(w*debugger.printArea)-1

		local _, wrap = font:getWrap(lgtemp, tt)
		local hlg = #wrap*fheight
		local tw, wrap, infoText

		graphics_setColor(color.bgNotActive)
		graphics_rectangle("fill", 0, 0, tt, hlg)
		if not debugger.useTitleBar then
			infoText = infoBox(dep.getFPS(), ram, updateDif)
			tw, wrap = font:getWrap(infoText, w)
			graphics_rectangle("fill", w-tw, 0, tw, #wrap*fheight)
		end

		graphics_setColor(color.fgNotActive)
		if debugger.printArea > 0 then
			graphics_printf(lgtemp, 0, 0, tt, "left")
		end
		if not debugger.useTitleBar then
			graphics_printf(infoText, w-tw, 0, tw, "right")
		end
	elseif not debugger.useTitleBar then
		-- Not printing the print calls
		local updateDif = dep.getTime() - updateTime
		local infoText = infoBox(dep.getFPS(), ram, updateDif)
		local tw, wrap = font:getWrap(infoText, w)

		graphics_setColor(color.bgNotActive)
		graphics_rectangle("fill", w-tw, 0, tw, #wrap*fheight)

		graphics_setColor(color.fgNotActive)
		graphics_printf(infoText, w-tw, 0, tw, "right")
	end

	if debugger.useTitleBar then
		dep.setTitle(infoTitle(dep.getRegularTitle(), dep.getFPS(), ram, dep.getTime()-updateTime))
	elseif dep.titleUpdated then
		dep.setTitle(dep.getRegularTitle())
		dep.titleUpdated = false
	end

	-- Returning the graphics state
	graphics_pop()
	graphics_setFont(oldfont)
	graphics_setScissor(xs, ys, ws, hs)
	graphics_setColor(r, g, b, a)
	graphics_setShader(oldshader)
	graphics_setBlendMode(blendmode, alphablendmode)
	graphics_getColorMask(rm, gm, bm, am)
	graphics_setWireframe(wireframe)
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
	printColor(color.red, "\tAllowing the indexing of functions for up-values might cause code-instability.\nTherefore access to indexing is only allowed within the command line.")

	local getupvalue = debug.getupvalue
	local setupvalue = debug.setupvalue
	local traceback  = debug.traceback
	local jitfuncinfo, isFile, lines
	pcall(function()
		jitfuncinfo = require("jit").util.funcinfo

		local filesystem = require("love.filesystem")
		isFile = filesystem.isFile
		lines = filesystem.lines
	end)

	local upval = setmetatable({}, {__mode = "kv"})
	local ret = setmetatable({}, {__mode = "kv", __index=function()return{}end})
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
				for k,v in pairs(fup) do _, t[k] = getupvalue(f, v) end
				return t
			elseif k == "___code" then
				if jitfuncinfo then
					local info = jitfuncinfo(f)
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

	if desc and jitfuncinfo then
		local amount, bytes = 1, 5
		local hardnames = {
			[realPrint] = "print"
		}
		local indexed = {
			[_G] = true,
			[package.loaded] = true
		}
		local function addName(item, path)
			if not hardnames[item] then
				if type(item) == "table" then
					if not indexed[item] then
						indexed[item] = true
						for k,v in pairs(item) do
							addName(v, path.."."..k)
						end
					end
				elseif type(item) == "function" then
					hardnames[item] = path
					amount = amount + 1
					bytes = bytes + #path
				end
			end
		end
		for i,v in ipairs{
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

				local info = jitfuncinfo(f)
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
						v = defined:match("[^_a-zA-Z0-9]function%s+([_a-zA-Z][%.%:_a-zA-Z0-9]*)[^_a-zA-Z0-9]")
						if not v then
							v = defined:match("[^_a-zA-Z0-9]([_a-zA-Z][%.%:_a-zA-Z0-9]*)%s*=%s*%(*function[^_a-zA-Z0-9]")
							if not v then
								v = "(unnamed)"
							end
						end
						v = v.." ("..source..":"..tostring(linedefined)..")"
					end
				end

				if v then
					v = "function: "..v
					if hardnames[f] then
						hardnames[f] = nil
					end
				elseif hardnames[f] then
					v = "function: "..hardnames[f]
				else
					local __tostring = funcMeta.__tostring
					funcMeta.__tostring = nil
					v = tostring(f)
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
	end

	debug.setmetatable(function()end, funcMeta)
end

function debugger.monitorGlobal(writeTo)
	if type(writeTo) ~= "string" then writeTo = "_G (log).txt" end

	printColor(color.red, "\tNow monitoring the global environment for changes.\nWill be logged to '"..writeTo.."'.")

	if not love.filesystem.isFile(writeTo) then
		love.filesystem.write(writeTo, "")
	end

	local file = love.filesystem.newFile(writeTo, "a")

	local traceback = debug.traceback

	setmetatable(_G, {
		__newindex = function(t, k, v)
			if notInDebugger() then
				local msg = "New global defined: "..tostring(k).."="..tostring(v).." (type "..type(v)..")"
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
			src = getinfo(src, "S").short_src
		end
		if type(inLine) ~= "number" then
			printColor(color.red, "You need to pass the line to check in!")
			return
		end

		printColor(color.blue, "Enabled local viewer.\nAny future passes on that line will now write a table!")

		sethook(function(event, line)
			if line == inLine and src == getinfo(2, "S").short_src then
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

function debugger.getStack(stack)
	stack = (stack or 1) + 1
	local getinfo = debug.getinfo
	local getlocal = debug.getlocal

	local var = {}

	local i=0
	local stackInfo = getinfo(stack, "fn")
	while stackInfo do
		local this = {
			["(Function:)"] = stackInfo.func,
			["(Function Name:)"] = stackInfo.name
		}
		i = i + 1
		var[i] = this

		local l = 1
    while true do
      local name, value = getlocal(stack, l)
      if not name then break end
      this[name] = value
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
		for i,v in ipairs(args) do
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

function debugger.newCommand(name, args, func)
	assert(type(name) == "string", "Command Name has to be a string!")
	assert(type(args) == "string", "Argument Pattern has to be a string!")
	assert(type(func) == "function" or getmetatable(func) and rawget(getmetatable(func), "__call"), "Argument function needs to be callable!")

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
	if commands[as] == nil then
		commands[as] = commands[name]
		commands[name].alias[#commands[name].alias+1] = as
	else
		error(":Command '"..tostring(name).."' exists already.")
	end
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
	for k,v in pairs(commands) do
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
		for i,v in ipairs(cmd) do
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
	__call = function(self, other, cb)
		-- Auto-Injection
		if other == nil then other = love end
		if cb == nil then cb = other end

		self.setOverrides(cb)

		local __update = other.update
		local __draw = other.draw

		loadstring([[
			local self, other, __update, __draw, lgraphics, pcall, realPrint = ...

			if __update then
				function other.update(...)
					local s, r = pcall(self.update, ...)
					if not s then
						realPrint(r)
					end

					__update(...)
				end
			else
				function other.update(...)
					local s, r = pcall(self.update, ...)
					if not s then
						realPrint(r)
					end
				end
			end

			if __draw then
				function other.draw(...)
					__draw(...)

					local s, r = pcall(self.draw)
					if not s then
						lgraphics.pop()
						realPrint(r)
					end
				end
			else
				function other.draw(...)
					local s, r = pcall(self.draw)
					if not s then
						lgraphics.pop()
						realPrint(r)
					end
				end
			end
		]], "run_injection")(self, other, __update, __draw, lgraphics, pcall, realPrint)

		return self
	end
})

-- If you want to use this as an error-handler
-- Will probably fail if the error was a stack overflow.
function debugger.errhand(message, stack)
	message = message or ""
	stack = stack or 2

	local love = require "love"
	local timer = require "love.timer"
	local event = require "love.event"
	local graphics = require "love.graphics"

	_stackTraceback = debug.traceback(message, stack)
	printColor(color.red, _stackTraceback)

	_stackLocals = debugger.getStack(stack)
	if not indexFunctions then
		debugger.allowFunctionIndex(true)
	end

	local main, callback = {}, {}
	local bg = {0, 85, 170}
	debugger(main, callback)

	debugger.setActive(false) debugger.setActive(true)

	local dt = 0
	timer.step()

	while true do
		event.pump()
		for name, a,b,c,d,e,f in event.poll() do
			if name == "quit" then
				return a
			elseif callback[name] then
				callback[name](a,b,c,d,e,f)
			end
		end
		dt = timer.getDelta()
		timer.step()

		main.update(dt)
		if graphics.isActive() then
			graphics.clear(bg)
			main.draw()
			graphics.present()
		end

		timer.sleep(0.01)
	end
end

return debugger
