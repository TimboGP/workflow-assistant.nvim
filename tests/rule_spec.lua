local rule = require("workflow-assistant.rule")

local function noop() end

describe("rule.normalize", function()
  local cfg

  before_each(function() cfg = { rules = {}, default_cooldown = 1800, tick_interval = 60 } end)

  it("requires a table spec", function()
    assert.has_error(function() rule.normalize("nope", cfg) end)
  end)

  it("requires a name", function()
    assert.has_error(function() rule.normalize({ condition = noop, action = noop }, cfg) end)
  end)

  it("requires a condition function", function()
    assert.has_error(function() rule.normalize({ name = "x", action = noop }, cfg) end)
  end)

  it("requires an action function", function()
    assert.has_error(function() rule.normalize({ name = "x", condition = noop }, cfg) end)
  end)

  it("rejects an invalid trigger", function()
    assert.has_error(
      function()
        rule.normalize({ name = "x", trigger = "bogus", condition = noop, action = noop }, cfg)
      end
    )
  end)

  it("defaults cooldown/check_interval from cfg", function()
    local r = rule.normalize({ name = "x", condition = noop, action = noop }, cfg)
    assert.are.equal(1800, r.cooldown)
    assert.are.equal(60, r.check_interval)
  end)

  it("lets a spec override cooldown/check_interval", function()
    local r = rule.normalize(
      { name = "x", condition = noop, action = noop, cooldown = 5, check_interval = 7 },
      cfg
    )
    assert.are.equal(5, r.cooldown)
    assert.are.equal(7, r.check_interval)
  end)

  describe("enabled resolution", function()
    it("defaults to true with no spec.enabled and no override", function()
      local r = rule.normalize({ name = "x", condition = noop, action = noop }, cfg)
      assert.is_true(r.enabled)
    end)

    it("honors spec.enabled = false", function()
      local r =
        rule.normalize({ name = "x", condition = noop, action = noop, enabled = false }, cfg)
      assert.is_false(r.enabled)
    end)

    it("config override wins over spec.enabled", function()
      cfg.rules.x = true
      local r =
        rule.normalize({ name = "x", condition = noop, action = noop, enabled = false }, cfg)
      assert.is_true(r.enabled)
    end)

    it("config override can disable a spec that defaults enabled", function()
      cfg.rules.x = false
      local r = rule.normalize({ name = "x", condition = noop, action = noop }, cfg)
      assert.is_false(r.enabled)
    end)
  end)
end)
