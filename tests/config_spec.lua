local config = require("workflow-assistant.config")

describe("config.merge", function()
  it("returns the defaults when called with no overrides", function()
    local cfg = config.merge(nil)
    assert.are.equal(60, cfg.tick_interval)
    assert.is_true(cfg.enabled)
    assert.are.same(
      { ".git", ".hg", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" },
      cfg.root_markers
    )
  end)

  it("deep-merges nested tables without dropping sibling defaults", function()
    local cfg = config.merge({ git = { commit_after = 10 } })
    assert.are.equal(10, cfg.git.commit_after)
    assert.are.equal(30 * 60, cfg.git.fetch_interval)
    assert.is_true(cfg.git.auto_fetch)
  end)

  it("overrides top-level scalars", function()
    local cfg = config.merge({ enabled = false })
    assert.is_false(cfg.enabled)
  end)

  it("does not mutate the shared defaults across calls", function()
    config.merge({ tick_interval = 999 })
    local cfg = config.merge(nil)
    assert.are.equal(60, cfg.tick_interval)
  end)
end)
