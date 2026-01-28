local M = {}

local ok, utf8 = pcall(require, 'lua-utf8')
local find, sub, len, byte_idx_to_char_pos, char_pos_to_byte_idx
if ok then
	find, sub, len, char_pos_to_byte_idx = utf8.find, utf8.sub, utf8.len, utf8.offset
	byte_idx_to_char_pos = function(str, byte_idx)
		local _, char_end_byte = utf8.offset(str, 0, math.min(byte_idx, string.len(str)))
		return utf8.len(str, 1, char_end_byte)
	end
else
	find, sub, len = string.find, string.sub, string.len
	char_pos_to_byte_idx = function(_, pos) return pos end
	byte_idx_to_char_pos = function(_, pos) return pos end
end

---Returns the content of the given line number.
---@param lnum number 1-indexed
---@return string
local function getline(lnum)
	return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
end

---Returns the next character position in the line matching any of the given patterns.
---@param ln table<string, integer> the line to search and its length
---@param init_char_pos number the character position to start searching from
---@param pats table the patterns to search for
---@param must_move boolean|nil whether we must move at least one position
---@return number|nil result next character position found, or nil
local function get_next_position(ln, init_char_pos, pats, must_move)
	local line, line_len = ln[1], ln[2]
	must_move = must_move or true
	if must_move then
		if init_char_pos >= line_len then
			return nil
		elseif init_char_pos == 0 then
			--we have jumped here from the previous line
			must_move = false
			init_char_pos = 1
		end
	end
	local min_new_pos = init_char_pos + (must_move and 1 or 0)
	-- Find minimum position among all the patterns
	local result = vim.iter(pats):map(function(p)
		local pattern, pattern_offset = p.pattern, p.offset_from_start
		-- We want match_start + pattern_offset >= min_new_pos,
		-- so we need match_start >= min_new_pos - pattern_offset.
		local start_search = math.max(min_new_pos - pattern_offset, init_char_pos)
		-- If the pattern begins with ^, and we are not searching from the start of the line,
		-- return nil.
		if start_search > 1 and sub(pattern, 1, 1) == "^" then
			return nil
		end
		local match_start = find(line, pattern, start_search)
		local target_pos = match_start and match_start + pattern_offset or nil
		return target_pos
	end):fold(line_len + 1, function(cur_best_pos, target_pos)
		if target_pos < cur_best_pos then
			return target_pos
		else
			return cur_best_pos
		end
	end)
	return result <= line_len and result or nil
end

---find_prev_match searches a line backwards from the character position init_char_pos
---for a match to the provided pattern. If no match is found, it will return nil.
---@param line string the line to search
---@param init_char_pos number the position to start searching backward from
---@param pattern string the pattern to search for
---@return number|nil,number|nil # start and end positions of the match, or nil
local function find_prev_match(line, pattern, init_char_pos)
	if sub(pattern, 1, 1) ~= "^" then
		-- if the pattern does not begin the line,
		-- we search for the last match of the pattern
		-- this allows us to implement a crude 'rfind'
		pattern = ".*" .. pattern
	end
	return find(sub(line, 1, init_char_pos), pattern)
end

---Returns the previous character position in the line matching any of the given patterns.
---@param ln table<string, integer> the line to search and its length
---@param init_char_pos number the character position to start searching backwards from
---@param pats table the patterns to search for
---@param must_move boolean|nil whether we must move at least one position
---@return number|nil result previous character position found, or nil
local function get_prev_position(ln, init_char_pos, pats, must_move)
	local line, line_len = ln[1], ln[2]
	must_move = must_move or true
	if must_move then
		if init_char_pos <= 1 then
			-- already at beginning of line
			return nil
		elseif init_char_pos == line_len + 1 then
			must_move = false
			init_char_pos = line_len
		end
	end
	local max_new_pos = init_char_pos - (must_move and 1 or 0)
	local result = vim.iter(pats):map(function(p)
		local pattern, pattern_offset = p.pattern, p.offset_from_end
		-- We want match_end - pattern_offset <= max_new_pos,
		-- so we need match_end <= max_new_pos + pattern_offset.
		local end_search = math.min(init_char_pos, max_new_pos + pattern_offset)
		-- If the pattern is anchored at the end of the line with $,
		-- and we are not searching from the end of the line, return nil.
		if end_search < line_len
			and sub(pattern, len(pattern)) == "$"
			and sub(pattern, -2) ~= "%" then
			return nil
		end
		local _, match_end = find_prev_match(line, pattern, end_search)
		return match_end and match_end - pattern_offset or nil
	end):fold(0, function(cur_best_pos, target_pos)
		if target_pos > cur_best_pos then
			return target_pos
		else
			return cur_best_pos
		end
	end)
	return result > 0 and result or nil
end

local motion_keys = { "w", "e", "b", "ge" }
local forward_motion_keys = { "w", "e" }
local word_begin_motion_keys = { "w", "b" }
local patterns = {
	-- %a = alphabet, %d = digit, %w = alphanumeric, %l = lowercase %u = uppercase
	-- ^ = start of line, $ = end of line
	-- capitalised versions are complements
	word_beginnings = {
		{ pattern = "%A%a", offset_from_start = 1, offset_from_end = 0 }, -- non-alphabet followed by alphabet
		{ pattern = "%u%l", offset_from_start = 0, offset_from_end = 1 }, -- uppercase followed by lowercase
		{ pattern = "%l%u", offset_from_start = 1, offset_from_end = 0 }, -- lowercase followed by uppercase
		{ pattern = "%D%d", offset_from_start = 1, offset_from_end = 0 }, -- non-digit followed by digit
		{ pattern = "^%w",  offset_from_start = 0, offset_from_end = 0 }, -- alphanumeric at the start of a line
	},
	word_endings = {
		{ pattern = "%a%A", offset_from_start = 0, offset_from_end = 1 }, -- alphabet followed by a non-alphabet
		{ pattern = "%l%u", offset_from_start = 0, offset_from_end = 1 }, -- lowercase followed by uppercase
		{ pattern = "%d%D", offset_from_start = 0, offset_from_end = 1 }, -- digit followed by non-digit
		{ pattern = "%w$",  offset_from_start = 0, offset_from_end = 0 }, -- alphanumeric at the end of a line
	},
}
---@class (exact) motionOpts
---@field count integer|nil Number of times to perform the motion (default is 1).
---@field multi_line boolean Whether the motion can cross line boundaries.
---@field must_move boolean Whether the motion is forced to move at least one character.
---@field inclusive boolean|table<string, boolean>|nil
---		Whether the motion is inclusive.
---		Or whether the motion is inclusive for each motion key.

---@type motionOpts
local default_opts = {
	multi_line = true,
	must_move = true,
	inclusive = {
		w = false,
		b = false,
		e = true,
		ge = true,
	}
}
local user_opts = default_opts

---Gets the (1, 0)-indexed ending byte positions of the motions 'w', 'e', 'b', and 'ge',
---with better word boundaries.
---If opts.multi_line is false and there is no world boundary found on the same line,
---will return a column position one past the end of the line.
---@param key 'w'|'e'|'b'|'ge' the motion to perform.
---@param start_pos table<integer, integer>|nil (1, 0)-indexed row and byte number of the starting position for the motion (default is cursor position).
---@param opts motionOpts Options to fine-tune the behaviour of the motion.
---@return table<integer, integer> (1, 0)-indexed row and byte number of the ending position for the motion.
function M.get_word_motion_end(key, start_pos, opts)
	start_pos = start_pos or vim.api.nvim_win_get_cursor(0) -- (1,0)-indexed
	local forward = vim.list_contains(forward_motion_keys, key)
	local pats = vim.list_contains(word_begin_motion_keys, key) and patterns.word_beginnings or patterns.word_endings
	local cur_lnum, byte_idx0 = unpack(start_pos)
	local line = getline(cur_lnum)
	local line_len = len(line)
	local char_pos
	if line_len ~= 0 then
		-- need the conditional to avoid overflow
		char_pos = byte_idx_to_char_pos(line, byte_idx0 + 1)
	else
		char_pos = 0
	end
	local start_lnum = cur_lnum
	local end_lnum = opts.multi_line
		and (forward
			and vim.api.nvim_buf_line_count(0)
			or 1)
		or start_lnum
	local first_lnum = math.min(start_lnum, end_lnum)
	local second_lnum = math.max(start_lnum, end_lnum)
	for _ = 1, (opts.count or 1) do
		-- looping through rows (if next location not found in line)
		while true do
			local result
			if forward then
				result = get_next_position({ line, line_len }, char_pos, pats, opts.must_move)
			else
				result = get_prev_position({ line, line_len }, char_pos, pats, opts.must_move)
			end
			if result then
				char_pos = result
				break
			end
			if not opts.multi_line
				or (cur_lnum >= second_lnum and forward)
				or (cur_lnum <= first_lnum and not forward) then
				-- return a past the end sentinel
				-- bytes(line) + 1 for a forward motion,
				-- -1 for a reverse motion
				return { cur_lnum, forward and string.len(line) + 1 or -1 }
			end

			cur_lnum = forward and cur_lnum + 1 or cur_lnum - 1
			line = getline(cur_lnum)
			line_len = len(line)
			-- setting this to 0 or len(line)+1 ensures
			-- that even if we must move, we will find a match
			-- in the new line.
			char_pos = forward and 0 or line_len + 1
		end
	end
	return { cur_lnum, char_pos_to_byte_idx(line, char_pos) - 1 }
end

---Moves the cursor to the destination of the specified subword motion.
---@param key "w"|"e"|"b"|"ge" the motion to perform
---@param opts motionOpts|nil
function M.word_motion(key, opts)
	-- GUARD validate motion parameter
	if not vim.list_contains(motion_keys, key) then
		local msg = "Invalid key: " .. key .. "\nOnly w, e, b, and ge are supported."
		-- TODO: title of the error message
		vim.notify(msg, vim.log.levels.ERROR, { title = "Motions" })
		return
	end
	if not user_opts then
		M.setup()
	end
	opts = vim.tbl_deep_extend(
		"force",
		user_opts,
		opts or {}
	)
	if type(opts.inclusive) == "table" then
		opts.inclusive = opts.inclusive[key]
	end
	opts.count = opts.count or vim.v.count1
	local mode = vim.api.nvim_get_mode().mode
	if mode == "no" then -- operator pending mode
		if opts.inclusive then
			vim.cmd.normal("v") -- force charwise inclusive motion
		end
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	local end_pos = M.get_word_motion_end(key, pos, opts)
	if end_pos[2] < 0 then
		end_pos[2] = 0
	end
	vim.api.nvim_win_set_cursor(0, end_pos)
	local should_open_fold = vim.tbl_contains(vim.opt_local.foldopen:get(), "hor")
	if vim.tbl_contains({ "n", "no" }, mode) and should_open_fold then
		vim.cmd.normal("zv")
	end
end

M.text_objects = {}

function M.text_objects.charwise_line(key, mode)
	local operation = mode == "o" and vim.v.operator or "v"
	local start = key == "i" and "^" or "0"
	local finish = key == "i" and "g_" or "$"
	return "<Esc>" .. start .. "\"" .. vim.v.register .. operation .. finish
end

---@return table<integer, integer>|nil start_pos (1,0)-indexed
---@return table<integer, integer>|nil end_pos (1,0)-indexed
local function get_inner_word_range(cursor_pos)
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
	--    - Result: [ge_end + 1 (or 0), line_end]
	--
	-- 3. Cursor is on LEADING whitespace (before a word):
	--    - `e` finds the end of the *next* word.
	--    - `b` from that end finds the start of the *next* word.
	--    - Since cursor < start_b, we are in the whitespace before it.
	--    - We find the start of this whitespace block using `ge`.
	--    - Result: [ge_end + 1 (or 0), start_b - 1]

	local line = getline(cursor_pos[1])
	local line_len = len(line)
	if line_len == 0 then
		return nil, nil
	end

	local opts = { must_move = false, multi_line = false }
	local e_pos = M.get_word_motion_end("e", cursor_pos, opts)
	local start_pos, end_pos

	-- Check for "past end of line" (Case 2: Trailing whitespace)
	local line_bytes = string.len(line)

	if e_pos[2] >= line_bytes then
		-- Case 2: Trailing Whitespace
		end_pos = { cursor_pos[1], line_bytes - 1 }
		local ge_pos = M.get_word_motion_end("ge", cursor_pos, opts)

		if ge_pos[2] == -1 then
			-- Sentinel case: start of line (and line starts with whitespace)
			start_pos = { cursor_pos[1], 0 }
		else
			-- Start is one char after ge_pos
			-- Convert ge_pos[2] (0-based byte) to 1-based char pos
			local char_pos = byte_idx_to_char_pos(line, ge_pos[2] + 1)
			-- Increment char pos
			char_pos = char_pos + 1
			-- Convert back to 0-based byte idx
			local start_byte = char_pos_to_byte_idx(line, char_pos) - 1
			start_pos = { cursor_pos[1], start_byte }
		end
	else
		-- Case 1 or 3
		local b_pos = M.get_word_motion_end("b", e_pos, opts)

		if cursor_pos[2] >= b_pos[2] then
			-- Case 1: Inside Word
			start_pos = b_pos
			end_pos = e_pos
		else
			-- Case 3: Leading Whitespace
			-- End is one char before b_pos,
			-- we return its last byte position
			end_pos = { cursor_pos[1], b_pos[2] - 1 }

			local ge_pos = M.get_word_motion_end("ge", cursor_pos, opts)
			if ge_pos[2] == -1 and string.match(line, "^%s") then
				start_pos = { cursor_pos[1], 0 }
			else
				local start_char_pos = byte_idx_to_char_pos(line, ge_pos[2] + 1)
				start_char_pos = start_char_pos + 1
				local start_byte = char_pos_to_byte_idx(line, start_char_pos) - 1
				start_pos = { cursor_pos[1], start_byte }
			end
		end
	end
	return start_pos, end_pos
end

---@param key "i"|"a" inner or around
---@param mode "o"|"x" operator or visual mode
function M.text_objects.word(key, mode)
	if key ~= "i" and key ~= "a" then
		-- TODO: title of the error message
		vim.notify(
			"Invalid key: " .. key .. "\nOnly i and a are supported .",
			vim.log.levels.ERROR,
			{ title = "TextObject" }
		)
		return
	end

	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local start_pos, end_pos

	-- TODO: logic for 'aw'
	start_pos, end_pos = get_inner_word_range(cursor_pos)

	if not start_pos or not end_pos then
		return ""
	end

	-- build up the expression to execute
	local operation
	local inclusive = key == "i"
	if mode == "o" then
		operation = vim.v.operator .. (inclusive and "v" or "")
	else
		-- visual mode
		operation = vim.fn.mode() -- visual mode
		-- if not inclusive then
		-- 	endPos[2] = endPos[2] - 1
		-- end
	end
	local str = "<Esc><Cmd>lua vim.api.nvim_win_set_cursor(0, {" .. start_pos[1] .. ", " .. start_pos[2] .. "})<CR>"
		.. "\"" .. vim.v.register
		.. operation
		.. "<Cmd>lua vim.api.nvim_win_set_cursor(0, {" .. end_pos[1] .. ", " .. end_pos[2] .. "})<CR>"
	return str
end

function M.setup(opts)
	user_opts = vim.tbl_deep_extend("keep", opts or {}, default_opts)
end

vim.keymap.set(
	{ "n", "x", "o" },
	"<Plug>(motion-w)",
	function()
		M.word_motion("w")
	end
)
vim.keymap.set(
	{ "n", "x", "o" },
	"<Plug>(motion-b)",
	function()
		M.word_motion("b")
	end
)
vim.keymap.set(
	{ "n", "x", "o" },
	"<Plug>(motion-e)",
	function()
		M.word_motion("e")
	end
)
vim.keymap.set(
	{ "n", "x", "o" },
	"<Plug>(motion-ge)",
	function()
		M.word_motion("ge")
	end
)
vim.keymap.set(
	"o",
	"<Plug>(textobject-iw)",
	function()
		return M.text_objects.word("i", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	"x",
	"<Plug>(textobject-iw)",
	function()
		return M.text_objects.word("i", "x")
	end,
	{ expr = true }
)
vim.keymap.set(
	"o",
	"<Plug>(textobject-aw)",
	function()
		return M.text_objects.word("a", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	"x",
	"<Plug>(textobject-aw)",
	function()
		return M.text_objects.word("a", "x")
	end,
	{ expr = true }
)
vim.keymap.set(
	"o",
	"<Plug>(textobject-il)",
	function()
		return M.text_objects.charwise_line("i", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	"x",
	"<Plug>(textobject-il)",
	function()
		return M.text_objects.charwise_line("i", "x")
	end,
	{ expr = true }
)
vim.keymap.set(
	"o",
	"<Plug>(textobject-al)",
	function()
		return M.text_objects.charwise_line("a", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	"x",
	"<Plug>(textobject-al)",
	function()
		return M.text_objects.charwise_line("a", "x")
	end,
	{ expr = true }
)

return M
