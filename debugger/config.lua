--[[
Copyright © 2017-2018 Darius "DPlay" K.
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the COPYING file for more details.
]]
return function(DBG)
	DBG.activate     = "f4"   -- Löve KeyConstant of the key used to open the console. (Default: 'f4')
	DBG.clearPrompt  = "f5"   -- Löve KeyConstant of the key used to clear the Lua prompt and toggle 'DBG.doTempPrint'. (Default: 'f5')
	DBG.textFade     = 7      -- Time it takes for text to fade away after its 'print' call in seconds.
	DBG.printArea    = 2/3    -- Screen Area where the prints are displayed (ratio 0.0-1.0). (Default: 2/3)
	DBG.doTempPrint  = true   -- Whether or not to print to the screen if the console is closed.
	DBG.maxStorage   = 100    -- How many console inputs are stored to be reused (by using 'Up' and 'Down' arrow keys). (Default: 100)
	DBG.useTitleBar  = true   -- Whether or not to print FPS, Lua Ram Usage and update time to the window title bar. (Default: true)
	DBG.replaceTabs  = "    " -- Replace tab character in prints with the specified string.

	DBG.color = {             -- Various colors used
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

	DBG.addSource()
end
