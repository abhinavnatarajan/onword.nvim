# onword.nvim

A Neovim plugin that provides smarter sub-word text objects.

## Features

- **Smarter motions (`w`, `b`, `e`, `ge`)**: Navigate by sub-word, intelligently handling whitespace, kebab-case, camelCase, and snake_case.
- **Inner Word (`iw`) and around word (`aw`)**: Text objects that respect sub-word boundaries, and are consistent with Vim's behaviour in regard to how non-word characters are selected.
- **UTF-8 Support**: Correctly handles UTF-8 characters for word boundaries (requires `luautf8` to be installed).
- **Customizable Behaviour**: Control whether motions are multi-line, inclusive/exclusive, and more.

## Dependencies

This plugin supports proper UTF-8 handling for word boundaries. This functionality depends on the `luautf8` library being available to the Lua interpreter.

The easiest way to ensure `luautf8` is available is by installing it via `luarocks` (`luarocks install luautf8`) and adding the luarocks module directories to your `package.path` and `package.cpath`.

Add the following to your Neovim configuration (e.g., `init.lua`):

```lua
if vim.fn.executable("luarocks") then
	-- add luarocks modules
	local process = vim.system({ 'luarocks', 'config', 'deploy_lua_dir' }, { text = true }):wait()
	local exit_code, stdout = process.code, process.stdout:gsub("\n", "")
	if exit_code == 0 then
		package.path = package.path .. ';' .. stdout .. '/?/init.lua'
		package.path = package.path .. ';' .. stdout .. '/?.lua'
	end
	-- add luarocks binary libraries
	local process = vim.system({ 'luarocks', 'config', 'deploy_lib_dir' }, { text = true }):wait()
	local exit_code, stdout = process.code, process.stdout:gsub("\n", "")
	if exit_code == 0 then
		-- Determine OS extension
		local extension = jit.os:find("Windows") and ".dll" or jit.os == "OSX" and ".dylib" or ".so"
		package.cpath = package.cpath .. ';' .. stdout .. '/?' .. extension
	end
end
```
