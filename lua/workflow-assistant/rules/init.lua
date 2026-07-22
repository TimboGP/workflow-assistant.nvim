-- Assembles the built-in rule set. Each group returns a list of rule specs.
local M = {}

function M.build(cfg)
  local rules = {}
  vim.list_extend(rules, require("workflow-assistant.rules.git").rules(cfg))
  vim.list_extend(rules, require("workflow-assistant.rules.tests").rules(cfg))
  vim.list_extend(rules, require("workflow-assistant.rules.todos").rules(cfg))
  return rules
end

return M
