vim.cmd [[set runtimepath+=.]]
local M = require('onword')

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(msg .. ": Expected '" .. tostring(expected) .. "', got '" .. tostring(actual) .. "'")
	end
end

-- Helper to extract coordinates from the returned string
-- String format: ...set_cursor(0, {r1, c1})...set_cursor(0, {r2, c2})...
local function parse_range(str)
	local r1, c1 = str:match("set_cursor%(0, {(%d+), (%d+)}%)")
	local r2, c2 = str:match(".*set_cursor%(0, {(%d+), (%d+)}%)")
	return tonumber(r1), tonumber(c1), tonumber(r2), tonumber(c2)
end

-- Setup buffer
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"foo bar  baz  ", -- 1
	"  leading",   -- 2
	"trailing   ", -- 3
	"  both  ",    -- 4
	"        ",    -- 5
	"",            -- 6
	"  after  ",   -- 7
	"    ",        -- 8
	"  last",      -- 9
})

local tests = {
	{
		title = "`iw` on word 'bar'",
		start_pos = { 1, 4 }, -- on 'b' of 'bar'
		textobject = 'iw',
		expected_range = { 1, 4, 1, 6 },
	},
	{
		title = "`iw` on ws between 'bar' and 'baz'",
		start_pos = { 1, 7 }, -- on first space between 'bar' and 'baz'
		textobject = 'iw',
		expected_range = { 1, 7, 1, 8 },
	},
	{
		title = "`iw` in leading whitespace",
		-- 'leading' is col 2-7. ws is col 0-1
		start_pos = { 2, 1 },
		textobject = 'iw',
		expected_range = { 2, 0, 2, 1 },
	},
	{
		title = "`iw` in trailing whitespace",
		-- 'trailing' is col 0-7. ws is 8-10.
		start_pos = { 3, 9 }, -- on 'b' of 'bar'
		textobject = 'iw',
		expected_range = { 3, 8, 3, 10 },
	},
	{
		title = "`iw` in line with only whitespace",
		-- only return the same line
		start_pos = { 5, 4 },
		textobject = 'iw',
		expected_range = { 5, 0, 5, 7 },
	},
	{
		title = "`iw` in empty line",
		-- return empty line only
		start_pos = { 6, 0 },
		textobject = 'iw',
		expected_range = { 6, 0, 6, 0 },
	},
	{
		title = "`aw` on word bar",
		-- return 'bar' + following whitespace until 'baz'
		start_pos = { 1, 5 },
		textobject = 'aw',
		expected_range = { 1, 4, 1, 8 },
	},
	{
		title = "`aw` in whitespace between 'bar' and 'baz'",
		-- should return whitespace + 'baz'
		start_pos = { 1, 8 },
		textobject = 'aw',
		expected_range = { 1, 7, 1, 11 },
	},
	{
		title = "`aw` on leading whitespace",
		-- should return ws only on this line + 'leading'
		start_pos = { 2, 1 },
		textobject = 'aw',
		expected_range = { 2, 0, 2, 8 },
	},
	{
		title = "`aw` on 'trailing'",
		-- should return 'trailing' + ws only on this line
		start_pos = { 3, 1 },
		textobject = 'aw',
		expected_range = { 3, 0, 3, 10 },
	},
	{
		title = "`aw` in whitespace after 'trailing'",
		-- should return ws after trailing as well as the word 'both'
		start_pos = { 3, 9 },
		textobject = 'aw',
		expected_range = { 3, 8, 4, 5 },
	},
	{
		title = "`aw` in whitespace before 'both'",
		-- should return ws only on this line and 'both'
		start_pos = { 4, 0 },
		textobject = 'aw',
		expected_range = { 4, 0, 4, 5 },
	},
	{
		title = "`aw` in whitespace after 'both'",
		-- should return all ws from 'both' until empty line
		start_pos = { 4, 6 },
		textobject = 'aw',
		expected_range = { 4, 6, 6, 0 },
	},
	{
		title = "`aw` on line with only whitespace",
		-- should return all ws on this line + empty line
		start_pos = { 5, 0 },
		textobject = 'aw',
		expected_range = { 5, 0, 6, 0 },
	},
	{
		title = "`aw` on empty line",
		-- should return empty line and until end of 'after'
		start_pos = { 6, 0 },
		textobject = 'aw',
		expected_range = { 6, 0, 7, 6 },
	},
	{
		title = "`aw` on ws line before 'last'",
		-- should return ws on this line and on the next line until 'last'
		start_pos = { 8, 2 },
		textobject = 'aw',
		expected_range = { 8, 0, 9, 5 },
	},
}

local function run_test(test)
	-- 'bar' is col 4-6 (0-indexed).
	vim.api.nvim_win_set_cursor(0, test.start_pos)
	local res = M.textobjects.word(test.textobject, 'no')
	local r1, c1, r2, c2 = parse_range(res)
	print("Result:", r1, c1, r2, c2)
	assert_eq(r1, test.expected_range[1], "Start Row")
	assert_eq(c1, test.expected_range[2], "Start Col")
	assert_eq(r2, test.expected_range[3], "End Row")
	assert_eq(c2, test.expected_range[4], "End Col")
end

for i, test in ipairs(tests) do
	print("Test " .. i .. ": " .. test.title)
	run_test(test)
end

print("All tests passed!")
