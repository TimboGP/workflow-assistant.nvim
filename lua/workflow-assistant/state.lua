-- Per-rule runtime state: last_fired (notified), snoozed_until.
-- last_checked is kept in memory only (not persisted) to avoid disk churn.
-- Also holds the persisted ad-hoc reminders list (see reminders.lua).
local M = {}

M._data = {} -- name -> { last_fired, snoozed_until }  (persisted)
M._reminders = {} -- list of { id, due, message }        (persisted)
M._mem = {} -- name -> { last_checked }               (in-memory)
M._inbox = {} -- rule name -> { id, rule, message, ts, actions, priority } (in-memory)
M._on_update = nil -- fired whenever the inbox changes; see config's on_update
M._cfg = nil

local function entry(name)
  M._data[name] = M._data[name] or {}
  return M._data[name]
end
local function mem(name)
  M._mem[name] = M._mem[name] or {}
  return M._mem[name]
end

function M.setup(cfg)
  M._cfg = cfg
  M._mem = {}
  M._inbox = {}
  M._on_update = cfg.on_update
  if cfg.state.persist then M.load() end
end

function M.load()
  local fd = io.open(M._cfg.state.path, "r")
  if not fd then return end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not (ok and type(decoded) == "table") then return end
  if decoded.rules ~= nil or decoded.reminders ~= nil then
    M._data = decoded.rules or {}
    M._reminders = decoded.reminders or {}
  else
    -- Legacy flat format (pre-reminders): the whole table is rule data.
    M._data = decoded
    M._reminders = {}
  end
end

function M.save()
  if not (M._cfg and M._cfg.state.persist) then return end
  local path = M._cfg.state.path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.json.encode, { rules = M._data, reminders = M._reminders })
  if not ok then return end
  local fd = io.open(path, "w")
  if not fd then return end
  fd:write(encoded)
  fd:close()
end

-- Notification bookkeeping (persisted) ------------------------------------
function M.last_fired(name) return entry(name).last_fired end
function M.mark_fired(name)
  entry(name).last_fired = os.time()
  M.save()
end

function M.snooze(name, seconds)
  entry(name).snoozed_until = os.time() + seconds
  M.save()
end
function M.is_snoozed(name)
  local u = entry(name).snoozed_until
  return u ~= nil and os.time() < u
end

-- Evaluation bookkeeping (in-memory) --------------------------------------
function M.last_checked(name) return mem(name).last_checked end
function M.mark_checked(name) mem(name).last_checked = os.time() end

function M.due_for_check(rule)
  local last = M.last_checked(rule.name)
  if not last then return true end
  return (os.time() - last) >= (rule.check_interval or 0)
end

-- Gate on whether a rule may *notify* right now (cooldown + snooze).
function M.can_fire(rule)
  if M.is_snoozed(rule.name) then return false end
  local last = M.last_fired(rule.name)
  if last and (os.time() - last) < rule.cooldown then return false end
  return true
end

-- Ad-hoc reminders (persisted) ---------------------------------------------
function M.list_reminders() return M._reminders end

function M.add_reminder(reminder)
  M._reminders[#M._reminders + 1] = reminder
  M.save()
end

--- Returns true if a reminder with this id was found and removed.
function M.remove_reminder(id)
  for i, r in ipairs(M._reminders) do
    if r.id == id then
      table.remove(M._reminders, i)
      M.save()
      return true
    end
  end
  return false
end

-- Notification inbox (in-memory only) --------------------------------------
-- Keyed by rule name, so a rule re-firing while its previous nudge is still
-- pending replaces that entry instead of stacking a second one.
local priority = require("workflow-assistant.priority")

local function notify_update()
  if M._on_update then pcall(M._on_update) end
end

function M.inbox_add(rule_name, message, actions, prio)
  M._inbox[rule_name] = {
    id = rule_name,
    rule = rule_name,
    message = message,
    ts = os.time(),
    actions = actions,
    priority = prio or priority.DEFAULT,
  }
  notify_update()
end

--- Removing an entry that isn't there is a no-op and doesn't fire on_update.
function M.inbox_remove(rule_name)
  if M._inbox[rule_name] == nil then return end
  M._inbox[rule_name] = nil
  notify_update()
end

function M.inbox_get(rule_name) return M._inbox[rule_name] end

--- Pending entries, oldest first.
function M.inbox_list()
  local out = {}
  for _, item in pairs(M._inbox) do
    out[#out + 1] = item
  end
  table.sort(out, function(a, b) return a.ts < b.ts end)
  return out
end

function M.inbox_count()
  local n = 0
  for _ in pairs(M._inbox) do
    n = n + 1
  end
  return n
end

function M.reset(name)
  if name then
    M._data[name] = nil
    M._mem[name] = nil
  else
    M._data = {}
    M._mem = {}
  end
  M.save()
end

return M
