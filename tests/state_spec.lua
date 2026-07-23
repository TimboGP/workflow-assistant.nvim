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

  describe("inbox", function()
    it("is empty until something is added", function()
      assert.are.equal(0, state.inbox_count())
      assert.are.same({}, state.inbox_list())
    end)

    it("adds an entry retrievable by rule name", function()
      state.inbox_add("r", "dirty tree", { { label = "x" } })
      local entry = state.inbox_get("r")
      assert.are.equal("r", entry.rule)
      assert.are.equal("dirty tree", entry.message)
      assert.are.equal(1, #entry.actions)
    end)

    it("defaults priority to 'normal' when omitted", function()
      state.inbox_add("r", "msg", {})
      assert.are.equal("normal", state.inbox_get("r").priority)
    end)

    it("stores an explicit priority", function()
      state.inbox_add("r", "msg", {}, "low")
      assert.are.equal("low", state.inbox_get("r").priority)
    end)

    it("dedupes by rule name: re-adding replaces rather than stacks", function()
      state.inbox_add("r", "first", {})
      state.inbox_add("r", "second", {})
      assert.are.equal(1, state.inbox_count())
      assert.are.equal("second", state.inbox_get("r").message)
    end)

    it("lists entries oldest-first", function()
      state.inbox_add("a", "msg-a", {})
      state._inbox.a.ts = 100
      state.inbox_add("b", "msg-b", {})
      state._inbox.b.ts = 50
      local list = state.inbox_list()
      assert.are.equal("b", list[1].rule)
      assert.are.equal("a", list[2].rule)
    end)

    it("removes an entry", function()
      state.inbox_add("r", "msg", {})
      state.inbox_remove("r")
      assert.is_nil(state.inbox_get("r"))
      assert.are.equal(0, state.inbox_count())
    end)

    it("removing an absent entry is a harmless no-op", function()
      assert.has_no.errors(function() state.inbox_remove("nope") end)
    end)

    it("is reset by a fresh setup() call", function()
      state.inbox_add("r", "msg", {})
      state.setup(fresh_cfg(tmpfile))
      assert.are.equal(0, state.inbox_count())
    end)
  end)

  describe("on_update", function()
    local function setup_with(fn)
      state.setup(vim.tbl_extend("force", fresh_cfg(tmpfile), { on_update = fn }))
    end

    it("fires when an entry is added", function()
      local calls = 0
      setup_with(function() calls = calls + 1 end)
      state.inbox_add("r", "msg", {})
      assert.are.equal(1, calls)
    end)

    it("fires when an entry is removed", function()
      local calls = 0
      setup_with(function() calls = calls + 1 end)
      state.inbox_add("r", "msg", {})
      calls = 0
      state.inbox_remove("r")
      assert.are.equal(1, calls)
    end)

    it("does not fire when removing an entry that isn't there", function()
      local calls = 0
      setup_with(function() calls = calls + 1 end)
      state.inbox_remove("nope")
      assert.are.equal(0, calls)
    end)

    it("is contained: a throwing callback doesn't break the inbox mutation", function()
      setup_with(function() error("boom") end)
      assert.has_no.errors(function() state.inbox_add("r", "msg", {}) end)
      assert.is_not_nil(state.inbox_get("r"))
    end)

    it("is a harmless no-op when unset", function()
      state.setup(fresh_cfg(tmpfile))
      assert.has_no.errors(function() state.inbox_add("r", "msg", {}) end)
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
