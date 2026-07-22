local state = require("workflow-assistant.state")

local function fresh_cfg(path, persist)
  return { state = { persist = persist ~= false, path = path } }
end

describe("state", function()
  local tmpfile

  before_each(function()
    tmpfile = vim.fn.tempname()
    state.setup(fresh_cfg(tmpfile))
    -- state.lua keeps module-local tables across requires; a nonexistent
    -- tmpfile means setup()'s load() no-ops and leaves prior specs' data in
    -- place, so force a clean slate explicitly.
    state.reset()
  end)

  after_each(function() os.remove(tmpfile) end)

  describe("due_for_check", function()
    it(
      "is true before the rule has ever been checked",
      function() assert.is_true(state.due_for_check({ name = "r", check_interval = 60 })) end
    )

    it("is false immediately after mark_checked, within check_interval", function()
      state.mark_checked("r")
      assert.is_false(state.due_for_check({ name = "r", check_interval = 60 }))
    end)
  end)

  describe("can_fire", function()
    it(
      "is true when never fired and not snoozed",
      function() assert.is_true(state.can_fire({ name = "r", cooldown = 60 })) end
    )

    it("is false within the cooldown window after firing", function()
      state.mark_fired("r")
      assert.is_false(state.can_fire({ name = "r", cooldown = 60 }))
    end)

    it("is false while snoozed, even if cooldown has elapsed", function()
      state.snooze("r", 60)
      assert.is_false(state.can_fire({ name = "r", cooldown = 0 }))
    end)
  end)

  describe("persistence", function()
    it("round-trips last_fired across a reload", function()
      state.mark_fired("r")
      state.setup(fresh_cfg(tmpfile))
      assert.is_not_nil(state.last_fired("r"))
    end)

    it("round-trips snoozed_until across a reload", function()
      state.snooze("r", 300)
      state.setup(fresh_cfg(tmpfile))
      assert.is_true(state.is_snoozed("r"))
    end)

    it("does not persist last_checked (in-memory only)", function()
      state.mark_checked("r")
      state.setup(fresh_cfg(tmpfile))
      assert.is_nil(state.last_checked("r"))
    end)

    it("does not write to disk when persist = false", function()
      local path = vim.fn.tempname()
      state.setup(fresh_cfg(path, false))
      state.mark_fired("r")
      assert.are.equal(0, vim.fn.filereadable(path))
    end)
  end)

  describe("reset", function()
    it("clears a single rule's state", function()
      state.mark_fired("a")
      state.mark_fired("b")
      state.reset("a")
      assert.is_nil(state.last_fired("a"))
      assert.is_not_nil(state.last_fired("b"))
    end)

    it("clears everything when called with no name", function()
      state.mark_fired("a")
      state.mark_fired("b")
      state.reset()
      assert.is_nil(state.last_fired("a"))
      assert.is_nil(state.last_fired("b"))
    end)
  end)
end)
