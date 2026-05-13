local modrev, specrev = "git", "-1"

rockspec_format = "3.0"
package = "onword.nvim"
version = modrev .. specrev

description = {
  summary = "Subword motions and textobjects with support for multibyte characters",
  detailed = "",
  labels = { "neovim", "neovim-plugin" },
  homepage = "https://github.com/abhinavnatarajan/onword.nvim",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "luautf8",
}

source = {
  url = "git://github.com/abhinavnatarajan/onword.nvim",
}

build = {
  type = "builtin",
}
