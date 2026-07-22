-- Configuration: defaults + user merge.
local M = {}

M.defaults = {
  -- Master switch. Rules never fire while this is false.
  enabled = true,

  -- Default gap (seconds) between two *notifications* from the same rule.
  default_cooldown = 30 * 60,

  -- How often the background timer wakes up to evaluate `timer` rules.
  tick_interval = 60,

  -- Only evaluate rules when the cwd is inside a detected project.
  require_project = false,

  -- Markers used to detect the project root (walked upward from cwd).
  root_markers = { ".git", ".hg", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" },

  notify = {
    title = "Workflow",
    level = vim.log.levels.INFO,
  },

  -- Persist last_fired / snoozed_until across sessions.
  state = {
    persist = true,
    path = vim.fn.stdpath("state") .. "/workflow-assistant.json",
  },

  -- Per-rule enable/disable overrides by name. nil = use the rule's own default.
  -- e.g. rules = { open_todos = true, review_incoming = false }
  rules = {},

  -- Tuning knobs consumed by built-in rule groups.
  git = {
    commit_after = 60 * 60,   -- nag about a dirty tree once HEAD is older than this
    fetch_interval = 30 * 60, -- how often review_incoming runs `git fetch`
    auto_fetch = true,        -- review_incoming fetches before checking "behind"
  },
  tests = {
    filetypes = { "lua", "python", "go", "rust", "javascript", "typescript",
      "java", "c", "cpp", "ruby" },
    remind_after_writes = 10, -- writes since last test run before nudging
    command = nil,            -- e.g. { "make", "test" }; enables a "Run tests" action
  },
  todos = {
    patterns = { "TODO", "FIXME", "HACK", "XXX" },
    threshold = 1,
  },

  -- User-supplied rule specs (see README). Registered after built-ins.
  custom_rules = {},
}

function M.merge(user)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user or {})
end

return M
