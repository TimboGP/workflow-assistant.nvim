-- Reusable side-effects rules can call from their `action` functions.
local M = {}
local state = require("workflow-assistant.state")
local priority = require("workflow-assistant.priority")

local _cfg

function M.setup(cfg) _cfg = cfg end

function M.notify(msg, level)
  vim.notify(msg, level or _cfg.notify.level, { title = _cfg.notify.title })
end

-- Interactive picker. `choices` = list of { label = string, run = function }.
-- "Snooze 30m" and "Dismiss" are appended automatically. Always registers an
-- inbox entry (see state.inbox_*) so the nudge stays visible in the panel /
-- statusline() count until the user actually picks something.
--
-- Below `cfg.interrupt_priority`, that's *all* that happens: a passive
-- notify plus the inbox entry — no vim.ui.select popup. The user opens
-- :WorkflowAssistant panel and hits <CR> on it whenever they get to it,
-- which replays this same choice menu. At or above the threshold, the
-- popup still shows immediately, same as before; cancelling it (e.g. <Esc>)
-- leaves the entry pending rather than discarding it.
function M.prompt(rule, msg, choices)
  choices = choices or {}
  state.inbox_add(rule.name, msg, choices, rule.priority)

  if not priority.meets(rule.priority, _cfg.interrupt_priority) then
    M.notify(("[%s] %s"):format(rule.name, msg))
    return
  end

  local items, handlers = {}, {}
  for _, c in ipairs(choices) do
    items[#items + 1] = c.label
    handlers[c.label] = c.run
  end

  local snooze_label = "Snooze 30m"
  items[#items + 1] = snooze_label
  handlers[snooze_label] = function() state.snooze(rule.name, 30 * 60) end

  local dismiss_label = "Dismiss"
  items[#items + 1] = dismiss_label
  handlers[dismiss_label] = function() end

  vim.ui.select(items, {
    prompt = string.format("[%s] %s", _cfg.notify.title, msg),
  }, function(choice)
    if not choice then return end
    state.inbox_remove(rule.name)
    local h = handlers[choice]
    if h then pcall(h) end
  end)
end

-- Fire-and-forget shell command; on_done(res) runs on the main loop.
function M.run_cmd(cwd, cmd, on_done)
  local ok = pcall(vim.system, cmd, { cwd = cwd, text = true }, function(res)
    if on_done then vim.schedule(function() on_done(res) end) end
  end)
  if not ok and on_done then
    vim.schedule(function() on_done({ code = -1, stderr = "failed to spawn command" }) end)
  end
end

-- Best-effort "open a git UI" used by several rules.
function M.open_git_status()
  if pcall(vim.cmd, "Git") then return end -- vim-fugitive
  if pcall(vim.cmd, "Neogit") then return end -- neogit
  M.notify("Open your git client to review changes.")
end

return M
