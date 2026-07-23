-- Normalizes a rule spec (built-in or user) into a validated internal rule.
--
-- A rule spec looks like:
--   {
--     name           = "unique_id",          -- required
--     desc           = "human description",
--     trigger        = "timer"|"event"|"manual",  -- default "timer"
--     events         = { "BufWritePost" },   -- for trigger == "event"
--     cooldown       = 45 * 60,              -- min seconds between notifications
--     check_interval = 5 * 60,              -- min seconds between condition runs
--     priority       = "low"|"normal"|"high", -- default "normal"; see config's
--                                              -- `interrupt_priority` and
--                                              -- actions.prompt
--     enabled        = true,
--     condition      = function(ctx, done) done(should_fire, payload) end,
--     action         = function(ctx, payload, rule) ... end,
--   }
--
-- `condition` MUST call `done` exactly once (sync or async). If it never does,
-- the rule silently stops re-evaluating.
local M = {}
local priority = require("workflow-assistant.priority")

function M.normalize(spec, cfg)
  assert(type(spec) == "table", "rule must be a table")
  assert(type(spec.name) == "string" and spec.name ~= "", "rule.name (string) required")
  assert(
    type(spec.condition) == "function",
    "rule.condition (function) required for " .. tostring(spec.name)
  )
  assert(
    type(spec.action) == "function",
    "rule.action (function) required for " .. tostring(spec.name)
  )

  local trigger = spec.trigger or "timer"
  assert(
    trigger == "timer" or trigger == "event" or trigger == "manual",
    "rule.trigger must be 'timer'|'event'|'manual' for " .. spec.name
  )

  local rule_priority = spec.priority or priority.DEFAULT
  assert(
    priority.is_valid(rule_priority),
    "rule.priority must be 'low'|'normal'|'high' for " .. spec.name
  )

  local rule = {
    name = spec.name,
    desc = spec.desc or "",
    trigger = trigger,
    events = spec.events or {},
    cooldown = spec.cooldown or cfg.default_cooldown,
    check_interval = spec.check_interval or cfg.tick_interval,
    priority = rule_priority,
    condition = spec.condition,
    action = spec.action,
    enabled = true,
  }

  -- Resolve enabled: explicit config override > spec default > true.
  local override = cfg.rules[spec.name]
  if override ~= nil then
    rule.enabled = override and true or false
  elseif spec.enabled ~= nil then
    rule.enabled = spec.enabled and true or false
  end

  return rule
end

return M
