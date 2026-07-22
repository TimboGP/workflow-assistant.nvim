-- Rule registry + evaluation. The scheduler (triggers.lua) calls into this.
local M = {}
local rule_mod = require("workflow-assistant.rule")
local context = require("workflow-assistant.context")
local state = require("workflow-assistant.state")

M._rules = {}      -- name -> rule
M._order = {}      -- names, registration order
M._evaluating = {} -- name -> true while an async condition is in flight
M._cfg = nil

function M.setup(cfg)
  M._cfg = cfg
  M._rules, M._order, M._evaluating = {}, {}, {}
end

function M.register(spec)
  local rule = rule_mod.normalize(spec, M._cfg)
  if not M._rules[rule.name] then
    M._order[#M._order + 1] = rule.name
  end
  M._rules[rule.name] = rule
  return rule
end

function M.get(name) return M._rules[name] end

function M.list()
  local out = {}
  for _, name in ipairs(M._order) do out[#out + 1] = M._rules[name] end
  return out
end

-- Evaluate one rule. `force` bypasses enabled/cooldown/snooze/check_interval
-- (used by :WorkflowAssistant check). It does NOT reset the cooldown timer.
function M.evaluate(name, force)
  local rule = M._rules[name]
  if not rule then return end
  if M._evaluating[name] then return end

  if not force then
    if not M._cfg.enabled then return end
    if not rule.enabled then return end
    if not state.can_fire(rule) then return end
    if not state.due_for_check(rule) then return end
  end

  local ctx = context.build(M._cfg)
  if not force and M._cfg.require_project and not ctx.is_project then return end

  state.mark_checked(name)
  M._evaluating[name] = true

  local done_called = false
  local function done(should, payload)
    if done_called then return end
    done_called = true
    M._evaluating[name] = nil
    if not should then return end
    if not force then state.mark_fired(name) end
    local ok, err = pcall(rule.action, ctx, payload, rule)
    if not ok then
      vim.notify(
        ("workflow-assistant: action error in '%s': %s"):format(name, tostring(err)),
        vim.log.levels.ERROR)
    end
  end

  local ok, err = pcall(rule.condition, ctx, done)
  if not ok then
    M._evaluating[name] = nil
    vim.notify(
      ("workflow-assistant: condition error in '%s': %s"):format(name, tostring(err)),
      vim.log.levels.ERROR)
  end
end

-- Evaluate every rule with the given trigger. For events, also match the name.
function M.evaluate_matching(kind, event_name, force)
  for _, name in ipairs(M._order) do
    local rule = M._rules[name]
    if rule.trigger == kind then
      if kind == "event" then
        if vim.tbl_contains(rule.events, event_name) then
          M.evaluate(name, force)
        end
      else
        M.evaluate(name, force)
      end
    end
  end
end

return M
