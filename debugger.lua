--[[
Copyright © 2017 "DPlayer234"/"DPlay"
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

debugger.color = {           -- Various colors used
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
local collectgarbage = collectgarbage
local getmetatable = getmetatable
local rawset = rawset
local table = table
local string = string
local math = math
local require = require
local _tostring = tostring
local type = type
local pcall = pcall
local loadstring = loadstring or load
local pairs = pairs
local ipairs = ipairs
local tostring = function(t)
	local s,r = pcall(_tostring,t)
	return s and r or ":ERROR:"
end
local debug = require("debug")

-- Dependencies, yes, I require those. *BADUM-TSS*
local utf8 = require("utf8")
local love = require("love")
if not love.keyboard then require("love.keyboard") end
if not love.mouse then require("love.mouse") end
if not love.graphics then require("love.graphics") end
if not love.event then require("love.event") end
local dep = {getFPS=nil,getTime=nil}
if love.timer then
	dep.getFPS = love.timer.getFPS
	dep.getTime = love.timer.getTime
else
	local time = 0
	dep.getFPS = function() return 0/0 end
	dep.getTime = function() time = time + 1/60 return time end
end

local function cloneList(t)
	local n = {}
	for i,v in ipairs(t) do
		n[i] = v
	end
	return n
end

-- Setting the font
local font
local fheight
function debugger.setFont(nfont)
	if nfont:type() == "Font" then
		font = nfont
		fheight = font:getHeight()*font:getLineHeight()
	else
		error(":Not a font.")
	end
end
function debugger.getFont()
	return font
end

-- Print Calls / Wrapping the 'regular' print
local realPrint = print

local lg = {}
local lgtemp = {}
local lgtime = {}
local color = debugger.color

local function checkUtf8(s) for p,c in utf8.codes(s) do end end
local function getLines(sf)
	local nl = 0
	for i,v in ipairs(sf) do
		if i%2 == 0 then
			local _,n = v:gsub("\n","\n")
			nl = nl + n
		end
	end
	return nl
end

local lastPrint,printedTimes
local function proxyPrint(c,...)
	local args = {...}
	local top = 0
	for i,v in pairs(args) do
		args[i] = tostring(v):gsub("%z","\\0")
		local s,e = pcall(checkUtf8,args[i])
		if not s then
			args[i] = ":ERROR: (utf8)"
			c = color.red
		end
		if i > top then top = i end
	end
	for i=1,top do
		if args[i] == nil then
			args[i] = "nil"
		end
	end

	if #args < 1 then args[1] = "nil" end

	local t = table.concat(args,"\t"):gsub("\r","").."\n"

	if t ~= lastPrint then
		table.insert(lg,c)
		table.insert(lg,t)

		while getLines(lg) > love.graphics.getHeight()/fheight - 1 and #lg > 2 do
			table.remove(lg,1)
			table.remove(lg,1)
		end

		table.insert(lgtemp,c)
		table.insert(lgtemp,t)

		while getLines(lgtemp) > love.graphics.getHeight()/fheight - 1 and #lgtemp > 2 do
			table.remove(lgtemp,1)
			table.remove(lgtemp,1)
		end

		table.insert(lgtime,dep.getTime())
		lastPrint = t
		printedTimes = 1
	else
		printedTimes = printedTimes + 1
		if printedTimes == 2 then
			lg[#lg] = "(2x) "..lg[#lg]
		else
			lg[#lg] = lg[#lg]:gsub("^%(%d+x%)","("..tostring(printedTimes).."x)")
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
	proxyPrint(color.white,...)
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
-- E.g. sortedTable({ x = 5, y = 2, a = "test" }) -> { "a","x","y" }
local function sort(a,b) if type(a) == type(b) then return a<b else return tostring(a)<tostring(b) end end
local function sortedTable(t,to)
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
	pcall(table.sort,tx,sort) -- <= Real Sorting
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

-- Storing original callbacks/overriding them to be used
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
	local keypressed = function(key,scancode,isrepeat)
		inputs[key] = true
		if active then
			if key == "backspace" then
				if texttable[textPosition-1] then
					table.remove(texttable,textPosition-1)
					textPosition = textPosition - 1
				end
			elseif key == "delete" then
				if texttable[textPosition] then
					table.remove(texttable,textPosition)
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
			if text == "\n" then text = "\\n"
			elseif text == "\r" then text = "\\r" end
			if font:hasGlyphs(text) then
				table.insert(texttable,textPosition,text)
				textPosition = textPosition + 1
			end
		end,

		keyreleased = function() end,

		mousepressed = function(x,y,button,istouch)
			inputs["m"..tostring(button)] = true
		end,

		mousereleased = function() end,

		mousemoved = function() end,

		wheelmoved = function(x,y)
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
local realKeyboard = {
	isDown = love.keyboard.isDown,
	isScancodeDown = love.keyboard.isScancodeDown,
	setKeyRepeat = love.keyboard.setKeyRepeat,
	hasKeyRepeat = love.keyboard.hasKeyRepeat,
	setTextInput = love.keyboard.setTextInput,
	hasTextInput = love.keyboard.hasTextInput
}
local realMouse = {
	isDown = love.mouse.isDown,
	setVisible = love.mouse.setVisible,
	isVisible = love.mouse.isVisible,
}

local mousevisible = false
local keyrepeat = false
local hastextinput = false
local rfalse = function() return false end
local fakeKeyboard = {
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
local fakeMouse = {
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

			love.event.push("keyreleased",debugger.activate,love.keyboard.getScancodeFromKey(debugger.activate))

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

local updateTime = 0
-- Update Function
local fromPattern = "%[\"[_a-zA-Z][_a-zA-Z0-9]-\"%]"
local nicerPush = function(t) return "."..string.sub(t,3,#t-2) end
function debugger.update()
	if inputs[debugger.activate] then
		debugger.setActive(not active)
	end

	if #lgtime > 0 then
		local ctime = dep.getTime()
		if lgtime[1] + debugger.textfade < ctime then
			table.remove(lgtemp,1)
			table.remove(lgtemp,1)
			table.remove(lgtime,1)
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
					table.insert(lastinput,1,texttable)
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

		if (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("v")) or (realKeyboard.isDown("lctrl","rctrl") and inputs.v)) and love.system then
			local cbt = love.system.getClipboardText()
			if type(cbt) == "string" then
				for p,c in utf8.codes(cbt) do
					override.textinput(utf8.char(c))
				end
			end
		elseif (((inputs.lctrl or inputs.rctrl) and realKeyboard.isDown("c")) or (realKeyboard.isDown("lctrl","rctrl") and inputs.c)) and love.system then
			love.system.setClipboardText(table.concat(texttable,""))
		end

		if inputs["return"] and #texttable > 0 then
			-- Handling console execution.
			textinput = table.concat(texttable,"")

			-- Storing current input to be reused
			table.insert(lastinput,1,texttable)
			lastselect = 0
			if #lastinput > debugger.maxStorage then
				table.remove(lastinput,#lastinput)
			end

			texttable = {}
			textPosition = 1
			if textinput:match("[_a-zA-Z0-9%.%[%]\"']+%s*=[^=].*") == textinput then
				-- Probably Variable assignment
				local success,err = pcall(loadstring(textinput,"prompt"))
				if success then
					local out = ":Set variable "..textinput
					realPrint(out)
					proxyPrint(color.yellow,out)
				else
					local out = ":ERROR:"..tostring(err)
					realPrint(out)
					proxyPrint(color.red,out)
				end
			elseif textinput:match(".+%(.-%).*") == textinput or textinput:match("[^%(%)]+") then
				-- Attempting return to print that on the screen
				local r = { pcall(loadstring("return "..textinput,"prompt")) }
				if r[1] == true then
					table.remove(r,1)
					for i,v in ipairs(r) do r[i] = type(v)..":"..tostring(v) end
					if #r > 0 then
						local out = ":"..table.concat(r,"\t")
						realPrint(out)
						proxyPrint(color.yellow,out)
					end
				else
					-- Other
					if tostring(r[2]) == "attempt to call a nil value" then
						local success,err = pcall(loadstring(textinput,"prompt"))
						if not success then
							local out = ":ERROR:"..tostring(err)
							realPrint(out)
							proxyPrint(color.red,out)
						end
					else
						local out = ":ERROR:"..tostring(r[2])
						realPrint(out)
						proxyPrint(color.red,out)
					end
				end
			else
				-- Other
				local success,err = pcall(loadstring(textinput,"prompt"))
				if not success then
					local out = ":ERROR:"..tostring(err)
					realPrint(out)
					proxyPrint(color.red,out)
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
		local s,dv = pcall(loadstring("return "..display))

		if type(dv) == "table" then
			index = sortedTable(dv,index)
		elseif indexFunctions and type(dv) == "function" then
			index = sortedTable(dv.___allupvalues,index)
		end
		if not s then dv = nil end

		if (inputs.m1 or inputs.m2) then

			if love.mouse.getX() >= math.ceil(love.graphics.getWidth()*debugger.printArea) then
				local nid = math.floor(love.mouse.getY()/fheight-2)
				local shift = realKeyboard.isDown("lshift","rshift")

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
							ndisplay = display.."["..(ntype=="string" and string.format("%q",ntext) or tostring(ntext)).."]"
						end

						local s,dv = pcall(loadstring("return "..ndisplay))
						if s and type(dv) == "table" and inputs.m1 then
							-- LMB
							-- Navigating to another table
							display = ndisplay
							index = sortedTable(dv,index)

							yScroll = 1
						elseif shift then
							-- Holding Shift
							if inputs.m2 then
								-- RMB
								-- Navigating to its metatable
								local m = getmetatable(dv)

								if type(m) == "table" then
									display = "getmetatable("..ndisplay..")"
									index = sortedTable(m,index)
									yScroll = 1
								end
							elseif indexFunctions and type(dv) == "function" then
								-- LMB
								-- Navigating to a function's upvalues
								display = ndisplay
							end
						else
							-- Copying the variable name to the prompt
							for p,c in utf8.codes(ndisplay:gsub(fromPattern,nicerPush)) do
								override.textinput(utf8.char(c))
							end
						end
					else
						-- Copying the variable name to the prompt
						for p,c in utf8.codes(display:gsub(fromPattern,nicerPush)) do
							override.textinput(utf8.char(c))
						end
					end
				else
					-- Clicked on the top
					if inputs.m2 then
						-- Navigating to the currently indexed variable's metatable
						local m = getmetatable(dv)

						if type(m) == "table" then
							display = "getmetatable("..display..")"
							index = sortedTable(m,index)
							yScroll = 1
						end
					else
						-- Navigating to its parent
						local s = display

						if s:find("^getmetatable%(.*%)$") then
							display = string.sub(s,14,#s-1)
						elseif s:find("%(%)$") then
							display = string.sub(s,1,#s-2)
						else
							local e,_e = string.find(s,"%[")
							if e then s = string.sub(s,e+1,#s) end
							local r = 0
							while e do
								r = r + e
								e,_e = string.find(s,"%[")
								if e then s = string.sub(s,e+1,#s) end
							end

							if r > 0 then
								display = string.sub(display,1,r-1)
							else
								display = "_G"
							end
						end

						local s,dv = pcall(loadstring("return "..display))
						if s then
							if type(dv) == "table" then
								index = sortedTable(dv,index)
							elseif indexFunctions and type(dv) == "function" then
								index = sortedTable(dv.___allupvalues,index)
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

	updateTime = dep.getTime()
end

local function count(str,patt)
	local _,c = string.gsub(str,patt,"")
	return c
end

-- Draw Function(s)
local lgraphics = love.graphics

local reppatt = "[\r\n\t\v\\%z\"]"
local rep = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\\"] = "\\\\", ["\0"] = "\\0", ["\""] = "\\\"" }
-- Printing the Lua prompt
local function promtPrint(w,h,fheight)
	local prompt = table.concat(texttable)
	local width = font:getWidth(prompt)
	local x = width < w and 0 or w-width
	lgraphics.print(prompt,x,h-fheight)
	if dep.getTime()%0.5 >= 0.25 then
		if textPosition > #texttable then
			lgraphics.rectangle("fill",font:getWidth(prompt),h-fheight,font:getWidth(" "),fheight)
		else
			lgraphics.rectangle("fill",font:getWidth(table.concat(texttable,"",1,textPosition-1))+x,h-fheight,font:getWidth(table.concat(texttable,"",textPosition,textPosition))-1,fheight)
		end
	end
end

-- Drawing everything
function debugger.draw()
	-- Storing the current graphics state and resetting it
	lgraphics.push()
	lgraphics.origin()

	local ram = collectgarbage("count")

	fheight = math.abs(font:getHeight()*font:getLineHeight())

	local oldfont = lgraphics.getFont()
	lgraphics.setFont(font)

	local xs,ys,ws,hs = lgraphics.getScissor()
	lgraphics.setScissor()

	local oldshader = lgraphics.getShader()
	lgraphics.setShader()

	local blendmode, alphablendmode = lgraphics.getBlendMode()
	lgraphics.setBlendMode("alpha")

	local rm,gm,bm,am = lgraphics.getColorMask()
	lgraphics.setColorMask(true,true,true,true)

	local wireframe = lgraphics.isWireframe()
	lgraphics.setWireframe(false)

	local r,g,b,a = lgraphics.getColor()
	local w,h = lgraphics.getDimensions()

	if active then
		-- Prompt and Environment is opened
		local tt = math.ceil(w*debugger.printArea)

		local _,wrap = font:getWrap(lg,tt)
		local hlg = #wrap*fheight

		local varprint
		local success,v = pcall(loadstring("return "..display))
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

		local printType,indexType = {},1
		local printName,indexName = {},1
		local printData,indexData = {},1

		local function addType(arg)
			printType[indexType] = arg
			indexType = indexType + 1
		end
		local function addName(arg)
			printName[indexName] = arg
			indexName = indexName + 1
		end
		local function addData(arg)
			printData[indexData] = arg:sub(1,150)
			indexData = indexData + 1
		end

		local maxLines = math.ceil(lgraphics.getHeight()/fheight)

		if vartype == "table" or (indexFunctions and vartype == "function") then
			-- Indexable
			local order = index
			for i,v in ipairs(order) do
				if i >= yScroll and i <= maxLines + yScroll - 4 then
					local k = order[i]
					local v = varprint[k]

					local t = type(v)
					addType(t)

					local name = tostring(k):gsub(reppatt,rep)
					if pcall(checkUtf8,name) then
						addName(name)
					else
						addName(":ERROR: (utf8)")
					end

					local data
					if t == "string" then
						data = '"'..v:gsub(reppatt,rep)..'"'
					else
						data = tostring(v):gsub(reppatt,rep)
					end
					if pcall(checkUtf8,data) then
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
			addType(tostring(varprint):gsub(" "," ").."\n\t>>>\n")
		end

		-- Variable Path
		local path = (display == "_G" and "env" or "env > "..display):gsub("%[\""," > "):gsub("\"%]","")
		if font:getWidth("\t"..path) > w-tt then
			while font:getWidth("\t…"..path) > w-tt do
				local byteoffset = utf8.offset(path,2)
				if byteoffset then
					path = string.sub(path,byteoffset,#path)
				else
					break
				end
			end
			path = "…"..path
		end

		local stringType = table.concat(printType," \n")
		local stringName = table.concat(printName," \n")
		local stringData = table.concat(printData,"\n")

		local header = "\t"..path.."\n\tType: "..vartype.." ~"..math.floor(ram+0.5).." KB "..dep.getFPS().." fps"
		local hprinted = count(stringType,"\n")*fheight

		-- Printed text and Prompt
		lgraphics.setColor(color.bgActive)
		lgraphics.rectangle("fill",0,0,tt-1,hlg)
		lgraphics.rectangle("fill",0,math.ceil(h-fheight),w,fheight)

		lgraphics.setColor(color.fgActive)
		lgraphics.setScissor(0,0,tt-1,hlg)
		lgraphics.printf(lg,0,0,tt,"left")
		lgraphics.setScissor()

		pcall(promtPrint,w,h,fheight)

		-- Environment Display
		if debugger.printArea < 1 then
			lgraphics.setScissor(tt,0,w-tt,math.ceil(h-fheight-1))

			lgraphics.setColor(color.bgActive)
			lgraphics.rectangle("fill",tt,0,w-tt,hprinted+fheight*2)

			lgraphics.setColor(color.fgActive)
			local wt = font:getWrap(stringType,(w-tt)/2)
			local wt2 = font:getWrap(stringName,(w-tt)/2-wt)
			lgraphics.print(stringType,tt,fheight*2)
			lgraphics.print(stringData,tt+wt+wt2,fheight*2)
			lgraphics.setColor(color.fgActive2)
			lgraphics.printf(header,tt,0,w-tt,"justify")
			lgraphics.print(stringName,tt+wt,fheight*2)
		end
	elseif debugger.doTempPrint then
		-- Printing the print calls
		local updateDif = dep.getTime() - updateTime
		local tt = math.ceil(w*debugger.printArea)-1

		local _,wrap = font:getWrap(lgtemp,tt)
		local hlg = #wrap*fheight
		local tw = font:getWidth("~0000000 KB\n0.000000 sec.")

		lgraphics.setColor(color.bgNotActive)
		lgraphics.rectangle("fill",0,0,tt,hlg)
		lgraphics.rectangle("fill",w-tw,0,tw,3*fheight)

		lgraphics.setColor(color.fgNotActive)
		lgraphics.printf(lgtemp,0,0,tt,"left")
		lgraphics.printf(string.format("%d fps\n~%.1f KB\n%.6f sec.",dep.getFPS(),ram,updateDif),w-tw,0,tw,"right")
	else
		-- Not printing the print calls
		local updateDif = dep.getTime() - updateTime
		local tw = font:getWidth("~0000000 KB\n0.000000 sec.")

		lgraphics.setColor(color.bgNotActive)
		lgraphics.rectangle("fill",w-tw,0,tw,3*fheight)

		lgraphics.setColor(color.fgNotActive)
		lgraphics.printf(string.format("%d fps\n~%.1f KB\n%.6f sec.",dep.getFPS(),ram,updateDif),w-tw,0,tw,"right")
	end

	-- Returning the graphics state
	lgraphics.pop()
	lgraphics.setFont(oldfont)
	lgraphics.setScissor(xs,ys,ws,hs)
	lgraphics.setColor(r,g,b,a)
	lgraphics.setShader(oldshader)
	lgraphics.setBlendMode(blendmode,alphablendmode)
	lgraphics.getColorMask(rm,gm,bm,am)
	lgraphics.setWireframe(wireframe)
end

function debugger.isActive()
	return active
end

if debug then
	-- Up-Value-getter
	function debugger.allowFunctionIndex(desc)
		indexFunctions = true
		local out = "\tAllowing the indexing of functions for up-values might cause code-instability.\nTherefore access to indexing is only allowed within the command line."
		realPrint(out)
		proxyPrint(color.red,out)

		local getupvalue = debug.getupvalue
		local setupvalue = debug.setupvalue
		local traceback  = debug.traceback
		local jitfuncinfo, isFile
		pcall(function()
			jitfuncinfo = require("jit").util.funcinfo

			local filesystem = require("love.filesystem")
			isFile = filesystem.isFile
			lines = filesystem.lines
		end)

		local codepath = traceback():match("^stack traceback:%s*(.-):")
		local allowed = "[string \"prompt\"]:1:"

		local upval = setmetatable({},{__mode = "kv"})
		local ret = setmetatable({},{__mode = "kv",__index=function()return{}end})
		local getlist = function(f)
			if upval[f] then
				return upval[f]
			else
				local fup = {}

				local i = 1
				local k,v = getupvalue(f,i)
				while k do
					fup[k] = i
					i = i + 1
					k,v = getupvalue(f,i)
				end

				upval[f] = fup
				return fup
			end
		end

		local funcMeta = {
			__index = function(f,k)
				local traceback = traceback()
				local illegal = true
				if traceback:find(codepath,1,true) then illegal = false end
				if traceback:find(allowed ,1,true) then illegal = false end
				if illegal then error("attempt to index a function value",2) end

				local fup = getlist(f)

				if k == "___allupvalues" then
					local t = ret[f]
					local _
					for k,v in pairs(fup) do _,t[k] = getupvalue(f,v) end
					return t
				elseif k == "___code" then
					if jitfuncinfo then
						local info = jitfuncinfo(f)
						local source = (info.source or ""):gsub("^@","")
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

							return table.concat(codelines,"\n")
						else
							error("unable to find code file")
						end
					else
						error("Cannot get code... No JIT utils?")
					end
				elseif fup[k] then
					local k,v = getupvalue(f,fup[k])
					return v
				else
					error("attempt to get invalid upvalue",2)
				end
			end,
			__newindex = function(f,k,v)
				local fup = getlist(f)
				if fup[k] then
					setupvalue(f,fup[k],v)
				else
					error("attempt to set invalid upvalue",2)
				end
			end,
			__metatable = false
		}

		if desc and jitfuncinfo then
			local names = setmetatable({},{
				__index = function(t,f)
					local v

					local info = jitfuncinfo(f)
					local source = (info.source or ""):gsub("^@","")
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
								v = defined:match("[^_a-zA-Z0-9]([_a-zA-Z][%.%:_a-zA-Z0-9]*)%s*=%s*function[^_a-zA-Z0-9]")
							end
							v = v.." ("..source..":"..tostring(linedefined)..")"
						end
					end

					if v then
						local s,e = pcall(checkUtf8,v)
						if not s then
							v = ":ERROR: (utf8)"
						end
						v = "function: "..v
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
		end

		debug.setmetatable(function()end,funcMeta)
	end
else
	function debugger.allowFunctionIndex()
		local out = "\tCould not find the default debug library! Therefore function indexing cannot be enabled..."
		realPrint(out)
		proxyPrint(color.red,out)
	end
end

function debugger.monitorGlobal(writeTo)
	if type(writeTo) ~= "string" then writeTo = "_G (log).txt" end

	local out = "\tNow monitoring the global environment for changes.\nWill be logged to '"..writeTo.."'."
	realPrint(out)
	proxyPrint(color.red,out)

	if not love.filesystem.isFile(writeTo) then
		love.filesystem.write(writeTo,"")
	end

	local file = love.filesystem.newFile(writeTo,"a")

	local traceback = debug and debug.traceback or function()end

	setmetatable(_G,{
		__newindex = function(t,k,v)
			local msg = "New global defined: "..tostring(k).."="..tostring(v).." (type "..type(v)..")"

			realPrint(msg)
			proxyPrint(color.blue,msg)

			local tb = traceback(msg, 2)
			file:write(tb.."\n\n")
			file:flush()
			rawset(t,k,v)
		end,
		__index = function(t,k)
			local msg = "Trying to access undefined global: "..tostring(k)

			realPrint(msg)
			proxyPrint(color.blue,msg)

			local tb = traceback(msg, 2)
			file:write(tb.."\n\n")
			file:flush()
			return nil
		end
	})
end

debugger.setFont(lgraphics.getFont())

debugger.A_DontScrewWith = true
debugger.B_TheVariables = true
debugger.C_OrItMayCrash = true

setmetatable(debugger,{
	__call = function(self,other,cb)
		-- Auto-Injection
		if other == nil then other = love end
		if cb == nil then cb = other end

		self.setOverrides(cb)

		local __update = other.update
		local __draw = other.draw

		if __update then
			function other.update(...)
				local s,r = pcall(self.update)
				if not s then
					realPrint(r)
				end

				__update(...)
			end
		else
			function other.update(...)
				local s,r = pcall(self.update)
				if not s then
					realPrint(r)
				end
			end
		end

		if __draw then
			function other.draw(...)
				__draw(...)

				local s,r = pcall(self.draw)
				if not s then
					lgraphics.pop()
					realPrint(r)
				end
			end
		else
			function other.draw(...)
				local s,r = pcall(self.draw)
				if not s then
					lgraphics.pop()
					realPrint(r)
				end
			end
		end

		return self
	end
})

return debugger
