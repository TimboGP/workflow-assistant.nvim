-- Ad-hoc, one-shot timed reminders. A single scanning timer checks for due
-- reminders on every tick (no per-reminder timer, so this scales); pending
-- reminders are persisted via workflow-assistant.state and survive restarts.
--
-- `actions` (custom choices passed to add()) only apply within the current
-- session: functions aren't JSON-serializable, so they don't survive a
-- restart. A reminder that outlives a restart just gets a plain notify.
local M = {}
local state = require("workflow-assistant.state")
local actions = require("workflow-assistant.actions")
local duration = require("workflow-assistant.duration")

local uv = vim.uv or vim.loop

M._timer = nil
M._cfg = nil
M._counter = 0
M._live_actions = {} -- id -> choices (in-memory only, current session)

--- Parse "30m", "2h", "90s", "1d" -> seconds. Returns nil, err on failure.
M.parse_duration = duration.parse

local function next_id()
  M._counter = M._counter + 1
  return tostring(os.time()) .. "-" .. tostring(M._counter)
end

--- spec = { in_seconds=?, at=? (epoch seconds), message = string, actions? = choices }
--- Returns the reminder's id.
function M.add(spec)
  assert(type(spec) == "table", "reminder spec must be a table")
  assert(
    type(spec.message) == "string" and spec.message ~= "",
    "reminder.message (string) required"
  )
  local due
  if spec.at then
    due = spec.at
  elseif spec.in_seconds then
    due = os.time() + spec.in_seconds
  else
    error("reminder spec needs `in_seconds` or `at`")
  end

  local id = next_id()
  if spec.actions then M._live_actions[id] = spec.actions end
  state.add_reminder({ id = id, due = due, message = spec.message })
  return id
end

function M.list() return state.list_reminders() end

function M.remove(id)
  M._live_actions[id] = nil
  return state.remove_reminder(id)
end

local function fire(reminder)
  local choices = M._live_actions[reminder.id]
  M._live_actions[reminder.id] = nil
  if choices and #choices > 0 then
    local items, handlers = {}, {}
    for _, c in ipairs(choices) do
      items[#items + 1] = c.label
      handlers[c.label] = c.run
    end
    vim.ui.select(items, { prompt = ("[Reminder] %s"):format(reminder.message) }, function(choice)
      if choice and handlers[choice] then pcall(handlers[choice]) end
    end)
  else
    actions.notify(reminder.message)
  end
end

--- Fire and remove every reminder whose due time has passed. Removes before
--- invoking the (possibly async) action so an overlapping scan can't
--- double-fire it. `now` defaults to os.time(); tests may inject a fixed
--- clock value instead.
function M.scan(now)
  now = now or os.time()
  local due = {}
  for _, r in ipairs(state.list_reminders()) do
    if r.due <= now then due[#due + 1] = r end
  end
  for _, r in ipairs(due) do
    state.remove_reminder(r.id)
    fire(r)
  end
end

function M.setup(cfg)
  M._cfg = cfg
  M.stop()
  local interval_ms = (cfg.reminders and cfg.reminders.scan_interval or 30) * 1000
  local timer = uv.new_timer()
  M._timer = timer
  timer:start(interval_ms, interval_ms, function()
    vim.schedule(function()
      if M._cfg.enabled then M.scan() end
    end)
  end)
end

function M.stop()
  if M._timer then
    M._timer:stop()
    if not M._timer:is_closing() then M._timer:close() end
    M._timer = nil
  end
end

return M
