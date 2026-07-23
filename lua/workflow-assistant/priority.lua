-- Named priority levels (none < low < normal < high < critical). Decides
-- whether a rule's nudge interrupts with a vim.ui.select prompt or just
-- notifies + lands in the inbox (see actions.prompt and config's
-- `interrupt_priority`).
--
-- Two levels are special-cased in actions.prompt rather than handled purely
-- by rank:
--   "none"     — never notifies or lands in the inbox at all (see how
--                rules/tests.lua's count_source_writes is silent today —
--                "none" is the formal, explicit way to declare that for any
--                rule, not just ones whose condition happens to never fire).
--   "critical" — the only priority that still interrupts during focus mode
--                (see focus.lua), which otherwise forces every rule through
--                the quiet notify+inbox path regardless of interrupt_priority.
local M = {}

M.LEVELS = { none = 0, low = 1, normal = 2, high = 3, critical = 4 }
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
