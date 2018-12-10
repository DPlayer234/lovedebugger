# LöveDebugger

(Not so) simple debugging tool for [Löve](https://www.love2d.org/), currently for Löve version 11.0 or newer (for older version, please check older releases).

Download/Clone the repository and include the 'debugger' folder in your Lua path or game directory (I suggest against leaving debug code in releases).

---

### Usage

Simply requiring and calling the module once after setting up at least *love.update*, *love.draw* should suffice for most cases.

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
	debugger.registerHandlers()
	-- This will monkey-patch relevant love.handlers.
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

Changing your callbacks after this is possible. *Keep in mind that modifying or changing the metatable of the table storing callbacks (by default 'love') will break things.* You aren't allowed to change love.update and love.draw (or the update and draw function in your table) after the automatic setup.

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
debugger.newCommand(name, arg_pattern, [help_text], func)
-- The argument pattern is a string. Every character represents an argument.
-- 's' means a string is expected, 'n' a number and 'b' a boolean.
-- There can be multiple commands with the same name and different arguments.
-- Commands added earlier are always prioritized.
-- If the passed function returns anything, this will printed to the screen in debugger.colors.printLog.

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

Then there's also a few additional debugger functions you may access if required.

```lua
debugger.setFont(font)
-- Sets a new font to be used by the console and such

local font = debugger.getFont()
-- Returns the currently used font

debugger.allPrint(...)
-- Prints text everywhere (the same as print after requiring the module)

debugger.printColor(colorTable, ...)
-- Prints text everywhere and with a certain color to debugger's console.

debugger.print(colorTable, ...)
-- Print exclusively to the debugger's console in the defined color

debugger.lua_print(...)
-- Regular Lua print function

debugger.clear()
-- Clears the console

debugger.tempClear()
-- Only clear the temporary console

local typeString = debugger.typeReal(value)
-- Returns the "real" user type of the value
-- This function is also used internally in the environment display and some other things.
-- It tries to get a value in the key 'type' of the value. Either returns that if it is
-- a string or (p)calls it with the value as the only argument and takes its return value.

debugger.setActive(active)
-- Sets whether or not the Lua prompt is active

local active = debugger.isActive()
-- Returns whether the Lua prompt is active

local id = debugger.addUpdate(func, [priority])
-- Adds a function to be called every frame. The function is passed dt.
-- The ID can be passed to debugger.removeUpdate(id) to remove the function once again.

debugger.removeUpdate(id)
-- Removes a function by ID from being called every frame.

local env, envName = debugger.getEnv()
-- Returns the current environment root. Defaults to _G, "env".

debugger.setEnv(env, [envName])
-- Replaces the root environment used by the debugger and the Lua prompt.
-- envName is the display name of the environment.

debugger.navigate(action, [arg])
-- Navigates the environment display once relative to the current state.
-- action:
--     'key': Navigate to the key as specified by arg.
--     'meta': Navigate to the meta table.
--     'parent': Navigate to the parent object.

debugger.navigateTo(envPath)
-- Navigates to a specified path.
-- This is limited to paths defined with period indexing, not brackets or function calls.

debugger.getEnvPath()
-- Returns a string, representing the current environment path.

debugger.getNiceEnvPath()
-- Returns a string, containing a nice representation of the current environment path.

debugger.loadString(code)
-- Loads code with the environment set to debugger.getEnv().

debugger.allowFunctionIndex([nicer_name])
-- Enables function indexing, allowing you to browse the upvalues
-- of functions by Shift-Left-Clicking them in the environment.
-- The optional argument is whether or not to also give functions
-- better 'tostring' values (more easily readable/descriptive),
-- like 'function: lib.func (lib.lua:4)' at the cost of some speed.
-- If you want to give functions a specific name, define them like this:
function myFunc()--[[my function name]] ... end
myFunc2 = function()--[[my function name #2]] ... end
-- Make sure not to put any spaces between the brackets and the comment
-- and also to make sure it's a block comment on a single line.
-- Additionally, enabled function indexing allows you to index functions
-- with the these special keys:
-- debugger.FUNCTION_CODE: Function code
-- debugger.FUNCTION_UPVALUES: A table containing all upvalues.

debugger.disallowFunctionIndex()
-- Disables function indexing.

local allowed = debugger.isFunctionIndexAllowed()
-- Returns whether function indexing is allowed.

debugger.monitorGlobal([options])
-- Enables monitoring the global environment for unusual changes or activities
-- (by which I mean, new definitions, accessing unused variables etc.).
-- This writes a log file to "ENV.txt"
-- options is a table, keys being the names of global variables and the values
-- being either DBG.MONITOR_UNDEFINED, DBG.MONITOR_CONSTANT or DBG.MONITOR_DYNAMIC
-- to define what a variable is. DBG.MONITOR_CONSTANT may be assigned to once,
-- DBG.MONITOR_DYNAMIC can be both accessed and assigned as often as wanted and
-- DBG.MONITOR_UNDEFINED may neither be accessed or assigned.
-- DBG.MONITOR_CONSTANT is implicitly set for all current global variables and
-- DBG.MONITOR_UNDEFINED is implicitly set for all not set values.

debugger.stopMonitorGlobal()
-- Stops monitoring the global environment.

debugger.viewLocals(source, inLine, [var, key])
-- Used debug.sethook to write the locals given to a table.
-- 'source' has to be either a relative file-name or a function in the same file.
-- 'inLine' is the line number, at which to pick out the variables from.
-- 'var' and 'key' are optional: If neither is defined, it will write the table to the global
-- variable _local. If only 'var' is defined, it will write it to a global variable of
-- the same name. If both are defined, 'var' is expected to be a table and 'key' is the key in that
-- table it will write to.
-- Calling it without any arguments will reset it. Calling it while running will override the
-- existing routine.

local stack = debugger.getStack([thread], stack_level)
-- Returns a table containing with each level of the current stack as its own table.
-- Each of the stack-tables contains all local variables at that point as well as all a
-- reference to the running function and whatever debug.getinfo gives out as a name.
-- stack_level is the stack level to start looking at.
-- stack_level = 1 >> Start at the function calling debugger.getStack
-- If you supply a thread (coroutine) first, it will instead get the information of that.

debugger.varDisplay(...)
-- Will display all given variables dynamically where FPS, Lua RAM etc. are displayed.
-- This call is not additive and will override any previous calls!
-- Takes any amount of arguments, formatted as such:
-- { "string to format given the result %s", function() return "or whatever" end }

debugger.aliasCommand(name, alias)
-- Allows you to access the command of 'name' also as 'alias'. You cannot add variants to
-- existing commands via the alias's title, create an alias with the name of another alias
-- or command or create a new command with the name of an alias.

debugger.addSource([func])
-- Adds the source file of a function or the source file this was called in to the debugger
-- whitelist. Any functions defined within this whitelist may index functions (if enabled)
-- and will not trigger the global variable monitor (also, if enabled).

debugger.errorhandler(error_message, [stack_level])
-- Override love.errorhandler with this function to use the debugger when the game crashes.
-- It will write the traceback and entire stack (via debugger.getStack) to the global variables
-- _stackTraceback and _stackLocals respectively.
-- It is very likely to fail if the initial error was a stack overflow, though!
-- If you want to use this within another error handler, please supply the stack_level in such
-- a way that the traceback starts at the correct point.
-- Can also be used as a pseudo-breakpoint by calling in within your code.
-- To continue, try to close the application in that case.

debugger.executeLuaCode(luaCode)
-- Executes Lua Code as if it was run from the console.

debugger.executeCommand(command)
-- Executes a command as if it was run from the console.

debugger.hideFields(var, pattern)
-- Hides fields whose name matches a certain pattern in a table.
-- Does not work for the upvalues of functions.

local down = debugger.isDown(inputId)
-- Returns whether a given input is held.
```

There's also a few constants that you may modify as well:

```lua
debugger.activate    = "f4"
-- Löve KeyConstant of the key used to open the console.

debugger.clearPrompt = "f5"
-- Löve KeyConstant of the key used to clear the Lua prompt
-- and toggle 'debugger.doTempPrint'.

debugger.textFade    = 7
-- Time it takes for text to fade away after its 'print'
-- call in seconds while the Lua prompt is closed.

debugger.printWidth   = 2/3
-- Screen Area where the prints are displayed (ratio 0.0-1.0).

debugger.maxStorage  = 100
-- How many console inputs are stored to be reused
-- (by using 'Up' and 'Down' arrow keys).

debugger.doTempPrint = true
-- Whether or not to print to the screen if the console is closed.

debugger.useTitleBar = true
-- Whether or not to print FPS, Lua Ram Usage and update time to the window title bar.
-- If false, will always display it in the upper-right corner of the window instead.

debugger.replaceTabs = 8
-- Replace tab character in prints with the specified amount of spaces.
-- Set to false to disable.

debugger.colors = {...}
-- A list of several colors used by the debugger, most notably:
-- fgActive, fgActive2, bgActive,
-- fgNotActive, bgNotActive
```

---

## profile.lua

This debugger also supports using [profile.lua](https://bitbucket.org/itraykov/profile.lua/src/):

```lua
-- Require profile.lua and pass it as the only argument to this function
debugger.setProfiler(require "profile")

-- Keep in mind that this may only give a vague error if the profiler is not supported.

-- Optionally, you may add a second argument defining the file in which to store the reports
debugger.setProfiler(require "profile", "my_file.txt")
```

Once set, you can use it relatively easily:

```lua
debugger.startProfiler()
-- Starts the profiler

debugger.stopProfiler()
-- Stops it

debugger.setProfilerInterval(frames)
-- How often the profiler should save a report and reset
-- The default interval is 100.

debugger.setProfilerReportArgs(sort, rows)
-- What arguments are passed to profile.report(sort, rows)
-- The defaults are "time" and 20.
```

Or use these commands to control it instead:

```
/pstart
/pstop
/pinterval <frames>
/preport [sort] [rows]
```

The reports are saved to the file 'profiler.txt' or whatever is given as the second argument to debugger.setProfiler.

If you want the profiler's reports to use the function name returned by tostring after calling debugger.allowFunctionIndex(true), make sure to do the latter first.

---

## Other Things

* The environment location at the top may glitch out and not tell you an entirely correct path if unexpected key names are used.
* This tool monkey-patches Lua's 'print' (but not 'io.write') function. The original function is stored as 'debugger.lua_print'.
* It will attempt to require "(require-path).font", which it expects to return a Font to use, on load. If it finds such a file, and it does not return a Font, it may crash.

---

Copyright © 2017-2018 Darius "DPlay" K.<br>
This work is free. You can redistribute it and/or modify it under the<br>
terms of the Do What The Fuck You Want To Public License, Version 2,<br>
as published by Sam Hocevar. See the COPYING file for more details.
