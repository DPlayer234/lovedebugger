--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	local utf8 = require "utf8"
	local love_graphics = require "love.graphics"
	local love_timer = require "love.timer"

	local table, string, math = table, string, math
	local pcall, collectgarbage = pcall, collectgarbage

	local function countString(str, patt)
		local _, c = str:gsub(patt, "")
		return c
	end

	-- Printing the Lua prompt
	function DBG._drawPrompt(w, h)
		love_graphics.setColor(DBG.color.bgActive)
		love_graphics.rectangle("fill", 0, math.ceil(h - DBG._fontHeight), w, DBG._fontHeight)

		love_graphics.setColor(DBG.color.fgActive)

		local prompt = table.concat(DBG._textTable)
		local width = DBG._font:getWidth(prompt)
		local x = width < w and 0 or w - width

		love_graphics.print(prompt, x, h - DBG._fontHeight)

		if love_timer.getTime() % 0.5 >= 0.25 then
			if DBG._textPosition > #DBG._textTable then
				love_graphics.rectangle("fill", DBG._font:getWidth(prompt), h - DBG._fontHeight, DBG._font:getWidth(" "), DBG._fontHeight)
			else
				love_graphics.rectangle("fill",
					DBG._font:getWidth(table.concat(DBG._textTable, "", 1, DBG._textPosition - 1)) + x,
					h - DBG._fontHeight,
					DBG._font:getWidth(table.concat(DBG._textTable, "", DBG._textPosition, DBG._textPosition)) - 1, DBG._fontHeight)
			end
		end
	end

	-- Gets the strings to be displayed in the environment display
	function DBG._getEnvStrings(w, h)
		local dv, index = DBG._getDvIndex(DBG._envNav)
		local envPathType = DBG.typeReal(dv):gsub(" ", " ")
		if DBG.isFunctionIndexAllowed() and envPathType == "function" then
			dv = dv[DBG.FUNCTION_UPVALUES]
		end

		local tableType, indexType = {}, 1
		local tableName, indexName = {}, 1
		local tableData, indexData = {}, 1

		local function addType(arg)
			tableType[indexType] = arg
			indexType = indexType + 1
		end

		local function addName(arg)
			tableName[indexName] = arg
			indexName = indexName + 1
		end

		local function addData(arg)
			tableData[indexData] = arg:sub(1, 150)
			indexData = indexData + 1
		end

		local maxLines = math.ceil(h / DBG._fontHeight)

		if index then
			-- Indexable
			for i=1, #index do
				if i >= DBG._yScroll and i <= maxLines + DBG._yScroll - 4 then
					local k = index[i]
					local v = dv[k]

					addType(DBG._validateUtf8(DBG.typeReal(v)))
					addName(DBG._validateUtf8(DBG._toSingleLine(k)))
					addData(DBG._validateUtf8(DBG._toSingleLine(DBG._toDisplayString(v))))
				elseif i > maxLines + DBG._yScroll - 4 then
					break
				end
			end

			addType("\t>>>\n")
			addName("")
		else
			addType(DBG._tostring(dv):gsub(" ", " ").."\n\t>>>\n")
		end

		local stringType = table.concat(tableType, " \n")
		local stringName = table.concat(tableName, " \n")
		local stringData = table.concat(tableData, "\n")

		return stringType, stringName, stringData, envPathType
	end

	-- Draws the environment
	function DBG._drawEnv(w, h)
		if DBG.printWidth < 1 then
			local tt = math.ceil(w * DBG.printWidth)

			local stringType, stringName, stringData, envPathType = DBG._getEnvStrings(w, h)

			-- Variable Path
			local path = DBG.getNiceEnvPath()

			local header = string.format("Type: %s %03dy\t", envPathType, DBG._yScroll)
			if not DBG.useTitleBar then
				header = header .. " ~" .. math.floor(DBG._ram + 0.5) .. " KB " .. love_timer.getFPS() .. " FPS"
			end
			local hprinted = countString(stringType, "\n") * DBG._fontHeight

			local wt = w - tt
			local wh = math.ceil(h - DBG._fontHeight - 1)
			local tw = math.ceil(wt * 0.25)
			local nw = math.ceil(wt * 0.25)

			love_graphics.setScissor(tt, 0, wt, wh)

			love_graphics.setColor(DBG.color.bgActive)
			love_graphics.rectangle("fill", tt, 0, wt, hprinted + DBG._fontHeight * 2)

			love_graphics.setColor(DBG.color.fgActive2)
			love_graphics.print(path, math.min(tt + 10, tt + wt - 10 - DBG._font:getWidth(path)), 0)
			love_graphics.printf(header, tt + 10, DBG._fontHeight, wt - 20, "justify")

			love_graphics.setColor(DBG.color.fgActive)

			love_graphics.setScissor(tt, 0, tw, wh)
			love_graphics.print(stringType, tt, DBG._fontHeight * 2)

			love_graphics.setScissor(tt + tw + nw, 0, wt - tw - nw, wh)
			love_graphics.print(stringData, tt + tw + nw, DBG._fontHeight * 2)

			love_graphics.setScissor(tt + tw, 0, nw, wh)
			love_graphics.setColor(DBG.color.fgActive2)
			love_graphics.print(stringName, tt + tw, DBG._fontHeight*2)
		end
	end

	-- Draws any printed text
	function DBG._drawAnyLG(w, h, lgTable, bgColor, fgColor, lgTime)
		if DBG.printWidth > 0 then
			local tt = math.ceil(w * DBG.printWidth) - 1

			local _, wrap = DBG._font:getWrap(lgTable, tt)

			while #lgTable > 2 and #wrap > math.floor(h / DBG._fontHeight - 1) do
				table.remove(lgTable, 1)
				table.remove(lgTable, 1)

				if lgTime then
					table.remove(lgTime, 1)
				end

				_, wrap = DBG._font:getWrap(lgTable, tt)
			end

			local hlg = #wrap * DBG._fontHeight

			love_graphics.setScissor(0, 0, tt, hlg)

			love_graphics.setColor(bgColor)
			love_graphics.rectangle("fill", 0, 0, tt, hlg)

			love_graphics.setColor(fgColor)
			love_graphics.printf(lgTable, 0, 0, tt, "left")

			love_graphics.setScissor()
		end
	end

	-- Draws the printed text
	function DBG._drawLG(w, h)
		DBG._drawAnyLG(w, h, DBG._lg, DBG.color.bgActive, DBG.color.fgActive)
	end

	-- Draws the temporarily printed text
	function DBG._drawLGTemp(w, h)
		if DBG.doTempPrint then
			DBG._drawAnyLG(w, h * DBG.printHeight, DBG._lgTemp, DBG.color.bgNotActive, DBG.color.fgNotActive, DBG._lgTime)
		end
	end

	-- Draws the variable info
	function DBG._drawVarInfo(w, h)
		if not DBG.useTitleBar then
			local updateDif = love_timer.getTime() - DBG._updateTime
			local infoText = infoBox(love_timer.getFPS(), DBG._ram, updateDif)
			local tw, wrap = DBG._font:getWrap(infoText, w)

			love_graphics.setColor(DBG.color.bgNotActive)
			love_graphics.rectangle("fill", w-tw, 0, tw, #wrap * DBG._fontHeight)

			love_graphics.setColor(DBG.color.fgNotActive)
			love_graphics.printf(infoText, w - tw, 0, tw, "right")
		end
	end

	-- Drawing everything
	function DBG.draw()
		-- Storing the current graphics state and resetting it
		love_graphics.push("all")
		love_graphics.origin()
		love_graphics.setFont(DBG._font)
		love_graphics.setScissor()
		love_graphics.setShader()
		love_graphics.setBlendMode("alpha")
		love_graphics.setColorMask(true, true, true, true)
		love_graphics.setWireframe(false)

		DBG._ram = collectgarbage("count")
		DBG._fontHeight = math.abs(DBG._font:getHeight() * DBG._font:getLineHeight())
		local w, h = love_graphics.getDimensions()

		if DBG.isActive() then
			-- Prompt and Environment is opened
			DBG._drawLG(w, h)
			DBG._drawPrompt(w, h)
			DBG._drawEnv(w, h)
		else
			DBG._drawLGTemp(w, h)
			DBG._drawVarInfo(w, h)
		end

		if DBG.useTitleBar then
			DBG._titleManager.setTitle(DBG._infoTitle(DBG._titleManager.getRegularTitle(), love_timer.getFPS(), DBG._ram, love_timer.getTime() - DBG._updateTime))
		elseif DBG._titleManager.titleUpdated then
			DBG._titleManager.setTitle(DBG._titleManager.getRegularTitle())
			DBG._titleManager.titleUpdated = false
		end

		-- Returning the graphics state
		love_graphics.pop()
	end

	DBG.addSource()
end
