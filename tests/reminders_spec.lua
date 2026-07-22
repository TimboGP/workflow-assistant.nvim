local state = require("workflow-assistant.state")
local reminders = require("workflow-assistant.reminders")

describe("reminders.parse_duration", function()
  it("parses seconds/minutes/hours/days", function()
    assert.are.equal(90, reminders.parse_duration("90s"))
    assert.are.equal(30 * 60, reminders.parse_duration("30m"))
    assert.are.equal(2 * 60 * 60, reminders.parse_duration("2h"))
    assert.are.equal(24 * 60 * 60, reminders.parse_duration("1d"))
  end)

  it("rejects an unknown unit", function()
    local secs, err = reminders.parse_duration("30x")
    assert.is_nil(secs)
    assert.is_not_nil(err)
  end)

  it("rejects a non-numeric duration", function()
    local secs, err = reminders.parse_duration("soon")
    assert.is_nil(secs)
    assert.is_not_nil(err)
  end)

  it("rejects a non-string input", function()
    local secs, err = reminders.parse_duration(nil)
    assert.is_nil(secs)
    assert.is_not_nil(err)
  end)
end)

describe("reminders", function()
  local tmpfile

  before_each(function()
    tmpfile = vim.fn.tempname()
    state.setup({ state = { persist = true, path = tmpfile } })
    state.reset() -- see state_spec.lua: module state can leak across specs
    -- state.reset() intentionally only clears rule bookkeeping, not
    -- user-scheduled reminders, so clear those directly for test isolation.
    state._reminders = {}
    -- fire() without custom actions notifies via actions.lua, which needs setup().
    require("workflow-assistant.actions").setup({
      notify = { title = "Workflow", level = vim.log.levels.INFO },
    })
  end)

  after_each(function() os.remove(tmpfile) end)

  it("add() computes an absolute due time from in_seconds", function()
    local before = os.time()
    local id = reminders.add({ in_seconds = 60, message = "stand up" })
    local list = reminders.list()
    assert.are.equal(1, #list)
    assert.are.equal(id, list[1].id)
    assert.are.equal("stand up", list[1].message)
    assert.is_true(list[1].due >= before + 60)
  end)

  it("add() honors an absolute `at` time", function()
    reminders.add({ at = 12345, message = "at a fixed time" })
    assert.are.equal(12345, reminders.list()[1].due)
  end)

  it("remove() cancels a pending reminder", function()
    local id = reminders.add({ in_seconds = 60, message = "x" })
    assert.is_true(reminders.remove(id))
    assert.are.equal(0, #reminders.list())
  end)

  it(
    "remove() returns false for an unknown id",
    function() assert.is_false(reminders.remove("nope")) end
  )

  describe("scan", function()
    it("fires and removes a reminder once its due time has passed", function()
      -- No `actions` here: firing with choices routes through vim.ui.select,
      -- which needs a real UI and would hang headless. That path is
      -- exercised manually; scan()'s due-time/removal logic is what's under
      -- test.
      reminders.add({ in_seconds = 60, message = "x" })
      local due_at = reminders.list()[1].due

      reminders.scan(due_at - 1)
      assert.are.equal(1, #reminders.list()) -- not due yet

      reminders.scan(due_at)
      assert.are.equal(0, #reminders.list()) -- fired and removed
    end)

    it("leaves not-yet-due reminders untouched", function()
      reminders.add({ in_seconds = 1000, message = "later" })
      reminders.scan(os.time())
      assert.are.equal(1, #reminders.list())
    end)

    it("persists the removal so a reload doesn't resurrect a fired reminder", function()
      reminders.add({ at = 100, message = "x" })
      reminders.scan(200)
      state.setup({ state = { persist = true, path = tmpfile } })
      assert.are.equal(0, #reminders.list())
    end)
  end)

  it("round-trips pending reminders across a reload", function()
    reminders.add({ at = 99999999999, message = "far future" })
    state.setup({ state = { persist = true, path = tmpfile } })
    local list = reminders.list()
    assert.are.equal(1, #list)
    assert.are.equal("far future", list[1].message)
  end)
end)
