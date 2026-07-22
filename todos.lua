-- Count outstanding TODO/FIXME markers via ripgrep. Opt-in (can be noisy).
local actions = require("workflow-assistant.actions")

local M = {}

local function have(exe) return vim.fn.executable(exe) == 1 end

function M.rules(cfg)
  local patterns = cfg.todos.patterns
  local threshold = cfg.todos.threshold

  return {
    {
      name = "open_todos",
      desc = "Outstanding TODO/FIXME markers in the project",
      trigger = "timer",
      check_interval = 30 * 60,
      cooldown = 4 * 60 * 60, -- gentle: a few times a day at most
      enabled = false,        -- opt-in via rules = { open_todos = true }
      condition = function(ctx, done)
        if not have("rg") then return done(false) end
        local alt = table.concat(patterns, "|")
        local cmd = { "rg", "--no-messages", "--count-matches", "-e", "(" .. alt .. ")", ctx.root }
        actions.run_cmd(ctx.root, cmd, function(res)
          local total = 0
          if res.stdout then
            for line in res.stdout:gmatch("[^\n]+") do
              local n = line:match(":(%d+)$")
              if n then total = total + tonumber(n) end
            end
          end
          done(total >= threshold, { count = total })
        end)
      end,
      action = function(ctx, payload, rule)
        actions.prompt(rule,
          ("%d open TODO/FIXME marker(s)"):format(payload.count),
          {
            {
              label = "List in quickfix",
              run = function()
                local alt = table.concat(patterns, "|")
                local ok = pcall(vim.cmd, ("silent! grep! -e '(%s)' %s")
                  :format(alt, vim.fn.fnameescape(ctx.root)))
                if ok then pcall(vim.cmd, "copen") end
              end,
            },
          })
      end,
    },
  }
end

return M
