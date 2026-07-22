-- Minimal init for headless test runs: puts this plugin and plenary.nvim on
-- runtimepath. Run via `make test` (which ensures plenary is vendored into
-- .deps/plenary.nvim first) — see Makefile.
local root = vim.fn.getcwd()

vim.opt.runtimepath:prepend(root)

local plenary_candidates = {
  root .. "/.deps/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/packer/start/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}

local found = false
for _, path in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    found = true
    break
  end
end

if not found then
  error("plenary.nvim not found - run `make deps` (or `make test`, which depends on it) first")
end

vim.cmd("runtime plugin/plenary.vim")
