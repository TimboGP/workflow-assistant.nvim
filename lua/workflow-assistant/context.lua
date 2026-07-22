-- Builds a snapshot of the current project/session, passed to every rule.
-- Must be called on the main loop (touches vim.api / vim.fn).
local M = {}

local root_cache = {} -- cwd -> resolved root (false = "no project")

-- Walk upward from `start` looking for any of `markers`. Cached per cwd.
function M.find_root(start, markers)
  start = start or vim.fn.getcwd()
  local cached = root_cache[start]
  if cached ~= nil then return cached or nil end
  local found = vim.fs.find(markers, { path = start, upward = true, limit = 1 })
  local root = (found and found[1]) and vim.fs.dirname(found[1]) or false
  root_cache[start] = root
  return root or nil
end

function M.clear_cache() root_cache = {} end

function M.build(cfg)
  local cwd = vim.fn.getcwd()
  local found = M.find_root(cwd, cfg.root_markers)
  local buf = vim.api.nvim_get_current_buf()
  return {
    cwd = cwd,
    root = found or cwd,
    is_project = found ~= nil,
    bufnr = buf,
    bufname = vim.api.nvim_buf_get_name(buf),
    filetype = vim.bo[buf].filetype,
    now = os.time(),
  }
end

return M
