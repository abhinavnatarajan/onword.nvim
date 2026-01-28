# AGENTS.md

## Build, Lint, and Test

This project is a Neovim plugin written in Lua.

### Build
- There is no compile step; Lua files are sourced directly by Neovim.
- Ensure `lua/` is in the Neovim runtime path.

### Linting
- Currently, there is no strict linter configuration (e.g., `.luacheckrc`).
- **Recommendation:** Use `luacheck` for static analysis.
- **Command:** `luacheck lua/`
- **Globals:** Must respect the `vim` global.

### Formatting
- **Style:** Tabs for indentation.
- **Tool:** `stylua` is recommended.
- **Command:** `stylua lua/`

### Testing
- **Status:** No test suite is currently implemented in this repository.
- **Future Convention:** 
  - Tests should be placed in `tests/` or `spec/`.
  - The `plenary.nvim` test harness is the standard for Neovim plugins.
  - Run command would typically be: `nvim --headless -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" -c "cquit"`

## Code Style Guidelines

### General
- **Language:** Lua 5.1 / LuaJIT (Neovim compatible).
- **Module Pattern:** Return a table `M` at the end of the file.
  ```lua
  local M = {}
  -- implementation
  return M
  ```

### Formatting Rules
- **Indentation:** **Use Tabs**. Do not use spaces for indentation.
- **Line Endings:** Unix (LF).
- **Line Length:** Soft limit of 100-120 characters.
- **Strings:** Double quotes `"` are generally preferred over single quotes `'`, but consistency within the file is key.
- **Blocks:** Use `do ... end` blocks sparingly, mostly for scope control.

### Naming Conventions
- **Local Variables:** `snake_case` (e.g., `line_len`, `char_pos`).
- **Functions:** `snake_case` (e.g., `get_next_position`).
- **Module Functions:** `M.function_name`.
- **Types/Classes:** `camelCase` is observed in annotations (e.g., `motionOpts`).
- **Constants:** `UPPER_SNAKE_CASE` (standard convention).

### Imports and Dependencies
- **Safety:** Use `pcall` when `require`-ing optional dependencies.
  ```lua
  local ok, lib = pcall(require, 'dependency')
  if not ok then
      -- fallback implementation
  end
  ```
- **Standard Library:** Prefer `vim.*` utility functions (e.g., `vim.iter`, `vim.tbl_deep_extend`) over implementing custom helpers when possible.
- **String Handling:** Handle UTF-8 correctly. Prefer `lua-utf8` if available, falling back to `string` (standard Lua) methods carefully.

### Type Checking & Documentation
- **EmmyLua:** Use EmmyLua annotations for all functions.
- **Parameters:** Document all parameters with `---@param`.
- **Returns:** Document return values with `---@return`.
- **Types:** Define complex table structures using `---@class`.
  ```lua
  ---@class (exact) motionOpts
  ---@field count integer|nil
  ---@field multi_line boolean
  local default_opts = {}
  ```

### Error Handling
- **User-Facing:** Use `vim.notify` for errors that the user needs to see.
  ```lua
  vim.notify("Error message", vim.log.levels.ERROR, { title = "PluginName" })
  ```
- **Internal:** Return `nil` to signal failure in low-level functions (e.g., `get_next_position` returns `number|nil`).
- **Guards:** Validate inputs early (e.g., check valid motion keys).

### Neovim Specifics
- **API:** Use `vim.api.nvim_*` for editor interactions.
- **Cursor:** `vim.api.nvim_win_get_cursor(0)` returns `(1,0)`-indexed positions.
- **Lines:** `vim.api.nvim_buf_get_lines` is 0-indexed.
- **Keymaps:**
  - Use `<Plug>` mappings for internal functionality exposed to users.
  - Use `vim.keymap.set` for creating mappings.
  - Define `expr = true` mappings for operator-pending or insert mode actions that return keys to be executed.

## Architecture & Patterns
- **Functional Iteration:** Use `vim.iter` for map/fold operations on lists.
- **Defaults:** Use `vim.tbl_deep_extend("force", defaults, opts)` for merging user configuration.
- **Modes:** Handle different modes (`n`, `x`, `o`) explicitly where necessary.
- **Efficiency:** Cache repeatedly used functions (e.g., `local find, sub = string.find, string.sub`).

## Existing Rules
- No `.cursorrules` or Copilot instructions found in the repository.

## Future Work: `aw` Implementation

### Context
We have implemented the `iw` (inner word) text object in `lua/onword.lua`. It correctly selects:
1.  The word itself if the cursor is on a word.
2.  The whitespace block if the cursor is on whitespace (leading or trailing).

The `aw` (around word) text object is currently a stub that falls back to `iw` behavior.

### Implementation Sketch
The `aw` logic needs to be implemented in `M.text_objects.word`.

**Algorithm Idea:**
1.  Get the `iw` range using `get_inner_word_range(cursor_pos)`.
2.  Check if the `iw` range covers a word (i.e., not just whitespace).
    *   *Helper:* `getline(row):sub(start_col+1, end_col+1):match("^%s+$")`
3.  If it is a word:
    *   **Priority 1:** Check for trailing whitespace. Extend `end_pos` to include it.
    *   **Priority 2:** If no trailing whitespace exists, check for leading whitespace. Extend `start_pos` to include it.
4.  If it is already whitespace (from `iw`):
    *   Decide on behavior. Standard Vim usually selects the whitespace plus the following word? Or just the whitespace? *Needs specification.*

### Verification
- Use `tests/repro_textobjects.lua`.
- **New Test Cases Required:**
  - `aw` on word with trailing whitespace `foo |bar  baz` -> selects `bar  `
  - `aw` on word with leading whitespace only `  |foo` -> selects `  foo`
  - `aw` on word surrounded by nothing `|foo` -> selects `foo`
  - `aw` on whitespace `foo|   bar` -> ?
