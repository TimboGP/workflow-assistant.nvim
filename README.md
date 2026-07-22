# workflow-assistant.nvim

A rule-engine assistant for Neovim that reminds you about project hygiene —
commit, push, fetch/review incoming work, run tests, update docs, chase TODOs —
on timers and editor events. Rules are plain data + two functions, so the
built-ins are just the starting set; the engine is the point.

Requires Neovim >= 0.10 (`vim.system`). `git` and (optionally) `ripgrep` on PATH.

## Install (lazy.nvim)

```lua
{
  "you/workflow-assistant.nvim",
  event = "VeryLazy",
  opts = {
    -- everything here is optional; see lua/workflow-assistant/config.lua
    tick_interval = 60,
    git = { commit_after = 60 * 60, fetch_interval = 30 * 60, auto_fetch = true },
    tests = { command = { "make", "test" } },   -- enables a "Run tests" action
    rules = { open_todos = true },               -- opt into the noisier ones
  },
}
```

Or manually: `require("workflow-assistant").setup({ ... })`.

## Commands

```
:WorkflowAssistant check [rule]   -- force-run all (or one) rule now, ignoring cooldown
:WorkflowAssistant list           -- list rules + trigger + enabled state
:WorkflowAssistant status         -- on/off + rule count
:WorkflowAssistant enable|disable|toggle
:WorkflowAssistant snooze <rule> [minutes]
:WorkflowAssistant reset [rule]   -- clear fired/snooze state (all if omitted)
:WorkflowAssistant tested         -- reset the "writes since tests" counter
:checkhealth workflow-assistant
```

## Built-in rules

| name                  | trigger | fires when                                        |
| --------------------- | ------- | ------------------------------------------------- |
| `uncommitted_changes` | timer   | dirty tree + HEAD older than `git.commit_after`   |
| `unpushed_commits`    | timer   | local branch ahead of upstream                    |
| `review_incoming`     | timer   | `git fetch`, then upstream is ahead of you        |
| `count_source_writes` | event   | (bookkeeping only, `BufWritePost`)                |
| `tests_stale`         | timer   | >= `tests.remind_after_writes` writes since tested|
| `open_todos`          | timer   | >= `todos.threshold` TODO/FIXME markers (opt-in)  |

Disable any of them with `rules = { unpushed_commits = false }`.

## Writing a rule

A rule is a table with a `condition(ctx, done)` and an `action(ctx, payload, rule)`.
`condition` calls `done(should_fire, payload)` exactly once — sync or async.

```lua
require("workflow-assistant").setup({
  custom_rules = {
    {
      name = "update_ticket",
      desc = "Remind to update the ticket after a feature branch commit",
      trigger = "timer",
      check_interval = 10 * 60,  -- how often the condition runs
      cooldown = 60 * 60,        -- min gap between notifications
      condition = function(ctx, done)
        local git = require("workflow-assistant.git")
        git.branch(ctx.root, function(b)
          done(b ~= nil and b:match("^feature/") ~= nil, { branch = b })
        end)
      end,
      action = function(ctx, payload, rule)
        require("workflow-assistant.actions").prompt(rule,
          "On " .. payload.branch .. " — ticket up to date?",
          { { label = "Open ticket", run = function() vim.ui.open("https://...") end } })
        -- Snooze/Dismiss are appended automatically.
      end,
    },
  },
})
```

Register at runtime instead of via config with
`require("workflow-assistant").register(spec)` (re-arms event autocmds).

### The `ctx` table

`{ cwd, root, is_project, bufnr, bufname, filetype, now }`

### Triggers

- `timer` — evaluated every `tick_interval`, gated by the rule's `check_interval`.
- `event` — evaluated on the listed `events` (any autocmd event, e.g.
  `{ "BufWritePost", "FocusGained" }`).
- `manual` — only via `:WorkflowAssistant check <name>`.

### `check_interval` vs `cooldown`

Two independent throttles. `check_interval` bounds how often the (possibly
expensive/network) **condition** runs; `cooldown` bounds how often the rule may
**notify**. This is why `review_incoming` only `git fetch`es every 30 min even
though the timer ticks every minute.

## Architecture

```
init.lua        setup() + public API (also the command backend)
config.lua      defaults + deep-merge
engine.lua      registry + per-rule evaluation (cooldown/snooze/check gates, pcall isolation)
rule.lua        spec validation/normalization
triggers.lua    libuv timer + autocmds (schedules back onto the main loop)
context.lua     project-root detection (cached) + session snapshot
state.lua       last_fired/snoozed (persisted JSON) + last_checked (in-memory)
actions.lua     notify / interactive prompt / async run_cmd
git.lua         async git wrappers over vim.system
rules/*.lua     built-in rule groups
health.lua      :checkhealth
```

Async note: libuv timer and `vim.system` callbacks run in a restricted context,
so every callback re-enters the main loop via `vim.schedule` before touching the
API. Rule authors don't need to think about this — `ctx` is built on the main
loop and `git.*` / `actions.run_cmd` callbacks already land there.
