-- :WorkflowAssistant <subcommand> [args]
local M = {}

local SUBS = {
  "check", "enable", "disable", "toggle",
  "list", "snooze", "reset", "status", "tested",
}

function M.setup(api)
  vim.api.nvim_create_user_command("WorkflowAssistant", function(opts)
    local a = opts.fargs
    local sub = a[1]
    if sub == "check" then
      if a[2] then api.check(a[2]) else api.check_all() end
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
    else
      vim.notify(
        "WorkflowAssistant: " .. table.concat(SUBS, "|"),
        vim.log.levels.WARN)
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
      if vim.tbl_contains({ "check", "snooze", "reset" }, parts[2]) then
        return api.rule_names()
      end
      return {}
    end,
  })
end

return M
