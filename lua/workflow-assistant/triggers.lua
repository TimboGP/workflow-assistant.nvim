-- Wires the two firing mechanisms: a repeating libuv timer (for `timer` rules)
-- and autocmds (for `event` rules). Callbacks vim.schedule onto the main loop
-- because libuv timer callbacks run in a restricted "fast" context.
local M = {}
local engine = require("workflow-assistant.engine")
local context = require("workflow-assistant.context")

local uv = vim.uv or vim.loop

M._timer = nil
M._augroup = nil
M._cfg = nil

function M.setup(cfg)
  M._cfg = cfg
  M.stop()
  M._augroup = vim.api.nvim_create_augroup("WorkflowAssistant", { clear = true })

  -- Keep the project-root cache honest when the user changes directory.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = M._augroup,
    callback = function() context.clear_cache() end,
  })

  M.start_timer()
  M.wire_events()
end

function M.start_timer()
  local interval_ms = M._cfg.tick_interval * 1000
  local timer = uv.new_timer()
  M._timer = timer
  timer:start(interval_ms, interval_ms, function()
    vim.schedule(function()
      if not M._cfg.enabled then return end
      engine.evaluate_matching("timer")
    end)
  end)
end

-- (Re)register autocmds for the union of events used by event-triggered rules.
-- Safe to call repeatedly; it clears the group's autocmds first.
function M.wire_events()
  if not M._augroup then return end
  -- Preserve the DirChanged cache-buster by re-adding it after clearing.
  vim.api.nvim_clear_autocmds({ group = M._augroup })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = M._augroup,
    callback = function() context.clear_cache() end,
  })

  local events = {}
  for _, rule in ipairs(engine.list()) do
    if rule.trigger == "event" then
      for _, ev in ipairs(rule.events) do
        events[ev] = true
      end
    end
  end
  local event_list = vim.tbl_keys(events)
  if #event_list == 0 then return end

  vim.api.nvim_create_autocmd(event_list, {
    group = M._augroup,
    callback = function(args)
      if not M._cfg.enabled then return end
      engine.evaluate_matching("event", args.event)
    end,
  })
end

function M.stop()
  if M._timer then
    M._timer:stop()
    if not M._timer:is_closing() then M._timer:close() end
    M._timer = nil
  end
  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
end

return M
