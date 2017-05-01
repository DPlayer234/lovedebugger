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
	SL = Navigate to a function's upvalues (requires calling debugger.allowFunctionIndex() beforehand, see below)
	SR = Navigate to metatable, if defined
```

You can also use the arrow keys (up and down) to bring back previous inputs to the Lua prompt.

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
debugger.setFont(font) -- Sets a new font to be used by the console and such
debugger.getFont() -- Returns the currently used font

debugger.print(colorTable, ...) -- Print exclusively to the debugger's console in the defined color
debugger.realPrint(...) -- Actual Lua print function
debugger.clear() -- Clears the console

debugger.setActive(active) -- Sets whether or not the Lua prompt is active
debugger.isActive() -- Returns whether the Lua prompt is active

debugger.allowFunctionIndex(desc)
-- Enables function indexing, allowing you to browse the upvalues of functions by Shift-Left-Clicking them in the environment.
-- The optional argument is whether or not to also give functions better 'tostring' values (more easily readable/descriptive).

debugger.monitorGlobal(writeTo)
-- Enables monitoring the global environment for unusual changes or activities (by which I mean, new definitions, accessing unused variables etc.).
-- 'writeto' is the file path (within the Löve save directory) to write the output to. Defaults to '_G (log).txt'.
```

---

Licensed under the WTFPL License:
```
DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
          Version 2, December 2004

Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>

Everyone is permitted to copy and distribute verbatim or modified
copies of this license document, and changing it is allowed as long
as the name is changed.

         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

0. You just DO WHAT THE FUCK YOU WANT TO.
```
