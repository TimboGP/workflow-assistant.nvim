-- Uses fake state/context modules (via package.loaded) instead of hitting
-- disk or git, per HANDOVER.md's P0 test notes.
describe("engine.evaluate", function()
  local engine, fake_state

  before_each(function()
    package.loaded["workflow-assistant.engine"] = nil
    package.loaded["workflow-assistant.state"] = nil
    package.loaded["workflow-assistant.context"] = nil
    package.loaded["workflow-assistant.rule"] = nil

    fake_state = {
      can_fire = function() return true end,
      due_for_check = function() return true end,
      mark_checked = function() end,
      mark_fired = function() end,
    }
    package.loaded["workflow-assistant.state"] = fake_state
    package.loaded["workflow-assistant.context"] = {
      build = function() return { cwd = "/tmp", root = "/tmp", is_project = true, now = 0 } end,
    }

    engine = require("workflow-assistant.engine")
    engine.setup({
      enabled = true,
      require_project = false,
      rules = {},
      default_cooldown = 60,
      tick_interval = 60,
    })
  end)

  after_each(function()
    package.loaded["workflow-assistant.engine"] = nil
    package.loaded["workflow-assistant.state"] = nil
    package.loaded["workflow-assistant.context"] = nil
    package.loaded["workflow-assistant.rule"] = nil
  end)

  local function register_rule(opts)
    engine.register(vim.tbl_extend("force", {
      name = "r",
      condition = function(_, done) done(true) end,
      action = function() end,
    }, opts or {}))
  end

  it("fires the action when the condition says so and gates allow", function()
    local fired = false
    register_rule({ action = function() fired = true end })
    engine.evaluate("r")
    assert.is_true(fired)
  end)

  it("does not fire when the condition returns false", function()
    local fired = false
    register_rule({
      condition = function(_, done) done(false) end,
      action = function() fired = true end,
    })
    engine.evaluate("r")
    assert.is_false(fired)
  end)

  it("does not evaluate when cfg.enabled is false", function()
    engine.setup({ enabled = false, rules = {}, default_cooldown = 60, tick_interval = 60 })
    local fired = false
    register_rule({ action = function() fired = true end })
    engine.evaluate("r")
    assert.is_false(fired)
  end)

  it("does not evaluate when state.can_fire is false (cooldown/snooze)", function()
    fake_state.can_fire = function() return false end
    local fired = false
    register_rule({ action = function() fired = true end })
    engine.evaluate("r")
    assert.is_false(fired)
  end)

  it("does not evaluate when state.due_for_check is false", function()
    fake_state.due_for_check = function() return false end
    local fired = false
    register_rule({ action = function() fired = true end })
    engine.evaluate("r")
    assert.is_false(fired)
  end)

  it("force bypasses enabled/can_fire/due_for_check gates", function()
    engine.setup({ enabled = false, rules = {}, default_cooldown = 60, tick_interval = 60 })
    fake_state.can_fire = function() return false end
    fake_state.due_for_check = function() return false end
    local fired = false
    register_rule({ action = function() fired = true end })
    engine.evaluate("r", true)
    assert.is_true(fired)
  end)

  it("does not call state.mark_fired when force = true", function()
    local marked = false
    fake_state.mark_fired = function() marked = true end
    register_rule()
    engine.evaluate("r", true)
    assert.is_false(marked)
  end)

  it("contains a throwing condition without propagating the error", function()
    register_rule({ condition = function() error("boom") end })
    assert.has_no.errors(function() engine.evaluate("r") end)
  end)

  it("contains a throwing action without propagating the error", function()
    register_rule({ action = function() error("boom") end })
    assert.has_no.errors(function() engine.evaluate("r") end)
  end)

  it("clears _evaluating after a throwing condition, allowing re-evaluation", function()
    local calls = 0
    register_rule({
      condition = function()
        calls = calls + 1
        error("boom")
      end,
    })
    engine.evaluate("r")
    engine.evaluate("r")
    assert.are.equal(2, calls)
  end)

  it("ignores a second call to done from the same condition", function()
    local fire_count = 0
    register_rule({
      condition = function(_, done)
        done(true)
        done(true)
      end,
      action = function() fire_count = fire_count + 1 end,
    })
    engine.evaluate("r")
    assert.are.equal(1, fire_count)
  end)
end)
