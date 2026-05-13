local M = {}

local ok, utf8 = pcall(require, 'lua-utf8')

if ok then
	M.find, M.sub, M.len = utf8.find, utf8.sub, utf8.len
	M.char_pos_to_byte_idx = utf8.offset
	M.byte_idx_to_char_pos = function(str, byte_idx)
		local _, char_end_byte = utf8.offset(str, 0, math.min(byte_idx, string.len(str)))
		return utf8.len(str, 1, char_end_byte)
	end
else
	M.find, M.sub, M.len = string.find, string.sub, string.len
	M.char_pos_to_byte_idx = function(_, pos) return pos end
	M.byte_idx_to_char_pos = function(_, pos) return pos end
end

---Returns the content of the given line number.
---@param lnum number 1-indexed
---@return string
function M.getline(lnum)
	return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
end

---Returns the next character position in the line matching any of the given patterns.
---@param ln table<string, integer> the line to search and its length
---@param init_char_pos number the character position to start searching from
---@param pats table the patterns to search for
---@param must_move boolean|nil whether we must move at least one position
---@return number|nil result next character position found, or nil
function M.get_next_position(ln, init_char_pos, pats, must_move)
	local line, line_len = ln[1], ln[2]
	if must_move == nil then must_move = true end
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
		if start_search > 1 and M.sub(pattern, 1, 1) == "^" then
			return nil
		end
		local match_start = M.find(line, pattern, start_search)
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
function M.find_prev_match(line, pattern, init_char_pos)
	if M.sub(pattern, 1, 1) ~= "^" then
		-- if the pattern does not begin the line,
		-- we search for the last match of the pattern
		-- this allows us to implement a crude 'rfind'
		pattern = ".*" .. pattern
	end
	return M.find(M.sub(line, 1, init_char_pos), pattern)
end

---Returns the previous character position in the line matching any of the given patterns.
---@param ln table<string, integer> the line to search and its length
---@param init_char_pos number the character position to start searching backwards from
---@param pats table the patterns to search for
---@param must_move boolean|nil whether we must move at least one position
---@return number|nil result previous character position found, or nil
function M.get_prev_position(ln, init_char_pos, pats, must_move)
	local line, line_len = ln[1], ln[2]
	if must_move == nil then must_move = true end
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
			and M.sub(pattern, M.len(pattern)) == "$"
			and M.sub(pattern, -2) ~= "%" then
			return nil
		end
		local _, match_end = M.find_prev_match(line, pattern, end_search)
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

return M
