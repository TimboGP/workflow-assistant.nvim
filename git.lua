-- Thin async git layer built on vim.system (Neovim >= 0.10).
-- Every callback is re-entered on the main loop via vim.schedule, so callers
-- may freely use vim.api / vim.ui inside them.
local M = {}

-- run(cwd, args, cb) -> cb(ok: boolean, stdout_lines: string[], stderr: string?)
function M.run(cwd, args, cb)
  local cmd = vim.list_extend({ "git" }, args)
  local ok = pcall(vim.system, cmd, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      local out = {}
      if res.stdout and #res.stdout > 0 then
        out = vim.split(res.stdout, "\n", { trimempty = true })
      end
      cb(res.code == 0, out, res.stderr)
    end)
  end)
  if not ok then
    -- git not spawnable (e.g. not installed): fail gracefully.
    vim.schedule(function() cb(false, {}, "failed to spawn git") end)
  end
end

function M.is_repo(cwd, cb)
  M.run(cwd, { "rev-parse", "--is-inside-work-tree" }, function(ok, out)
    cb(ok and out[1] == "true")
  end)
end

function M.branch(cwd, cb)
  M.run(cwd, { "rev-parse", "--abbrev-ref", "HEAD" }, function(ok, out)
    cb(ok and out[1] or nil)
  end)
end

-- Returns the porcelain lines (each = one changed/untracked entry), or nil.
function M.status(cwd, cb)
  M.run(cwd, { "status", "--porcelain" }, function(ok, out)
    cb(ok and out or nil)
  end)
end

-- Returns { ahead = n, behind = n } vs @{upstream}, or nil if no upstream.
function M.ahead_behind(cwd, cb)
  M.run(cwd, { "rev-list", "--left-right", "--count", "HEAD...@{upstream}" }, function(ok, out)
    if not ok or not out[1] then return cb(nil) end
    local ahead, behind = out[1]:match("(%d+)%s+(%d+)")
    if not ahead then return cb(nil) end
    cb({ ahead = tonumber(ahead), behind = tonumber(behind) })
  end)
end

-- Seconds since the last commit on HEAD, or nil (no commits / error).
function M.seconds_since_last_commit(cwd, cb)
  M.run(cwd, { "log", "-1", "--format=%ct" }, function(ok, out)
    local ts = ok and out[1] and tonumber(out[1]) or nil
    cb(ts and (os.time() - ts) or nil)
  end)
end

return M
