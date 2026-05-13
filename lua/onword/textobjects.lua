local M = {}

local motions = require("onword.motions")
local next_subword, next_subword_end, prev_subword, prev_subword_end =
	motions.builtin.next_subword,
	motions.builtin.next_subword_end,
	motions.builtin.prev_subword,
	motions.builtin.prev_subword_end
local compute_motion = motions.compute_motion
local utils = require("onword.utils")

local len, char_pos_to_byte_idx, byte_idx_to_char_pos, getline =
	utils.len,
	utils.char_pos_to_byte_idx,
	utils.byte_idx_to_char_pos,
	utils.getline

---@alias vimMode
---| '"no"' # operator pending
---| '"nov"' # operator pending, forced charwise
---| '"noV"' # operator pending, forced linewise
---| '"no<C-v>"' # operator pending, forced blockwise
---| '"v"' # visual charwise
---| '"vs"' # visual charwise using Ctrl-o in select mode
---| '"V"' # visual linewise
---| '"Vs"' # visual linewise using Ctrl-o in select mode
---| '"<C-v>"' # visual blockwise
---| '"<C-v>s"' # visual blockwise using Ctrl-o in select mode
---| '"s"' # select mode charwise
---| '"S"' # select mode linewise
---| '"<C-s>"' # select mode blockwise

local function cancel_visual_mode()
	local mode = vim.api.nvim_get_mode().mode:sub(1)
	if vim.tbl_contains({ "v", "V", "", }, mode) then
		-- exit visual mode first
		vim.cmd("exe \"normal! \\<Esc>\"")
	end
end
function M.inner_line()
	cancel_visual_mode()
	vim.cmd("normal! ^vg_")
end

function M.around_line()
	cancel_visual_mode()
	local pos = vim.api.nvim_win_get_cursor(0)
	local line_len = string.len(getline(pos[1]))
	vim.cmd("normal! 0v")
	vim.api.nvim_win_set_cursor(0, { pos[1], math.max(line_len - 1, 0) })
end

---@return table<integer, integer>|nil start_pos (1,0)-indexed
---@return table<integer, integer>|nil end_pos (1,0)-indexed
local function get_inner_word_range(init_pos)
	-- Algorithm for Inner Word (iw) text object:
	-- The goal is to select the current word (if on one) or the surrounding whitespace block.
	-- Since `iw` is single-line only, we disable multi-line motions.
	--
	-- We identify three main scenarios based on cursor position relative to word boundaries:
	--
	-- 1. Cursor is ON a word:
	--    - `e` finds the end of this word.
	--    - `b` from that end finds the start.
	--    - Result: [start_b, end_e]
	--
	-- 2. Cursor is on TRAILING whitespace (no word follows on this line):
	--    - `e` returns a past-the-end sentinel (line length).
	--    - We find the start of this whitespace block using `ge` (end of previous word).
	--    - If `ge` hits start-of-line sentinel (-1), the whole line is whitespace.
	--    - Result: [ge_end + 1 (or 0), line_len]
	--
	-- 3. Cursor is on LEADING whitespace (before a word):
	--    - `e` finds the end of the *next* word.
	--    - `b` from that end finds the start of the *next* word.
	--    - Since cursor < start_b, we are in the whitespace before it.
	--    - We find the start of this whitespace block using `ge`.
	--    - Result: [ge_end + 1 (or 0), start_b - 1]

	local line = getline(init_pos[1])
	local line_len = len(line)
	if line_len == 0 then
		return nil, nil
	end

	local opts = { must_move = false, multi_line = false }
	local e_pos = compute_motion(vim.tbl_extend("force", next_subword_end, opts), init_pos)
	local start_pos, end_pos

	-- Check for "past end of line" (Case 2: Trailing whitespace)
	local line_bytes = string.len(line)

	if e_pos[2] >= line_bytes then
		-- Case 2: Trailing Whitespace
		end_pos = { init_pos[1], line_bytes - 1 }
		local ge_pos = compute_motion(vim.tbl_extend("force", prev_subword_end, opts), init_pos)

		if ge_pos[2] == -1 then
			-- Sentinel case: start of line (and line starts with whitespace)
			start_pos = { init_pos[1], 0 }
		else
			-- Start is one char after ge_pos
			-- Convert ge_pos[2] (0-based byte) to 1-based char pos
			local char_pos = byte_idx_to_char_pos(line, ge_pos[2] + 1)
			-- Increment char pos
			char_pos = char_pos + 1
			-- Convert back to 0-based byte idx
			local start_byte = char_pos_to_byte_idx(line, char_pos) - 1
			start_pos = { init_pos[1], start_byte }
		end
	else
		-- Case 1 or 3
		local b_pos = compute_motion(vim.tbl_extend("force", prev_subword, opts), e_pos)

		if init_pos[2] >= b_pos[2] then
			-- Case 1: Inside Word
			start_pos = b_pos
			end_pos = e_pos
			-- Need to add the byte width of the last character to end_pos
			local eline = getline(e_pos[1])
			if #eline ~= 0 then
				local e_char_pos = byte_idx_to_char_pos(eline, math.min(e_pos[2] + 1, #eline))
				local _, e_char_last_byte = char_pos_to_byte_idx(eline, e_char_pos)
				end_pos = { e_pos[1], e_char_last_byte - 1 }
			end
		else
			-- Case 3: Leading Whitespace
			-- End is one char before b_pos,
			-- we return its last byte position
			end_pos = { init_pos[1], b_pos[2] - 1 }

			local ge_pos = compute_motion(vim.tbl_extend("force", prev_subword_end, opts), init_pos)
			if ge_pos[2] == -1 then
				start_pos = { init_pos[1], 0 }
			else
				local start_char_pos = byte_idx_to_char_pos(line, ge_pos[2] + 1)
				start_char_pos = start_char_pos + 1
				local start_byte = char_pos_to_byte_idx(line, start_char_pos) - 1
				start_pos = { init_pos[1], start_byte }
			end
		end
	end
	return start_pos, end_pos
end

---@return table<integer, integer>|nil start_pos (1,0)-indexed
---@return table<integer, integer>|nil end_pos (1,0)-indexed
local function get_around_word_range(init_pos)
	-- Algorithm for Around Word (aw) text object:
	-- The goal is to select the current word (if on one) plus the surrounding whitespace block.
	-- The surrounding block of whitespace may be before or after the word,
	-- depending on the cursor position.
	-- The whitespace block should not extend to adjacent lines, unless the current word
	-- is itself on a subsequent line. In that case, we include only the whitespace on the lines
	-- between the current line (inclusive) and the line with the word, and no whitespace
	-- on any previous lines.
	--
	-- Pseudocode:
	-- -- Find the end of the current word with e_pos, then find the start with b_pos.
	-- let e_pos = compute_motion("e", init_pos, { multi_line = true, must_move = false })
	-- let b_pos = compute_motion("b", e_pos, { multi_line = true, must_move = false })
	-- if cursor_pos >= b_pos:
	--   -- Cursor is ON a word.
	--   start_pos = b_pos
	--   -- Find the subsequent whitespace block after the word.
	--   w_pos = compute_motion("w", init_pos, { multi_line = false, must_move = true })
	--   if w_pos is end of the line sentinel (line_len + 1):
	--     -- there is trailing whitespace only
	--     end_pos = line_len - 1
	--   else:
	--     end_pos = w_pos - 1
	--   endif
	-- else:
	--    -- Cursor is in whitespace BEFORE the word.
	--    end_pos = e_pos
	--    -- Find the start of the current whitespace block.
	--    ge_pos = compute_motion("ge", init_pos, { multi_line = false, must_move = false })
	--    -- If `ge` hits start-of-line sentinel (-1), the whole line is whitespace.
	--    if ge_pos == -1:
	--      start_pos = beginning of current_line
	--    else:
	--      start_pos = ge_pos + 1
	--    endif
	-- endif
	-- return [start_pos, end_pos]
	local line = getline(init_pos[1])
	local line_len = len(line)
	if line_len == 0 then
		return nil, nil
	end

	local start_pos, end_pos
	local e_pos = compute_motion(vim.tbl_extend(
		"force", next_subword_end, {
			multi_line = true,
			must_move = false,
			stop_at_empty_line = true,
		}
	), init_pos)
	local b_pos = compute_motion(vim.tbl_extend(
		"force", prev_subword, {
			multi_line = false,
			must_move = false,
		}), e_pos)
	if init_pos[1] > b_pos[1] or init_pos[1] == b_pos[1] and init_pos[2] >= b_pos[2] then
		start_pos = b_pos
		local w_pos = compute_motion(vim.tbl_extend(
			"force",
			next_subword,
			{ multi_line = false, must_move = true }
		), init_pos)
		end_pos = { w_pos[1], w_pos[2] - 1 }
	else
		end_pos = e_pos
		-- Check if e_pos is on an empty line
		local eline = getline(e_pos[1])
		if #eline ~= 0 then
			local e_char_pos = byte_idx_to_char_pos(eline, math.min(e_pos[2] + 1, #eline))
			local _, e_char_last_byte = char_pos_to_byte_idx(eline, e_char_pos)
			end_pos = { e_pos[1], e_char_last_byte - 1 }
		end

		local ge_pos = compute_motion(vim.tbl_extend(
			"force",
			prev_subword_end,
			{ must_move = false, multi_line = false }
		), init_pos)
		if ge_pos[2] == -1 then
			start_pos = { init_pos[1], 0 }
		else
			local start_char_pos = byte_idx_to_char_pos(line, ge_pos[2] + 1)
			start_char_pos = start_char_pos + 1
			local start_byte = char_pos_to_byte_idx(line, start_char_pos) - 1
			start_pos = { init_pos[1], start_byte }
		end
	end
	return start_pos, end_pos
end

-- ---@param key "iw"|"aw" inner or around
-- ---@param mode vimMode
-- function M.word(key, mode)
-- 	if key ~= "iw" and key ~= "aw" then
-- 		-- TODO: title of the error message
-- 		vim.notify(
-- 			"Invalid key: " .. key .. "\nOnly iw and aw are supported .",
-- 			vim.log.levels.ERROR,
-- 			{ title = "TextObject" }
-- 		)
-- 		return
-- 	end
--
-- 	local cursor_pos = vim.api.nvim_win_get_cursor(0)
-- 	local start_pos, end_pos
--
-- 	-- TODO: logic for 'aw'
-- 	start_pos, end_pos = get_inner_word_range(cursor_pos)
--
-- 	if not start_pos or not end_pos then
-- 		return ""
-- 	end
--
-- 	-- build up the expression to execute
-- 	local operation
-- 	local inclusive = (key == "iw") or mode == "nov"
-- 	if mode:sub(1, 2) == "no" then
-- 		operation = vim.v.operator .. (inclusive and "v" or "")
-- 	else
-- 		-- visual mode
-- 		-- TODO: handle different visual modes properly
-- 		-- see documentation for vim.fn.mode()
-- 		operation = mode
-- 		-- if not inclusive then
-- 		-- 	endPos[2] = endPos[2] - 1
-- 		-- end
-- 	end
-- 	local str = "<Esc><Cmd>lua vim.api.nvim_win_set_cursor(0, {" .. start_pos[1] .. ", " .. start_pos[2] .. "})<CR>"
-- 		.. "\"" .. vim.v.register
-- 		.. operation
-- 		.. "<Cmd>lua vim.api.nvim_win_set_cursor(0, {" .. end_pos[1] .. ", " .. end_pos[2] .. "})<CR>"
-- 	return str
-- end

---@param get_range function(integer[2]): (integer[2]|nil, integer[2]|nil)
function M.word(get_range)
	cancel_visual_mode()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local start_pos, end_pos
	start_pos, end_pos = get_range(cursor_pos)
	if not start_pos or not end_pos then
		return ""
	end
	vim.api.nvim_win_set_cursor(0, start_pos)
	vim.cmd("normal! v")
	vim.api.nvim_win_set_cursor(0, end_pos)
end

function M.inner_word()
	M.word(get_inner_word_range)
end

function M.around_word()
	M.word(get_around_word_range)
end

return M
