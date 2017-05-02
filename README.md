# LöveDebugger

(Not so) simple debugging tool for [Löve](https://www.love2d.org/), currently for Löve version 0.10.2 (may work with other versions).

Download the 'debugger.lua' file and include it in your Lua path or game directory (I suggest against leaving debug code in releases).

---

### Usage

Simply requiring and calling the module once after setting up *love.update*, *love.draw* and any callbacks you need should suffice for most cases.

```lua
-- Load and initialize the debugger
local debugger = require "debugger" ()
-- Calling the module makes it return itself
```

This will override/inject the update functions and required callbacks. If this is not to your liking, you may also do all this manually:

```lua
local debugger

function love.load(arg)
	debugger = require "debugger"
	debugger.setOverrides()
end

function love.update(dt)
	-- Anywhere is fine, preferably the first line
	debugger.update()

	-- Your Code
end

function love.draw()
	-- Your Code

	-- The Draw function needs to be the last line of the love.draw!
	debugger.draw()
end
```

*Do not change your callbacks after this point, or something may break.* This should not be a concern in most cases however.

To open the Lua prompt and environment, hit 'F4'.

At the bottom is said Lua prompt, at the right is said global environment. Use the keyboard to type code into the prompt, hit 'Return' to confirm and execute it.

The environment is navigated solely with your mouse and Shift key:

```
L = Left Mouse Button
R = Right Mouse Button
S = Shift (Left or Right)

Clicking the top:
	L = Go back
	R = Navigate to metatable or current 'path'

Clicking a variable name:
	L = Navigate to (table), copy name to the prompt
	R = Always copy name to the prompt
	SL = Navigate to a function's upvalues (requires calling debugger.allowFunctionIndex() beforehand, see below!)
	SR = Navigate to metatable, if defined
```

You can also use the arrow keys (up and down) to bring back previous inputs to the Lua prompt. Ctrl+V (pasting) and Ctrl+C (copying the entire prompt) is also supported.

'F5' will toggle whether print calls will be drawn to the screen while the Lua prompt is disabled or clear the current input in the Lua prompt.

---

## Additional Functions

By default, the module will assume that callbacks and the update and draw functions are stored in the 'love' table. If you decided to change it up, you may also do this:

```lua
-- Both arguments are tables holding information
local debugger = require "debugger" (update_and_draw_here, callbacks_here)
```

Furthermore, if you went the manual route, `debugger.setOverrides` allows for an optional argument: A table storing all callbacks.

There's also a few additional functions you may access if required.

```lua
debugger.setFont(font)
-- Sets a new font to be used by the console and such
debugger.getFont()
-- Returns the currently used font

debugger.print(colorTable, ...)
-- Print exclusively to the debugger's console in the defined color
debugger.realPrint(...)
-- Regular Lua print function
debugger.clear()
-- Clears the console

debugger.setActive(active)
-- Sets whether or not the Lua prompt is active
debugger.isActive()
-- Returns whether the Lua prompt is active

debugger.allowFunctionIndex(desc)
-- Enables function indexing, allowing you to browse the upvalues
-- of functions by Shift-Left-Clicking them in the environment.
-- The optional argument is whether or not to also give functions
-- better 'tostring' values (more easily readable/descriptive),
-- like 'function: lib.func (lib.lua:4)'.

debugger.monitorGlobal(writeTo)
-- Enables monitoring the global environment for unusual changes or activities
-- (by which I mean, new definitions, accessing unused variables etc.).
-- 'writeto' is the file path (within the Löve save directory) to write the output to.
-- Defaults to '_G (log).txt'.
```

There's also a few constants that you may modify as well as their defaults:

```lua
debugger.activate    = "f4"
-- Löve KeyConstant of the key used to open the console.

debugger.clearPrompt = "f5"
-- Löve KeyConstant of the key used to clear the Lua prompt
-- and toggle 'debugger.doTempPrint'.

debugger.textfade    = 7
-- Time it takes for text to fade away after its 'print'
-- call in seconds while the Lua prompt is closed.

debugger.printArea   = 2/3
-- Screen Area where the prints are displayed (ratio 0.0-1.0).

debugger.maxStorage  = 100
-- How many console inputs are stored to be reused
-- (by using 'Up' and 'Down' arrow keys).

debugger.doTempPrint = true
-- Whether or not to print to the screen if the console is closed.

debugger.color = {...}
-- A list of several colors used by the debugger, most notably:
-- fgActive, fgActive2, bgActive,
-- fgNotActive, bgNotActive
```

---

Copyright © 2017 "DPlayer234"/"DPlay"<br>
This work is free. You can redistribute it and/or modify it under the<br>
terms of the Do What The Fuck You Want To Public License, Version 2,<br>
as published by Sam Hocevar. See the COPYING file for more details.
