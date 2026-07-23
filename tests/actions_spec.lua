-- actions.prompt's inbox side effects. vim.ui.select is stubbed per test
-- instead of faked at package.loaded level, since it's a single function on
-- a real global, not a whole module to swap out.
local state = require("workflow-assistant.state")
local actions = require("workflow-assistant.actions")

describe("actions.prompt", function()
  local orig_select
  local rule = { name = "r" }

  before_each(function()
    state.setup({ state = { persist = false, path = "" } })
    state.reset()
    actions.setup({ notify = { title = "Workflow", level = vim.log.levels.INFO } })
    orig_select = vim.ui.select
  end)

  after_each(function() vim.ui.select = orig_select end)

  it("adds an inbox entry for the rule as soon as the prompt opens", function()
    vim.ui.select = function() end -- never calls back: prompt stays "open"
    actions.prompt(rule, "dirty tree", {})
    local entry = state.inbox_get("r")
    assert.is_not_nil(entry)
    assert.are.equal("dirty tree", entry.message)
  end)

  it("runs the choice and clears the inbox entry when a custom action is picked", function()
    local ran = false
    vim.ui.select = function(items, _, cb) cb(items[1]) end
    actions.prompt(rule, "msg", { { label = "Do it", run = function() ran = true end } })
    assert.is_true(ran)
    assert.is_nil(state.inbox_get("r"))
  end)

  it("clears the inbox entry when Dismiss is picked, without running anything", function()
    vim.ui.select = function(_, _, cb) cb("Dismiss") end
    actions.prompt(rule, "msg", {})
    assert.is_nil(state.inbox_get("r"))
  end)

  it("clears the inbox entry and snoozes the rule when Snooze is picked", function()
    vim.ui.select = function(_, _, cb) cb("Snooze 30m") end
    actions.prompt(rule, "msg", {})
    assert.is_nil(state.inbox_get("r"))
    assert.is_true(state.is_snoozed("r"))
  end)

  it("leaves the inbox entry pending when the prompt is cancelled", function()
    vim.ui.select = function(_, _, cb) cb(nil) end
    actions.prompt(rule, "msg", {})
    assert.is_not_nil(state.inbox_get("r"))
  end)

  it("dedupes by rule name: re-firing while pending replaces, not stacks", function()
    vim.ui.select = function() end
    actions.prompt(rule, "first", {})
    actions.prompt(rule, "second", {})
    assert.are.equal(1, state.inbox_count())
    assert.are.equal("second", state.inbox_get("r").message)
  end)
end)
