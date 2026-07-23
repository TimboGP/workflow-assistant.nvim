-- Parses short duration strings ("30m", "2h", "90s", "1d") into seconds.
-- Shared by reminders.lua (:WorkflowAssistant remind) and focus.lua
-- (:WorkflowAssistant focus) — pulled out on its own so neither has to
-- require the other (focus.lua reusing reminders.parse_duration directly
-- would be circular: reminders.lua already requires actions.lua, and
-- actions.lua needs focus.lua for the interrupt-threshold override).
local M = {}

local UNITS = { s = 1, m = 60, h = 60 * 60, d = 24 * 60 * 60 }

--- Returns seconds, or nil + an error message on failure.
function M.parse(str)
  if type(str) ~= "string" then return nil, "duration must be a string" end
  local n, unit = str:match("^(%d+)([smhd])$")
  if not n then
    return nil, ("invalid duration '%s' (expected e.g. 30m, 2h, 90s, 1d)"):format(str)
  end
  return tonumber(n) * UNITS[unit]
end

return M
