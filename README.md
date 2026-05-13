# onword.nvim

A Neovim plugin that provides motions and textobjects that intelligently handle sub-words and multibyte characters.

## Features

### Motions

- Move forwards or backwards to the nearest sub-word beginning or sub-word ending.
	Sub-word beginnings and endings are defined by patterns that handle whitespace snake_case, kebab-case, and camelCase.
- Correctly handles UTF-8 characters for word boundaries (requires `luautf8` to be installed).
- Implement custom motions by specifying a string pattern to search for and a direction ("forward" or "backward").

### Textobjects

- **Inner Word (`iw`) and around word (`aw`)**: Text objects that respect sub-word boundaries (like the motions), and are consistent with Vim's behaviour in regard to how non-word characters are selected.
- **Inside line word (`il`)**: A text object that selects the entire line except leading and trailing whitespace.

## Installation

<details>
<summary>Using <code>lazy.nvim</code></summary>

```lua
return {
	"abhinavnatarajan/onword.nvim",
	-- This plugin does not need to be lazy-loaded, since it is lightweight.
	-- <Plug> mappings cannot be enabled until the plugin is loaded.
	lazy = false,
}
```

</details>

## Configuration

You do not need to call any setup function.
Simply set up key bindings to use the provided motion functions, and you're good to go!
<details>
<summary>Example configuration snippet</summary>

```lua
vim.keymap.set(
    {'n', 'v', 'o'}, 'w',
    function() require('onword').motions.next_subword() end,
    { desc = "onword: move to next sub-word" }
)
vim.keymap.set(
    {'n', 'v', 'o'}, 'e',
    function() require('onword').motions.next_subword_end() end,
    { desc = "onword: move to next sub-word end" }
)
vim.keymap.set(
    {'n', 'v', 'o'}, 'b',
    function() require('onword').motions.prev_subword() end,
    { desc = "onword: move to previous sub-word" }
)
vim.keymap.set(
    {'n', 'v', 'o'}, 'ge',
    function() require('onword').motions.prev_subword_end() end,
    { desc = "onword: move to previous sub-word end" }
)
```

</details>

The plugin also provides the following `<Plug>` mappings:
TODO: describe the mappings here.

## Usage

### Inbuilt motions

TODO: describe the motions here.
Each of motion functions (`next_subword()`, `next_subword_end()`, `prev_subword()`, `prev_subword_end()`) accepts an optional table argument to customize their behaviour.
The available options and their defaults are:

```lua
motion_opts = {
	multi_line = true, -- whether the motion can cross line boundaries
	must_move = true, -- whether the motion should move at least one character (useful for programmatic usage)
	stop_at_empty_line = true, -- whether the motion should stop at an empty line
	count = vim.v.count1 -- number of times to repeat the motion
}
```

### Custom motions based on lua patterns

You can also set up your own motions by providing a pattern and direction.
For example, to create a motion that moves to the next English vowel character:

```lua
local motion = {
	direction = "forward",
	multi_line = true,
	patterns = {
		{ "[aeiouAEIOU]", offset_from_start = 0, offset_from_end = 0 }
	}
}
vim.keymap.set(
	{'n', 'v', 'o'}, '<leader>v',
	function() require('onword').motions.run(motion) end,
	{ desc = "onword: move forward to next vowel" }
)
```

The `patterns` field can contain multiple patterns, and the nearest match in the specified direction will be used.
The offset parameters specify where to place the cursor within the matched pattern.
For example, to move forward to the first non-whitespace character that follows whitespace:

```lua
motion = {
	direction = "forward",
	multi_line = true,
	patterns = {
		{ "%s%S", offset_from_start = 1, offset_from_end = 0 }
	}
}
```

To move backward to the first non-whitespace character that precedes whitespace:
```lua
motion = {
	direction = "backward",
	multi_line = true,
	patterns = {
		{ "%S%s", offset_from_start = 0, offset_from_end = 1 }
	}
}
```

### Textobjects

TODO: describe the textobjects here.


## Dependencies

This plugin supports proper UTF-8 handling for word boundaries.
This functionality depends on the [`luautf8`](https://github.com/starwing/luautf8) library being available to the Lua interpreter.

The easiest way to ensure `luautf8` is available is by installing it via the [`luarocks`](https://luarocks.org/) package manager for Lua (`luarocks install --lua-version=5.1 luautf8`).
Ensure that the luarocks module directories are added into the `package.path` and `package.cpath` global variables in the Neovim Lua environment.
For example, you can add the following code snippet to your `init.lua` before loading any plugins:

```lua
if vim.fn.executable("luarocks") then
	local process = vim.system({ 'luarocks', 'config', 'deploy_lua_dir' }, { text = true }):wait()
	local exit_code, stdout = process.code, process.stdout:gsub("\n", "")
	if exit_code == 0 then
        -- Add luarocks modules.
        package.path = package.path .. ';' .. vim.fs.joinpath(stdout, '?.lua')
		package.path = package.path .. ';' .. vim.fs.joinpath(stdout, '?', 'init.lua')
	end
	process = vim.system({ 'luarocks', 'config', 'deploy_lib_dir' }, { text = true }):wait()
	exit_code, stdout = process.code, process.stdout:gsub("\n", "")
	if exit_code == 0 then
		-- Add luarocks binary libraries with appropriate extension.
		local extension = (jit.os:find('Windows') and '.dll')
			or (jit.os == 'OSX' and '.dylib')
			or (jit.os == 'Linux' and '.so')
		package.cpath = package.cpath .. ';' .. vim.fs.joinpath(stdout, '?' .. extension)
	end
end
```
