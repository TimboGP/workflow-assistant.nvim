-- :WorkflowAssistant panel — a floating window listing pending nudges (the
-- inbox) and every registered rule at a glance.
--   <CR> act     — pending: replay its choice menu; rule: force-check it now
--   s    snooze  — snooze the rule under cursor for 30 minutes
--   d    dismiss — clear the pending item under cursor (rule lines: no-op)
--   x    toggle  — flip enabled/disabled for the rule under cursor
--   q    close
local M = {}
local state = require("workflow-assistant.state")
local engine = require("workflow-assistant.engine")

M._buf = nil
M._win = nil
M._index = {} -- line number -> { kind = "pending"|"rule", name = rule_name }

local function fmt_ago(ts)
  if not ts then return "never" end
  local secs = os.time() - ts
  if secs < 60 then return secs .. "s ago" end
  if secs < 3600 then return math.floor(secs / 60) .. "m ago" end
  return math.floor(secs / 3600) .. "h ago"
end

--- Builds the panel's lines plus a per-line index of what that line refers
--- to. Pure (no window/buffer side effects), so it's testable on its own.
function M.render()
  local lines = {}
  local index = {}

  local pending = state.inbox_list()
  lines[#lines + 1] = ("Pending (%d)"):format(#pending)
  if #pending == 0 then
    lines[#lines + 1] = "  (none)"
  else
    for _, item in ipairs(pending) do
      lines[#lines + 1] = ("  %-22s %s"):format(item.rule, item.message)
      index[#lines] = { kind = "pending", name = item.rule }
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Rules"
  for _, rule in ipairs(engine.list()) do
    lines[#lines + 1] = ("  %-22s [%-6s] %-3s  fired:%-10s snoozed:%s"):format(
      rule.name,
      rule.trigger,
      rule.enabled and "on" or "off",
      fmt_ago(state.last_fired(rule.name)),
      state.is_snoozed(rule.name) and "yes" or "no"
    )
    index[#lines] = { kind = "rule", name = rule.name }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "<CR> act   s snooze 30m   d dismiss   x toggle-enable   q close"

  return lines, index
end

local function refresh()
  if not (M._buf and vim.api.nvim_buf_is_valid(M._buf)) then return end
  local lines, index = M.render()
  M._index = index
  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false
end

local function current_item()
  if not (M._win and vim.api.nvim_win_is_valid(M._win)) then return nil end
  local lnum = vim.api.nvim_win_get_cursor(M._win)[1]
  return M._index[lnum]
end

local function act()
  local item = current_item()
  if not item then return end

  if item.kind == "rule" then
    engine.evaluate(item.name, true)
    return
  end

  local entry = state.inbox_get(item.name)
  if not entry then return end
  local choices = entry.actions or {}
  if #choices == 0 then
    state.inbox_remove(item.name)
    refresh()
    return
  end

  local items, handlers = {}, {}
  for _, c in ipairs(choices) do
    items[#items + 1] = c.label
    handlers[c.label] = c.run
  end
  vim.ui.select(items, { prompt = entry.message }, function(choice)
    if not choice then return end
    state.inbox_remove(item.name)
    local h = handlers[choice]
    if h then pcall(h) end
    refresh()
  end)
end

local function snooze()
  local item = current_item()
  if not item then return end
  state.snooze(item.name, 30 * 60)
  state.inbox_remove(item.name)
  refresh()
end

local function dismiss()
  local item = current_item()
  if not item or item.kind ~= "pending" then return end
  state.inbox_remove(item.name)
  refresh()
end

local function toggle_enable()
  local item = current_item()
  if not item or item.kind ~= "rule" then return end
  local rule = engine.get(item.name)
  if rule then rule.enabled = not rule.enabled end
  refresh()
end

local function close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then vim.api.nvim_win_close(M._win, true) end
  M._win = nil
end

function M.open()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_set_current_win(M._win)
    refresh()
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  M._buf = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "workflow-assistant-panel"

  local width = math.min(90, math.floor(vim.o.columns * 0.8))
  local height = math.min(20, math.floor(vim.o.lines * 0.6))
  M._win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.max(width, 20),
    height = math.max(height, 6),
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Workflow Assistant ",
  })

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  map("<CR>", act)
  map("s", snooze)
  map("d", dismiss)
  map("x", toggle_enable)
  map("q", close)

  refresh()
end

return M
