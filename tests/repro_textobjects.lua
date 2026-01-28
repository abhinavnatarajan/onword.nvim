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
	"foo bar baz",   -- 1
	"  leading",     -- 2
	"trailing   ",   -- 3
	"  both  "       -- 4
})

-- Test 1: On 'bar' (foo |bar baz)
-- 'bar' starts at col 4 (0-indexed), ends at col 6.
print("Running Test 1: Inside word 'bar'")
vim.api.nvim_win_set_cursor(0, {1, 5}) -- On 'a' of bar
local res = M.text_objects.word('i', 'o')
local r1, c1, r2, c2 = parse_range(res)
print("Result:", r1, c1, r2, c2)
assert_eq(r1, 1, "Start Row")
assert_eq(c1, 4, "Start Col") -- b
assert_eq(r2, 1, "End Row")
assert_eq(c2, 6, "End Col") -- r

-- Test 2: Leading whitespace ( | leading)
-- whitespace is col 0-1.
print("Running Test 2: Leading whitespace")
vim.api.nvim_win_set_cursor(0, {2, 0})
res = M.text_objects.word('i', 'o')
r1, c1, r2, c2 = parse_range(res)
print("Result:", r1, c1, r2, c2)
assert_eq(r1, 2, "Start Row")
assert_eq(c1, 0, "Start Col")
assert_eq(r2, 2, "End Row")
assert_eq(c2, 1, "End Col")

-- Test 3: Trailing whitespace (trailing | )
-- 'trailing' is 0-7. ws is 8-10.
print("Running Test 3: Trailing whitespace")
vim.api.nvim_win_set_cursor(0, {3, 9})
res = M.text_objects.word('i', 'o')
r1, c1, r2, c2 = parse_range(res)
print("Result:", r1, c1, r2, c2)
assert_eq(r1, 3, "Start Row")
assert_eq(c1, 8, "Start Col")
assert_eq(r2, 3, "End Row")
assert_eq(c2, 10, "End Col")

print("All tests passed!")
