local M = {}

-- Lazy load a module.
local function lazy_load(modname)
	return setmetatable({}, {
		__index = function(_, key)
			return require(modname)[key]
		end,
		__newindex = function(_, key, value)
			require(modname)[key] = value
		end,
	})
end

M.motions = lazy_load("onword.motions")
M.textobjects = lazy_load("onword.textobjects")

vim.keymap.set(
	{ "n", "v", "o" },
	"<Plug>(onword-motion-next-subword)",
	function()
		M.motion.next_subword()
	end
)
vim.keymap.set(
	{ "n", "v", "o" },
	"<Plug>(onword-motion-previous-subword)",
	function()
		M.motion.prev_subword()
	end
)
vim.keymap.set(
	{ "n", "v", "o" },
	"<Plug>(onword-motion-next-subword-end)",
	function()
		M.motion.next_subword_end()
	end
)
vim.keymap.set(
	{ "n", "v", "o" },
	"<Plug>(onword-motion-previous-subword-end)",
	function()
		M.motion.prev_subword_end()
	end
)
vim.keymap.set(
	{ "v", "o" },
	"<Plug>(onword-textobject-inner-subword)",
	function()
		return M.textobjects.word("i", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	{ "v", "o" },
	"<Plug>(onword-textobject-around-subword)",
	function()
		return M.textobjects.word("a", "o")
	end,
	{ expr = true }
)
vim.keymap.set(
	{ "v", "o", },
	"<Plug>(onword-textobject-inner-line-charwise)",
	function()
		return M.textobjects.inner_line()
	end,
	{ expr = true }
)
vim.keymap.set(
	{ "v", "o", },
	"<Plug>(onword-textobject-around-line-charwise)",
	function()
		return M.textobjects.around_line()
	end,
	{ expr = true }
)

return M
