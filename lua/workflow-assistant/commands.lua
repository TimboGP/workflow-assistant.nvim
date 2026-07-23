-- :WorkflowAssistant <subcommand> [args]
local M = {}

local SUBS = {
  "check",
  "enable",
  "disable",
  "toggle",
  "list",
  "snooze",
  "reset",
  "status",
  "tested",
  "remind",
  "reminders",
  "unremind",
  "panel",
}

function M.setup(api)
  vim.api.nvim_create_user_command("WorkflowAssistant", function(opts)
    local a = opts.fargs
    local sub = a[1]
    if sub == "check" then
      if a[2] then
        api.check(a[2])
      else
        api.check_all()
      end
    elseif sub == "enable" then
      api.enable(true)
    elseif sub == "disable" then
      api.enable(false)
    elseif sub == "toggle" then
      api.toggle()
    elseif sub == "list" then
      api.show_list()
    elseif sub == "status" then
      api.show_status()
    elseif sub == "tested" then
      api.mark_tested()
    elseif sub == "snooze" then
      local name = a[2]
      local mins = tonumber(a[3]) or 30
      if name then api.snooze(name, mins * 60) end
    elseif sub == "reset" then
      api.reset(a[2]) -- nil resets everything
    elseif sub == "remind" then
      local duration = a[2]
      local words = {}
      for i = 3, #a do
        words[#words + 1] = a[i]
      end
      local message = table.concat(words, " ")
      if not duration or message == "" then
        vim.notify("Usage: WorkflowAssistant remind <duration> <message>", vim.log.levels.WARN)
      else
        api.remind(duration, message)
      end
    elseif sub == "reminders" then
      api.show_reminders()
    elseif sub == "unremind" then
      api.unremind(a[2])
    elseif sub == "panel" then
      api.panel()
    else
      vim.notify("WorkflowAssistant: " .. table.concat(SUBS, "|"), vim.log.levels.WARN)
    end
  end, {
    nargs = "*",
    desc = "Workflow assistant control",
    complete = function(_, line)
      local parts = vim.split(vim.trim(line), "%s+")
      -- Completing the subcommand.
      if #parts <= 2 then
        local prefix = parts[2] or ""
        return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, SUBS)
      end
      -- Completing a rule name for check/snooze/reset.
      if vim.tbl_contains({ "check", "snooze", "reset" }, parts[2]) then return api.rule_names() end
      -- Completing a reminder id for unremind.
      if parts[2] == "unremind" then return api.reminder_ids() end
      return {}
    end,
  })
end

return M
