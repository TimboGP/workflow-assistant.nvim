-- Per-rule runtime state: last_fired (notified), snoozed_until.
-- last_checked is kept in memory only (not persisted) to avoid disk churn.
local M = {}

M._data = {}  -- name -> { last_fired, snoozed_until }  (persisted)
M._mem = {}   -- name -> { last_checked }               (in-memory)
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
  if cfg.state.persist then M.load() end
end

function M.load()
  local fd = io.open(M._cfg.state.path, "r")
  if not fd then return end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then M._data = decoded end
end

function M.save()
  if not (M._cfg and M._cfg.state.persist) then return end
  local path = M._cfg.state.path
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, encoded = pcall(vim.json.encode, M._data)
  if not ok then return end
  local fd = io.open(path, "w")
  if not fd then return end
  fd:write(encoded)
  fd:close()
end

-- Notification bookkeeping (persisted) ------------------------------------
function M.last_fired(name) return entry(name).last_fired end
function M.mark_fired(name) entry(name).last_fired = os.time(); M.save() end

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
