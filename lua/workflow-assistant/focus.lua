-- Focus mode: temporarily raises the effective interrupt threshold to
-- "critical" so only the most urgent nudges can still pop up; everything
-- else still notifies + lands in the inbox, same as being below
-- interrupt_priority normally (see actions.prompt).
--
-- In-memory only (not persisted) — restarting Neovim always starts
-- unfocused. A timed session is checked lazily against os.time() whenever
-- is_active() is called; no background timer is needed just for expiry.
local M = {}
local state = require("workflow-assistant.state")
local duration = require("workflow-assistant.duration")

M._active = false
M._until = nil -- epoch seconds; nil = indefinite while _active

--- Turn focus mode on. `duration_str` (e.g. "25m") is optional — omit for
--- indefinite, until stop() is called. Returns true, or nil + an error
--- message if duration_str is given but invalid (focus mode is left
--- untouched in that case).
function M.start(duration_str)
  local until_ts = nil
  if duration_str then
    local secs, err = duration.parse(duration_str)
    if not secs then return nil, err end
    until_ts = os.time() + secs
  end
  M._active = true
  M._until = until_ts
  state.notify_update()
  return true
end

function M.stop()
  if not M._active then return end
  M._active = false
  M._until = nil
  state.notify_update()
end

--- Is focus mode currently in effect? A timed session past its `_until`
--- expires itself the first time this is checked, rather than needing a
--- separate polling timer.
function M.is_active()
  if not M._active then return false end
  if M._until and os.time() >= M._until then
    M.stop()
    return false
  end
  return true
end

--- Seconds remaining, or nil if inactive or indefinite.
function M.remaining()
  if not M.is_active() or not M._until then return nil end
  return math.max(0, M._until - os.time())
end

return M
