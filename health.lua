-- :checkhealth workflow-assistant
local M = {}

function M.check()
  local h = vim.health or require("health")
  local start = h.start or h.report_start
  local ok = h.ok or h.report_ok
  local warn = h.warn or h.report_warn
  local err = h.error or h.report_error

  start("workflow-assistant")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10 (vim.system available)")
  else
    err("Neovim < 0.10 required for vim.system; upgrade recommended")
  end

  if vim.fn.executable("git") == 1 then
    ok("git found")
  else
    err("git not found — git rules will stay inert")
  end

  if vim.fn.executable("rg") == 1 then
    ok("ripgrep found (open_todos usable)")
  else
    warn("ripgrep (rg) not found — open_todos rule will no-op")
  end
end

return M
