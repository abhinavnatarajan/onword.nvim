local M = {}

local utils = require("onword.utils")

---@class motionSpec
---The patterns used to identify the target of the motion.
---@field patterns table
---Whether the motion goes forward or backwards.
---@field direction? "forward"|"backward"
---Whether the motion is inclusive.
---@field inclusive? boolean
---Whether the motion can cross line boundaries.
---@field multi_line? boolean
---Whether the motion should stop when an empty line is encountered.
---@field stop_at_empty_line? boolean
---Whether the motion is forced to move at least one character. Default is true.
---@field must_move? boolean
---The number of times to repeat the motion. The default is vim.v.count1.
---@field count? integer

---@param motion motionSpec?
---@return motionSpec
local function resolve_motion_opts(motion)
	return vim.tbl_extend("force", {
		direction = "forward",
		inclusive = true,
		multi_line = true,
		stop_at_empty_line = true,
		must_move = true,
		count = vim.v.count1
	}, motion or {})
end

---@param motion motionSpec The motion to compute.
---@param start_pos table<integer, integer>? (1, 0)-indexed row and byte number of the starting position for the motion. Defaults to cursor position.
---@return table<integer, integer> (1, 0)-indexed row and byte number of the ending position for the motion.
function M.compute_motion(motion, start_pos)
	start_pos = start_pos or vim.api.nvim_win_get_cursor(0) -- (1,0)-indexed
	motion = resolve_motion_opts(motion)
	local is_forward = motion.direction == "forward"
	local pats = motion.patterns

	local cur_lnum, byte_idx0 = unpack(start_pos)
	local line = utils.getline(cur_lnum)
	local line_len = utils.len(line)
	local char_pos
	if line_len ~= 0 then
		-- need the conditional to avoid overflow
		char_pos = utils.byte_idx_to_char_pos(line, byte_idx0 + 1)
	else
		char_pos = 0
	end
	local num_lines = vim.api.nvim_buf_line_count(0)
	for _ = 1, motion.count do
		while true do
			local result
			if is_forward then
				result = utils.get_next_position({ line, line_len }, char_pos, pats, motion.must_move)
			else
				result = utils.get_prev_position({ line, line_len }, char_pos, pats, motion.must_move)
			end
			if result then
				char_pos = result
				break
			end
			if not motion.multi_line
				or (cur_lnum >= num_lines and is_forward)
				or (cur_lnum <= 1 and not is_forward) then
				-- return a past the end sentinel
				-- bytes(line) + 1 for a forward motion,
				-- -1 for a reverse motion
				return { cur_lnum, is_forward and string.len(line) or -1 }
			end

			cur_lnum = is_forward and cur_lnum + 1 or cur_lnum - 1
			line = utils.getline(cur_lnum)
			line_len = utils.len(line)
			-- Check if we have moved to an empty line and return if needed
			if motion.stop_at_empty_line and string.len(line) == 0 then
				char_pos = 0
				break
			end
			-- setting this to 0 or len(line)+1 ensures
			-- that even if we must move, we will find a match
			-- in the new line.
			char_pos = is_forward and 0 or line_len + 1
		end
	end
	return { cur_lnum, utils.char_pos_to_byte_idx(line, char_pos) - 1 }
end

---Moves the cursor to the destination of the specified subword motion.
---@param motion motionSpec The motion to execute.
function M.run(motion)
	local mode = vim.api.nvim_get_mode().mode
	local pos = vim.api.nvim_win_get_cursor(0)
	local end_pos = M.compute_motion(motion, pos)
	-- nvim_win_set_cursor handles column values that are too large,
	-- but not negative ones.
	if end_pos[2] < 0 then
		end_pos[2] = 0
	end
	if mode == "no" and motion.inclusive then
		-- make the motion inclusive, preserving count
		vim.cmd.normal(vim.v.count1 .. "v")
	end
	vim.api.nvim_win_set_cursor(0, end_pos)
	local should_open_fold = vim.tbl_contains(vim.opt_local.foldopen:get(), "hor")
	if vim.tbl_contains({ "n", "no" }, mode) and should_open_fold then
		vim.cmd.normal("zv")
	end
end

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

---@type table<string, motionSpec>
M.builtin = {
	next_subword = {
		direction = "forward",
		patterns = patterns.word_beginnings,
		inclusive = false,
		multi_line = true,
		stop_at_empty_line = true,
	},
	next_subword_end = {
		direction = "forward",
		patterns = patterns.word_endings,
		inclusive = true,
		multi_line = true,
		stop_at_empty_line = false,
	},
	prev_subword = {
		direction = "backward",
		patterns = patterns.word_beginnings,
		inclusive = false,
		multi_line = true,
		stop_at_empty_line = true,
	},
	prev_subword_end = {
		direction = "backward",
		patterns = patterns.word_endings,
		inclusive = false, -- this deviates from default Vim behaviour but is more ergonomic
		multi_line = true,
		stop_at_empty_line = true,
	},
}

function M.next_subword()
	-- We need to special case this in operator mode as in the Vim documentation for 'w'
	-- If the motion is used with an operator and crosses a line boundary, then
	-- the end position is set to the end of the word rather than the beginning of the next word.
	local mode = vim.api.nvim_get_mode().mode
	local pos = vim.api.nvim_win_get_cursor(0)
	local end_pos = M.compute_motion(M.builtin.next_subword, pos)
	if end_pos[1] > pos[1] and mode == "no" then
		end_pos = M.compute_motion(M.builtin.next_subword_end, pos)
		vim.cmd.normal(vim.v.count1 .. "v")
	end
	if end_pos[2] < 0 then
		end_pos[2] = 0
	end
	vim.api.nvim_win_set_cursor(0, end_pos)
end

for motion_name, motion in pairs(M.builtin) do
	M[motion_name] = M[motion_name] or function()
		M.run(motion)
	end
end

return M
