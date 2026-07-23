-- Public entry point. `require("workflow-assistant").setup{...}`
local M = {}

local config = require("workflow-assistant.config")
local state = require("workflow-assistant.state")
local actions = require("workflow-assistant.actions")
local engine = require("workflow-assistant.engine")
local triggers = require("workflow-assistant.triggers")
local commands = require("workflow-assistant.commands")
local builtins = require("workflow-assistant.rules")
local reminders = require("workflow-assistant.reminders")
local focus = require("workflow-assistant.focus")

M.config = nil

function M.setup(opts)
  local cfg = config.merge(opts)
  M.config = cfg

  state.setup(cfg)
  actions.setup(cfg)
  engine.setup(cfg)

  for _, spec in ipairs(builtins.build(cfg)) do
    engine.register(spec)
  end
  for _, spec in ipairs(cfg.custom_rules or {}) do
    engine.register(spec)
  end

  triggers.setup(cfg)
  reminders.setup(cfg)
  commands.setup(M)
end

-- ---- Public API (also used by :WorkflowAssistant) -----------------------

--- Register a rule at runtime and re-arm event autocmds.
function M.register(spec)
  local rule = engine.register(spec)
  triggers.wire_events()
  return rule
end

--- Force-evaluate a single rule now (bypasses cooldown/snooze).
function M.check(name) engine.evaluate(name, true) end

--- Force-evaluate every timer/event rule now.
function M.check_all()
  for _, rule in ipairs(engine.list()) do
    if rule.trigger ~= "manual" then engine.evaluate(rule.name, true) end
  end
end

function M.enable(on)
  M.config.enabled = on and true or false
  actions.notify("Workflow assistant " .. (M.config.enabled and "enabled" or "disabled"))
end

function M.toggle() M.enable(not M.config.enabled) end

function M.snooze(name, seconds)
  state.snooze(name, seconds)
  actions.notify(("Snoozed '%s' for %d min"):format(name, math.floor(seconds / 60)))
end

function M.reset(name) state.reset(name) end

--- Tell the tests rule group that tests just ran (resets the write counter).
function M.mark_tested()
  require("workflow-assistant.rules.tests").mark_tested()
  actions.notify("Marked tests as run.")
end

function M.rule_names()
  local names = {}
  for _, r in ipairs(engine.list()) do
    names[#names + 1] = r.name
  end
  return names
end

function M.show_list()
  local lines = { "Workflow rules:" }
  for _, r in ipairs(engine.list()) do
    lines[#lines + 1] =
      string.format("  %-22s [%s]%s %s", r.name, r.trigger, r.enabled and "" or " (off)", r.desc)
  end
  actions.notify(table.concat(lines, "\n"))
end

--- Set an ad-hoc reminder due after `duration_str` (e.g. "30m", "2h", "90s",
--- "1d"). Returns the reminder id, or nil if the duration is invalid.
function M.remind(duration_str, message)
  local secs, err = reminders.parse_duration(duration_str)
  if not secs then
    actions.notify("Invalid duration: " .. err, vim.log.levels.ERROR)
    return nil
  end
  local id = reminders.add({ in_seconds = secs, message = message })
  actions.notify(("Reminder set for %s: %s"):format(duration_str, message))
  return id
end

function M.unremind(id)
  if reminders.remove(id) then
    actions.notify("Reminder cancelled.")
  else
    actions.notify("No such reminder: " .. tostring(id), vim.log.levels.WARN)
  end
end

function M.reminder_ids()
  local ids = {}
  for _, r in ipairs(reminders.list()) do
    ids[#ids + 1] = r.id
  end
  return ids
end

function M.show_reminders()
  local list = reminders.list()
  if #list == 0 then
    actions.notify("No pending reminders.")
    return
  end
  local now = os.time()
  local lines = { "Pending reminders:" }
  for _, r in ipairs(list) do
    local remaining = math.max(0, r.due - now)
    lines[#lines + 1] = ("  [%s] in %ds — %s"):format(r.id, remaining, r.message)
  end
  actions.notify(table.concat(lines, "\n"))
end

function M.show_status()
  actions.notify(
    ("Workflow assistant: %s | %d rules registered"):format(
      M.config.enabled and "on" or "off",
      #engine.list()
    )
  )
end

--- Open the floating panel listing pending nudges and all registered rules.
function M.panel() require("workflow-assistant.panel").open() end

--- Short status string for a statusline/lualine component, e.g. "WA 3" or
--- "FOCUS 3". Empty string when there's nothing pending and focus mode is
--- off, so it disappears cleanly; focus mode always shows something so
--- there's a passive reminder it's on even with an empty inbox.
function M.statusline()
  local n = state.inbox_count()
  local focused = focus.is_active()
  if not focused and n == 0 then return "" end
  local label = focused and "FOCUS" or "WA"
  return n > 0 and (label .. " " .. n) or label
end

--- Turn focus mode on. `duration_str` (e.g. "25m") is optional — omit for
--- indefinite, until unfocus() is called. Only priority = "critical" rules
--- still interrupt while it's active; everything else still notifies and
--- lands in the inbox, same as being below interrupt_priority normally.
function M.focus(duration_str)
  local ok, err = focus.start(duration_str)
  if not ok then
    actions.notify("Invalid duration: " .. err, vim.log.levels.ERROR)
    return
  end
  actions.notify(duration_str and ("Focus mode on for " .. duration_str .. ".") or "Focus mode on.")
end

function M.unfocus()
  focus.stop()
  actions.notify("Focus mode off.")
end

function M.is_focused() return focus.is_active() end

return M
