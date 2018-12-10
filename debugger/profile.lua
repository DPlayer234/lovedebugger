--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	-- Sets up the profiler
	function DBG.setProfiler(profileLib, reportPath)
		assert(DBG._profile == nil, ":Profiler already set.")
		if type(reportPath) ~= "string" then reportPath = "profiler.txt" end

		local profile = {
			lib = profileLib,
			frame = 0, interval = 100,
			sort = "time", rows = 20,
			running = false
		}

		if (love.filesystem.getInfo(reportPath) or { type = "file" }).type ~= "file" then
			error("Report Path cannot be a file.")
		end

		local reportFile
		function profile.addReport()
			reportFile:write(profileLib.report(profile.sort, profile.rows).."\n")
		end

		function DBG.startProfiler()
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

		function DBG.stopProfiler()
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

		function DBG.setProfilerInterval(interval)
			assert(type(interval) == "number", ":Argument #1 to DBG.setProfilerInterval(interval) has to be a number.")
			profile.interval = interval

			return ":Set report interval to "..tostring(interval).." frame(s)."
		end

		function DBG.setProfilerReportArgs(sort, rows)
			assert(sort == "time" or sort == "call" or sort == nil, ":Argument #1 to DBG.setProfilerReportArgs(sort, rows) has to be 'time' or 'call'.")
			assert(type(rows) == "number" and rows > 0 or rows == nil, ":Argument #2 to DBG.setProfilerReportArgs(sort, rows) has to be a number.")

			DBG._profile.sort = sort or "time"
			DBG._profile.rows = rows or 20

			return ":Set report arguments to '"..DBG._profile.sort.."' (sort) and "..tostring(DBG._profile.rows).." (rows)."
		end

		function DBG._updateProfiler()
			if not profile.running then return end

			profile.frame = profile.frame + 1
			if profile.frame % profile.interval == 0 then
				profile.addReport()
				profileLib.reset()
			end
		end

		DBG.newCommand("pstart", "", "Starts the profiler", DBG.startProfiler)
		DBG.newCommand("pstop", "", "Stops the profiler", DBG.stopProfiler)
		DBG.newCommand("pinterval", "n", "Sets the profiler interval", DBG.setProfilerInterval)
		DBG.newCommand("preport", "sn", "Sets profiler report arguments.", DBG.setProfilerReportArgs)
		DBG.newCommand("preport", "", "Sets profiler report arguments to their defaults.", DBG.setProfilerReportArgs)

		profileLib.hookall("Lua")

		local function unhook(table)
			for k,v in next, table do
				if type(v) == "function" then
					profileLib.unhook(v)
				end
			end
		end

		-- Unhook DBG functions
		unhook(DBG)
		unhook(DBG.callbacks)
		unhook(DBG._keyboard)
		unhook(DBG._mouse)
		unhook(DBG._titleManager)

		if DBG.isFunctionIndexAllowed() and DBG.hasPrettyFunctionNames() then
			-- If the profiler given is not compatible, this will crash!
			-- I don't take any responsibility for that.
			local _defined = profileLib.hook._defined

			setmetatable(_defined, {
				__newindex = function(t, k, v)
					if v ~= nil then
						rawset(t, k, (DBG._tostring(k):gsub("function: ", "")))
					end
				end
			})
		end

		DBG._profile = profile
	end

	-- Overriden when setting the profiler
	function DBG._updateProfiler() end

	DBG.addSource()
end
