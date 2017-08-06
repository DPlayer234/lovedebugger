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

This will override/monkey-patch the update functions and required callbacks. If this is not to your liking, you may also do all this manually:

```lua
-- Probably in your main.lua or something...
local debugger

function love.load(arg)
	debugger = require "debugger"
	debugger.setOverrides()
	-- You cannot easily circumvent letting the debugger monkey-patch
	-- some callbacks. Sorry. :/
end

function love.update(dt)
	-- Anywhere is fine, preferably the first line
	debugger.update(dt)

	-- Your Update Code...
end

function love.draw()
	-- Your Draw Code...

	-- The Draw function needs to be the last line of the love.draw!
	debugger.draw()
end
```

*Do not change your callbacks after this point, or something may break.* This should not be a concern in most cases however.

To open the Lua prompt and environment, hit 'F4' (debugger.activate).

At the bottom is said Lua prompt, at the right is said global environment. Use the keyboard to type code into the prompt, hit 'Return' to confirm and execute it.

Additionally, it supports commands. Commands can be accessed by prefixing a command's name with '/', '\\', '!', ':', '.', or '\*' and listing all arguments separated with spaces. By default, it comes with the following ones:

```
/command <required> [optional]
	Information

/index [nicer_name]
	The same as debugger.allowFunctionIndex(nicer_name).
/global [path]
	The same as debugger.monitorGlobal(path).
/clear
	Clears all prints from the screen.
/to [path]
	Moves to the defined location in the environment. No arguments means back to the root.
/loc
	Displays the current location in the environment.
/local <source> <inLine>
/local
	See debugger.viewLocals(source, inLine) further down.
/help [command]
	Either lists all commands, or if the name of one is passed, shows all valid argument patterns.
```

You can also add custom commands like so:

```lua
debugger.newCommand(name, arg_pattern, func)
-- The argument pattern is a string. Every character represents an argument.
-- 's' means a string is expected, 'n' a number and 'b' a boolean.
-- There can be multiple commands with the same name and different arguments.
-- Commands added earlier are always prioritized.
-- If the passed function returns anything, this will printed to the screen in yellow.

-- Example:
debugger.newCommand("ret", "snb", function(string, number, boolean)
	return string..tostring(number)..tostring(boolean)
end)
-- This can now be called as '/ret hi 5 false' and will print 'hi5false' to the screen.
```

Now to the environment. It is navigated solely with your mouse and Shift key:

```
L = Left Mouse Button
R = Right Mouse Button
S = Shift (Left or Right)

Clicking the top:
	L = Go back
	R = Navigate to the metatable of the current 'path'

Clicking a variable name:
	L = Navigate to table, copy name to the prompt otherwise
	R = Always copy name to the prompt
	SL = Navigate to a function's upvalues (requires calling debugger.allowFunctionIndex() beforehand, see below!)
	SR = Navigate to metatable, if defined
```

You can also use the arrow keys (up and down) to bring back previous inputs to the Lua prompt. Ctrl+V (pasting) and Ctrl+C (copying the entire prompt) is also supported.

'F5' (debugger.clearPrompt) will toggle whether print calls will be drawn to the screen while the Lua prompt is disabled or clear the current input in the Lua prompt.

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
debugger.tempClear()
-- Only clear the temporary console

debugger.setActive(active)
-- Sets whether or not the Lua prompt is active
debugger.isActive()
-- Returns whether the Lua prompt is active

debugger.addUpdate(func, priority)
-- Adds a function to be called every frame. The function is passed dt (if dt is passed
-- to debugger.update).

debugger.allowFunctionIndex(nicer_name)
-- Enables function indexing, allowing you to browse the upvalues
-- of functions by Shift-Left-Clicking them in the environment.
-- The optional argument is whether or not to also give functions
-- better 'tostring' values (more easily readable/descriptive),
-- like 'function: lib.func (lib.lua:4)' at the cost of some speed.

debugger.monitorGlobal(writeTo)
-- Enables monitoring the global environment for unusual changes or activities
-- (by which I mean, new definitions, accessing unused variables etc.).
-- 'writeto' is the file path (within the Löve save directory) to write the output to.
-- Defaults to '_G (log).txt'.

debugger.viewLocals(source, inLine, var, key)
-- Used debug.sethook to write the locals given to a table.
-- 'source' has to be either a relative file-name or a function in the same file.
-- 'inLine' is the line number, at which to pick out the variables from.
-- 'var' and 'key' are optional: If neither is defined, it will write the table to the global
-- variable _local. If only 'var' is defined, it will write it to a global variable of
-- the same name. If both are defined, 'var' is expected to be a table and 'key' is the key in that
-- table it will write to.
-- Calling it without any arguments will reset it. Calling it while running will override the
-- existing routine.

debugger.getStack(stack_level)
-- Returns a table containing with each level of the current stack as its own table.
-- Each of the stack-tables contains all local variables at that point as well as all a
-- reference to the running function and whatever debug.getinfo gives out as a name.
-- stack_level is the stack level to start looking at.
-- stack_level = 1 >> Start at the function calling debugger.getStack

debugger.varDisplay(...)
-- Will display all given variables dynamically where FPS, Lua RAM etc. are displayed.
-- This call is not additive and will override any previous calls!
-- Takes any amount of arguments, formatted as such:
-- { "string to format given the result %s", function() return "or whatever" end }

debugger.aliasCommand(name, alias)
-- Allows you to access the command of 'name' also as 'alias'. You cannot add variants to
-- existing commands via the alias's title, create an alias with the name of another alias
-- or command or create a new command with the name of an alias.

debugger.errhand(error_message, stack_level)
-- Override love.errhand with this function to use the debugger when the game crashes.
-- It will write the traceback and entire stack (via debugger.getStack) to the global variables
-- _stackTraceback and _stackLocals respectively.
-- It is very likely to fail if the initial error was a stack overflow, though!
-- If you want to use this within another error handler, please supply the stack_level in such
-- a way that the traceback starts at the correct point.
```

There's also a few constants that you may modify as well:

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

debugger.useTitleBar = true
-- Whether or not to print FPS, Lua Ram Usage and update time to the window title bar.
-- If false, will always display it in the upper-right corner of the window instead.

debugger.replaceTabs = "    "
-- Replace tab character in prints with the specified characters.
-- Set to false to disable.

debugger.color = {...}
-- A list of several colors used by the debugger, most notably:
-- fgActive, fgActive2, bgActive,
-- fgNotActive, bgNotActive
```

---

## Other Things

* The environment location at the top may glitch out and not tell you an entirely correct path if unexpected key names are used.
* It always uses 'debug.getmetatable' rather than 'getmetatable'. Therefore it can access metatables even if those have a '\_\_metatable' key.
* The variable 'getmetatable' is overriden by 'debug.getmetatable' within the Lua prompt.
* This tool monkey-patches Lua's 'print' (but not 'io.write') function. The original function is stored as 'debugger.realPrint'.
* It will attempt to require "debugger_font", which it expects to return a Font to use, on load. If it finds such a file, and it does not return a Font, it may crash.

---

Copyright © 2017 Darius "DPlay" K.<br>
This work is free. You can redistribute it and/or modify it under the<br>
terms of the Do What The Fuck You Want To Public License, Version 2,<br>
as published by Sam Hocevar. See the COPYING file for more details.
