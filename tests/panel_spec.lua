local state = require("workflow-assistant.state")
local engine = require("workflow-assistant.engine")
local panel = require("workflow-assistant.panel")
local focus = require("workflow-assistant.focus")

local function noop() end

local function fresh()
  state.setup({ state = { persist = false, path = "" } })
  state.reset()
  engine.setup({ rules = {}, default_cooldown = 60, tick_interval = 60, root_markers = {} })
  focus.stop() -- module-local state can leak across specs; start unfocused
end

describe("panel.render", function()
  before_each(fresh)

  it("shows zero pending and lists registered rules", function()
    engine.register({ name = "r1", trigger = "timer", condition = noop, action = noop })
    local lines, index = panel.render()
    assert.is_not_nil(lines[1]:match("^Pending %(0%)"))
    local found = false
    for i in ipairs(lines) do
      if index[i] and index[i].kind == "rule" and index[i].name == "r1" then found = true end
    end
    assert.is_true(found)
  end)

  it("shows a pending item and maps its line back to the rule", function()
    state.inbox_add("r1", "dirty tree", {})
    local lines, index = panel.render()
    assert.is_not_nil(lines[1]:match("^Pending %(1%)"))
    local found
    for i in ipairs(lines) do
      if index[i] and index[i].kind == "pending" then found = index[i] end
    end
    assert.is_not_nil(found)
    assert.are.equal("r1", found.name)
  end)

  it("shows each rule's priority and a pending item's priority", function()
    engine.register({
      name = "r1",
      trigger = "timer",
      condition = noop,
      action = noop,
      priority = "high",
    })
    state.inbox_add("r1", "dirty tree", {}, "high")
    local lines = panel.render()
    local rule_line, pending_line
    for _, line in ipairs(lines) do
      if line:match("^  r1%s+%[timer") then rule_line = line end
      if line:match("^  r1%s+%[high") then pending_line = line end
    end
    assert.is_not_nil(pending_line)
    assert.is_not_nil(rule_line)
    assert.is_not_nil(rule_line:find("high", 1, true))
  end)

  it("shows a focus mode banner when active, and none when inactive", function()
    local lines = panel.render()
    assert.is_nil(lines[1]:match("^Focus mode"))

    focus.start("10m")
    lines = panel.render()
    assert.is_not_nil(lines[1]:match("^Focus mode: on"))
    focus.stop()
  end)
end)

describe("panel.open (interactive)", function()
  before_each(fresh)

  after_each(function()
    if panel._win and vim.api.nvim_win_is_valid(panel._win) then
      vim.api.nvim_win_close(panel._win, true)
    end
    panel._win, panel._buf = nil, nil
  end)

  local function keymap_fn(buf, lhs)
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if km.lhs == lhs then return km.callback end
    end
  end

  local function line_for(kind, name)
    for i, item in pairs(panel._index) do
      if item.kind == kind and item.name == name then return i end
    end
  end

  it("opens a floating window with the rendered lines", function()
    panel.open()
    assert.is_true(vim.api.nvim_win_is_valid(panel._win))
    local lines = vim.api.nvim_buf_get_lines(panel._buf, 0, -1, false)
    assert.is_not_nil(lines[1]:match("^Pending"))
  end)

  it("dismiss (d) clears a pending entry under the cursor", function()
    state.inbox_add("r1", "dirty tree", {})
    panel.open()
    vim.api.nvim_win_set_cursor(panel._win, { line_for("pending", "r1"), 0 })
    keymap_fn(panel._buf, "d")()
    assert.is_nil(state.inbox_get("r1"))
  end)

  it("snooze (s) snoozes the rule under the cursor", function()
    engine.register({ name = "r1", trigger = "timer", condition = noop, action = noop })
    panel.open()
    vim.api.nvim_win_set_cursor(panel._win, { line_for("rule", "r1"), 0 })
    keymap_fn(panel._buf, "s")()
    assert.is_true(state.is_snoozed("r1"))
  end)

  it("toggle-enable (x) flips a rule's enabled flag", function()
    engine.register({ name = "r1", trigger = "timer", condition = noop, action = noop })
    panel.open()
    vim.api.nvim_win_set_cursor(panel._win, { line_for("rule", "r1"), 0 })
    assert.is_true(engine.get("r1").enabled)
    keymap_fn(panel._buf, "x")()
    assert.is_false(engine.get("r1").enabled)
  end)

  it("close (q) closes the window", function()
    panel.open()
    local win = panel._win
    keymap_fn(panel._buf, "q")()
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  it("act (<CR>) on a rule line force-evaluates it, bypassing gates", function()
    local fired = false
    engine.register({
      name = "r2",
      trigger = "manual",
      cooldown = 999999,
      check_interval = 999999,
      condition = function(_, done) done(true) end,
      action = function() fired = true end,
    })
    panel.open()
    vim.api.nvim_win_set_cursor(panel._win, { line_for("rule", "r2"), 0 })
    keymap_fn(panel._buf, "<CR>")()
    assert.is_true(fired)
  end)

  it("act (<CR>) on a pending item with no custom choices just clears it", function()
    state.inbox_add("r1", "msg", {})
    panel.open()
    vim.api.nvim_win_set_cursor(panel._win, { line_for("pending", "r1"), 0 })
    keymap_fn(panel._buf, "<CR>")()
    assert.is_nil(state.inbox_get("r1"))
  end)
end)
