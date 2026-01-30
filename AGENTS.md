# Agent Instructions for onword.nvim

This document contains instructions for AI agents (and humans) working on the `onword.nvim` repository.

## 1. Build, Lint, and Test

This project is a Neovim plugin written in Lua. It does not use a standard test runner like `busted` or `plenary`. Instead, it uses a standalone Lua script for testing.

### Running Tests
To run the test suite, execute the test file using Neovim's headless mode:

```bash
nvim -l tests/textobjects.lua
```

**Note:** The test script `tests/textobjects.lua` currently runs all tests defined in the `tests` table. To run a single test, you would currently need to temporarily comment out other tests in the `tests` table within that file.

### Linting
There are no strict linting configurations (like `.luacheckrc`) present. However, standard Lua guidelines apply.
- Ensure no global variables are leaked.
- Unused variables should be removed or prefixed with `_`.

## 2. Code Style Guidelines

Adhere strictly to the following conventions to maintain consistency with the existing codebase.

### General
- **Indentation:** Use **Tabs**, not spaces.
- **Quotes:** Use **double quotes** `"` for strings (e.g., `require("onword.motions")`), unless the string contains double quotes.
- **Line Length:** Aim for readable line lengths, generally under 100 characters.

### Naming Conventions
- **Variables & Functions:** Use `snake_case` (e.g., `local start_pos`, `function get_inner_word_range`).
- **Modules:** Use the standard `M` pattern:
  ```lua
  local M = {}
  -- ... functions ...
  return M
  ```
- **Private Functions:** Define helper functions as `local` before the module definition or at the top of the file.

### Type Definitions
Use LuaCATS annotations (Doxygen-style) for function parameters and return values, especially for public API methods.

```lua
---@param key "iw"|"aw" inner or around
---@param mode vimMode
function M.word(key, mode)
```

### Error Handling
- Use `pcall` or `xpcall` if a function might fail and crash Neovim.
- For user-facing errors, use `vim.notify`:
  ```lua
  vim.notify("Error message", vim.log.levels.ERROR, { title = "TextObject" })
  ```

### File Structure
- **Imports:** Group `require` calls at the top of the file.
- **Module Setup:** If the module has a setup function, define it as `function M.setup()`.
- **Lazy Loading:** For performance, heavy requires can be moved inside the functions that use them, though top-level requires are standard for core logic.

### Modifying Code
- **Context:** Always read the surrounding code to match the exact style (e.g., spacing around operators, table formatting).
- **Comments:** Add comments for complex logic (like the `get_inner_word_range` algorithm). Do not over-comment obvious code.

## 3. Cursor/Copilot Rules

*No specific `.cursorrules` or Copilot instructions were found in the repository.*

## 4. Project Structure
- `lua/onword/`: Core plugin code.
  - `init.lua`: Plugin entry point and setup.
  - `motions.lua`: Motion logic.
  - `textobjects.lua`: Text object definitions and algorithms.
  - `utils.lua`: Utility functions (length, byte conversions).
- `tests/`: Test files.
  - `textobjects.lua`: Standalone test runner.

When creating new files, ensure they are placed in the appropriate subdirectory under `lua/onword/`.
