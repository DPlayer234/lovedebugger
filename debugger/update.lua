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

	local table, math = table, math
	local assert, type, tonumber, unpack, pcall, loadstring, getmetatable, next, select = assert, type, tonumber, unpack, pcall, loadstring, getmetatable, next, select

	DBG._updateEvents = {}
	DBG._updateTime = 0

	-- Updates the DBG
	function DBG.update(dt)
		assert(type(dt) == "number", "Argument #1 to DBG.update(dt) must be a number!")

		-- Removing text from the temporary output
		if #DBG._lgTime > 0 then
			local ctime = love_timer.getTime()
			if DBG._lgTime[1] + DBG.textFade < ctime then
				table.remove(DBG._lgTemp, 1)
				table.remove(DBG._lgTemp, 1)
				table.remove(DBG._lgTime, 1)
			end
		end

		if DBG.isActive() then
			-- Clearing the prompt
			if DBG.isDown(DBG.clearPrompt) then
				DBG._textTable = {}
				DBG._textPosition = 1
			end

			-- Getting previous inputs
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

			-- Clipboard
			if (((DBG.isDown("lctrl") or DBG.isDown("rctrl")) and DBG._keyboard.isDown("v")) or (DBG._keyboard.isDown("lctrl", "rctrl") and DBG.isDown("v")) or DBG.isDown("insert")) and love.system then
				local cbt = love.system.getClipboardText()
				if type(cbt) == "string" then
					for p,c in utf8.codes(cbt) do
						DBG.callbacks.textinput(utf8.char(c))
					end
				end
			elseif (((DBG.isDown("lctrl") or DBG.isDown("rctrl")) and DBG._keyboard.isDown("c")) or (DBG._keyboard.isDown("lctrl", "rctrl") and DBG.isDown("c"))) and love.system then
				love.system.setClipboardText(table.concat(DBG._textTable, ""))
			end

			-- Handling console execution.
			if DBG.isDown("return") and #DBG._textTable > 0 then
				DBG._textInput = table.concat(DBG._textTable, "")

				-- Storing current input to be reused
				table.insert(DBG._lastInput, 1, DBG._textTable)
				DBG._lastSelect = 0
				if #DBG._lastInput > DBG.maxStorage then
					table.remove(DBG._lastInput, #DBG._lastInput)
				end

				DBG._textTable = {}
				DBG._textPosition = 1
				if DBG._textInput:find("^[/\\!:%.%*]") then
					-- A command. Has to be.
					local args = {}
					local inString, string = false, nil
					for match in DBG._textInput:gmatch("%S+") do
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

					local one = table.remove(args, 1)
					local command = DBG._commands[one:sub(2, #one)]
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
								DBG.printColor(DBG.color.yellow, out or ":Executed.")
							else
								DBG.printColor(DBG.color.red, ":ERROR:" .. DBG._tostring(out))
							end
						else
							DBG.printColor(DBG.color.red, ":ERROR:Incorrect arguments...")
						end
					else
						DBG.printColor(DBG.color.red, ":ERROR:Unknown command. Add commands with DBG.newCommand(name, args, function)")
					end
				else
					-- Attempting return to print that on the screen
					DBG.printColor(DBG.color.yellow, ">> " .. DBG._textInput)

					local r = { loadstring("local getmetatable=...;return "..DBG._textInput, DBG._LOADSTRING_SRC) }
					if not r[1] then
						r = { loadstring("local getmetatable=...;"..DBG._textInput, DBG._LOADSTRING_SRC) }
					end
					if r[1] then
						r = { pcall(r[1], debug.getmetatable) }
					end
					if r[1] == true then
						local max = 0
						for i,v in next, r do if i > max then max = i end end
						if max > 1 then
							r[1] = ":Return values"
							for i=2, max do
								local v = r[i]
								r[i] = "[" .. DBG._tostring(i-1) .. "] (" .. DBG._validateUtf8(DBG.typeReal(v)) .. ") " .. DBG._validateUtf8(DBG._toSingleLine(DBG._toDisplayString(v)))
							end
							if #r > 0 then
								DBG.printColor(DBG.color.yellow, table.concat(r, "\n\t"))
							end
						end
					else
						DBG.printColor(DBG.color.red, ":ERROR:" .. DBG._tostring(r[2]))
					end
				end
			end

			-- Other crap with the environment (mostly navigation)
			local dv, index = DBG._getDvIndex(DBG._envPath)

			if (DBG.isDown("m1") or DBG.isDown("m2")) then
				if love_mouse.getX() >= math.ceil(love_graphics.getWidth() * DBG.printArea) then
					local newId = math.floor(love_mouse.getY() / DBG._fontHeight - 2)

					if newId >= 0 then
						-- Clicked on a variable
						if index and index[newId+DBG._yScroll] then
							local newText = index[newId+DBG._yScroll]

							-- Getting variable name:
							local newEnvPath = ""
							local newType = type(newText)
							if newType ~= "string" and newType ~= "number" then newText = DBG._tostring(newText) end
							if DBG._envPath == "_G" then
								newEnvPath = newText
							else
								newEnvPath = DBG._envPath .. "[" .. DBG._toSingleLine(DBG._toDisplayString(newText)) .. "]"
							end

							local dv = DBG._getDv(newEnvPath)
							if type(dv) == "table" and DBG.isDown("m1") then
								-- LMB
								-- Navigating to another table
								DBG._envPath = newEnvPath
								DBG._yScroll = 1
							elseif DBG._keyboard.isDown("lshift", "rshift") then
								-- Holding Shift
								if DBG.isDown("m2") then
									-- RMB
									-- Navigating to its metatable
									local m = debug.getmetatable(dv)

									if type(m) == "table" then
										DBG._envPath = "getmetatable("..newEnvPath..")"
										DBG._yScroll = 1
									end
								elseif DBG._indexFunctions and type(dv) == "function" then
									-- LMB
									-- Navigating to a function's upvalues
									DBG._envPath = newEnvPath
									DBG._yScroll = 1
								end
							else
								-- Copying the variable name to the prompt
								for p,c in utf8.codes(DBG._nicerEnvPath(newEnvPath)) do
									DBG.callbacks.textinput(utf8.char(c))
								end
							end
						else
							-- Copying the variable name to the prompt
							for p,c in utf8.codes(DBG._nicerEnvPath(DBG._envPath)) do
								DBG.callbacks.textinput(utf8.char(c))
							end
						end
					else
						-- Clicked on the top
						if DBG.isDown("m2") then
							-- Navigating to the currently indexed variable's metatable
							local m = debug.getmetatable(dv)

							if type(m) == "table" then
								DBG._envPath = "getmetatable("..DBG._envPath..")"
								DBG._yScroll = 1
							end
						else
							repeat
								-- Navigating to its parent
								local s = DBG._envPath

								if s:find("^getmetatable%(.*%)$") then
									DBG._envPath = s:sub(14, #s-1)
								elseif s:find("%(%)$") then
									DBG._envPath = s:sub(1, #s-2)
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
										DBG._envPath = DBG._envPath:sub(1, r-1)
									else
										DBG._envPath = "_G"
									end
								end
							until DBG._envPath == "_G" or select(2, DBG._getDvIndex(DBG._envPath))

							DBG._yScroll = 1
						end
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

			-- Scrolling the cursor through the text
			if DBG.isDown("right") and DBG._textPosition <= #DBG._textTable then
				DBG._textPosition = DBG._textPosition + 1
			elseif DBG.isDown("left") and DBG._textPosition > 1 then
				DBG._textPosition = DBG._textPosition - 1
			end

			DBG._clearInputs()
		end

		for i=1, #DBG._updateEvents do
			local s, r = pcall(DBG._updateEvents[i].func, dt)
			if not s then
				DBG.printColor(DBG.color.red, ":ERROR:" .. DBG._tostring(r))
			end
		end

		DBG._updateProfiler()

		DBG._updateTime = love_timer.getTime()
	end

	-- Adds a function to the update loop
	function DBG.addUpdate(func, prio)
		local this = {
			func = func,
			prio = prio or 0
		}

		DBG._updateEvents[#DBG._updateEvents+1] = this
		table.sort(DBG._updateEvents, function(a, b)
			return a.prio > b.prio
		end)

		for i=1, #DBG._updateEvents do
			if DBG._updateEvents[i] == this then
				return i
			end
		end
	end

	DBG.addSource()
end
