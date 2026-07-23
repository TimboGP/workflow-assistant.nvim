-- Nudge to run tests once enough source files change since the last run.
-- Writes are counted via a BufWritePost event rule; a timer rule reads the
-- counter. Call require("workflow-assistant").mark_tested() (or the command
-- :WorkflowAssistant tested) after running tests to reset it.
local actions = require("workflow-assistant.actions")

local M = {}
M._writes_since_test = 0

function M.mark_tested() M._writes_since_test = 0 end

function M.rules(cfg)
  local src_ft = cfg.tests.filetypes
  local threshold = cfg.tests.remind_after_writes
  local test_cmd = cfg.tests.command

  return {
    {
      name = "count_source_writes",
      desc = "Bookkeeping: count source writes since tests ran",
      trigger = "event",
      events = { "BufWritePost" },
      check_interval = 0,
      cooldown = 0,
      condition = function(ctx, done)
        if vim.tbl_contains(src_ft, ctx.filetype) then
          M._writes_since_test = M._writes_since_test + 1
        end
        done(false) -- never notifies
      end,
      action = function() end,
    },

    {
      name = "tests_stale",
      desc = "Many changes since tests last ran",
      trigger = "timer",
      check_interval = 60,
      cooldown = 20 * 60,
      priority = "low", -- FYI, not urgent: notify + inbox, no interrupt
      condition = function(_, done)
        done(M._writes_since_test >= threshold, { writes = M._writes_since_test })
      end,
      action = function(ctx, payload, rule)
        local choices = {}
        if test_cmd then
          choices[#choices + 1] = {
            label = "Run tests",
            run = function()
              actions.notify("Running tests…")
              actions.run_cmd(ctx.root, test_cmd, function(res)
                M.mark_tested()
                local okt = res.code == 0
                actions.notify(
                  okt and "Tests passed." or "Tests failed — check output.",
                  okt and vim.log.levels.INFO or vim.log.levels.ERROR
                )
              end)
            end,
          }
        end
        choices[#choices + 1] = { label = "Mark as tested", run = M.mark_tested }
        actions.prompt(rule, ("%d writes since tests last ran"):format(payload.writes), choices)
      end,
    },
  }
end

return M
