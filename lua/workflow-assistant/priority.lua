-- Named priority levels (low < normal < high). Decides whether a rule's
-- nudge interrupts with a vim.ui.select prompt or just notifies + lands in
-- the inbox (see actions.prompt and config's `interrupt_priority`).
local M = {}

M.LEVELS = { low = 1, normal = 2, high = 3 }
M.DEFAULT = "normal"

function M.is_valid(name) return M.LEVELS[name] ~= nil end

--- Does `priority` meet or exceed `threshold`? Both are level names; an
--- invalid/missing priority is treated as the default rather than erroring,
--- so a stray hand-built rule table (e.g. in tests) degrades safely.
function M.meets(priority, threshold)
  local p = M.LEVELS[priority] or M.LEVELS[M.DEFAULT]
  local t = M.LEVELS[threshold] or M.LEVELS[M.DEFAULT]
  return p >= t
end

return M
