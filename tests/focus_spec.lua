local state = require("workflow-assistant.state")
local focus = require("workflow-assistant.focus")

describe("focus", function()
  before_each(function()
    state.setup({ state = { persist = false, path = "" } })
    focus.stop()
  end)

  after_each(function() focus.stop() end)

  it("is inactive by default", function() assert.is_false(focus.is_active()) end)

  it("start() with no duration turns it on indefinitely", function()
    focus.start()
    assert.is_true(focus.is_active())
    assert.is_nil(focus.remaining())
  end)

  it("start(duration) turns it on and reports remaining time", function()
    focus.start("10m")
    assert.is_true(focus.is_active())
    local r = focus.remaining()
    assert.is_true(r ~= nil and r > 0 and r <= 600)
  end)

  it("rejects an invalid duration and leaves focus mode untouched", function()
    local ok, err = focus.start("bogus")
    assert.is_nil(ok)
    assert.is_not_nil(err)
    assert.is_false(focus.is_active())
  end)

  it("stop() turns it off", function()
    focus.start()
    focus.stop()
    assert.is_false(focus.is_active())
  end)

  it("auto-expires once its duration has passed", function()
    focus.start("1s")
    focus._until = os.time() - 1 -- force it into the past instead of sleeping
    assert.is_false(focus.is_active())
  end)

  it("triggers state.notify_update() (e.g. a lualine refresh) on start and stop", function()
    local calls = 0
    state.setup({
      state = { persist = false, path = "" },
      on_update = function() calls = calls + 1 end,
    })
    focus.start()
    assert.are.equal(1, calls)
    focus.stop()
    assert.are.equal(2, calls)
  end)

  it("stopping when already inactive does not fire on_update again", function()
    local calls = 0
    state.setup({
      state = { persist = false, path = "" },
      on_update = function() calls = calls + 1 end,
    })
    focus.stop()
    assert.are.equal(0, calls)
  end)
end)
