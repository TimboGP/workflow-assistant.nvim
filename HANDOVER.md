## workflow-assistant.nvim — Claude Code Handover

**Audience:** Claude Code (or any coding agent) continuing this plugin.
**Date:** 2026-07-21
**Repo state:** working rule-engine skeleton, 17 files, ~990 lines of Lua, all
files parse under `luac5.1 -p`. No tests, no CI, no lint config yet.

Read this whole file before touching code. It contains invariants that are easy
to break with an innocent-looking refactor and expensive to debug (async context
bugs and cooldown regressions surface only at runtime, days later).

---

## 1. What this plugin is

A rule-engine assistant for Neovim that nudges the user about project hygiene —
commit, push, fetch/review incoming work, run tests, update tickets/docs,
validate against spec, chase TODOs, ad-hoc reminders. Rules are declarative data
+ two functions. The built-in rules are just the first tenants of a general
engine; the engine is the product.

Target: Neovim **>= 0.10** (`vim.system`, `vim.uv`). Runtime deps: `git`;
optional `ripgrep`. No Lua library dependencies (keep it that way unless a
backlog item explicitly adds one, and make it optional).

---

## 2. Current state (what already works)

- Full evaluation engine with per-rule gating, async conditions, failure
  isolation.
- Triggers: repeating libuv timer (`timer` rules) + autocmds (`event` rules) +
  manual (`:WorkflowAssistant check <name>`).
- State: `last_fired`/`snoozed_until` persisted to JSON in `stdpath("state")`;
  `last_checked` in-memory.
- Actions: `vim.notify`, interactive `vim.ui.select` prompt (auto-appends
  Snooze/Dismiss), async `run_cmd`.
- Async git layer over `vim.system`.
- Built-in rules: `uncommitted_changes`, `unpushed_commits`, `review_incoming`,
  `count_source_writes` (bookkeeping), `tests_stale`, `open_todos` (opt-in).
- Commands: `check|enable|disable|toggle|list|status|snooze|reset|tested` with
  completion. `:checkhealth workflow-assistant`.

See `README.md` for the user-facing surface and a custom-rule example.

---

## 3. File map

```
plugin/workflow-assistant.lua          load guard only
lua/workflow-assistant/
  init.lua        setup() + public API (also backs the command dispatcher)
  config.lua      defaults + vim.tbl_deep_extend merge
  engine.lua      registry + evaluate() with all gating; evaluate_matching()
  rule.lua        normalize()/validate a rule spec
  triggers.lua    libuv timer + autocmd wiring; schedules onto main loop
  context.lua     project-root detection (cached) + per-eval snapshot (ctx)
  state.lua       persisted (fired/snooze) + in-memory (checked) tracking
  actions.lua     notify / prompt / run_cmd / open_git_status
  git.lua         async git wrappers (is_repo, status, ahead_behind, ...)
  commands.lua    :WorkflowAssistant dispatcher + completion
  health.lua      :checkhealth entry
  rules/
    init.lua      build(cfg) -> concatenated list of built-in rule specs
    git.lua       git rule group
    tests.lua     tests rule group (holds a module-local write counter)
    todos.lua     todo rule group
```

---

## 4. Architecture / data flow

```
timer tick (every cfg.tick_interval)
  -> vim.schedule -> engine.evaluate_matching("timer")
autocmd (event)          -> engine.evaluate_matching("event", args.event)
:WorkflowAssistant check -> engine.evaluate(name, force=true)

engine.evaluate(name, force):
  guards (skipped when force):
    cfg.enabled? rule.enabled? state.can_fire (cooldown+snooze)?
    state.due_for_check (check_interval)?
  ctx = context.build(cfg)                      -- main loop
  if cfg.require_project and not ctx.is_project -> stop (unless force)
  state.mark_checked(name)
  rule.condition(ctx, done)  -- pcall'd
    done(should, payload):    -- called exactly once, sync or async
      if should: (mark_fired unless force) then rule.action(ctx,payload,rule) -- pcall'd
```

`ctx = { cwd, root, is_project, bufnr, bufname, filetype, now }`.

---

## 5. INVARIANTS — do not break these

These are the load-bearing guarantees. A refactor that violates one will appear
to work and fail intermittently in production.

1. **Condition contract.** `condition(ctx, done)` must call `done(should,
   payload)` **exactly once**, sync or async. The engine guards against a second
   call, but a condition that *never* calls `done` will silently wedge that rule
   (`_evaluating[name]` stays true forever). When adding async chains, ensure
   every branch — including error branches — reaches a single `done`.

2. **Main-loop safety.** Callbacks from `vim.uv` timers and `vim.system` run in
   a restricted "fast" context where most `vim.api`/`vim.fn` calls error. Any
   new async helper MUST `vim.schedule(...)` before touching the API and before
   invoking a caller-supplied callback. `git.run` and `actions.run_cmd` already
   do this — new async code must follow the same pattern. Rule authors rely on
   `git.*`/`run_cmd` callbacks and `ctx` being main-loop-safe; keep that true.

3. **Two independent throttles.** `check_interval` bounds how often the
   *condition* runs; `cooldown` bounds how often the rule may *notify*. Do not
   collapse them. Collapsing re-introduces the bug this split fixed: a rule
   whose condition is false (nothing to report) would re-run its expensive/
   network work every tick, e.g. `review_incoming` would `git fetch` every 60s.

4. **State scope split.** `last_fired`/`snoozed_until` persist to disk;
   `last_checked` is memory-only (avoids disk churn every tick). Do not persist
   `last_checked` and do not stop persisting the other two.

5. **Failure isolation.** `condition` and `action` are `pcall`-wrapped in
   `engine.evaluate`. Keep that. One broken rule must not break the engine or
   other rules.

6. **Rules are declarative.** A rule is data + `condition` + `action`. Per-rule
   mutable runtime state lives in `state.lua` (persisted) or as a documented
   module-local (see the write counter in `rules/tests.lua`). Don't stash state
   on the rule table or in engine internals.

7. **Event re-arming.** `triggers.wire_events()` clears the augroup and rebuilds
   it (re-adding the DirChanged cache-buster). It is idempotent and must stay
   so; registering a rule at runtime calls it. If you add always-on autocmds,
   re-add them inside `wire_events` after the clear, or they'll be wiped.

8. **No hard version pins to newer APIs without a fallback.** Avoid
   `vim.validate` (its signature changed across 0.11); use plain asserts.
   `vim.uv or vim.loop` is already the pattern. Keep 0.10 working.

---

## 6. Ground rules for working in this repo

- **Style:** 2-space indent; each module is `local M = {} ... return M`; prefer
  small pure helpers; comments explain *why*, not *what*.
- **No new runtime deps** unless a backlog item says so, and then make them
  optional (feature-detect, degrade gracefully — mirror how `open_todos`
  no-ops without `ripgrep`).
- **Update `README.md`** for any user-visible change (config keys, commands,
  rules) and **`health.lua`** when a new external dependency is introduced.
- **Every change ends green** on the verification loop below.

### Verification loop (run after every change)

```sh
# 1. Syntax — must pass for every file
find lua plugin -name '*.lua' -exec luac5.1 -p {} \;     # or any Lua 5.1 parser

# 2. Lint (add in P0 task below, then this becomes required)
luacheck lua/ plugin/

# 3. Format check
stylua --check lua/ plugin/

# 4. Tests (after P0 harness lands)
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
```

If `luac5.1` isn't installed: `apt-get install -y lua5.1` (or use any Lua 5.1
parser; Neovim's dialect is 5.1/LuaJIT — do not use 5.2+ syntax like `goto`,
integer-div `//`, or `<close>`).

---

## 7. Public / internal API reference (extend, don't reinvent)

Public (`require("workflow-assistant")`):
`setup(opts)`, `register(spec)`, `check(name)`, `check_all()`,
`enable(bool)`, `toggle()`, `snooze(name, seconds)`, `reset(name?)`,
`mark_tested()`, `rule_names()`, `show_list()`, `show_status()`.

`state`: `can_fire(rule)`, `due_for_check(rule)`, `mark_fired(name)`,
`mark_checked(name)`, `snooze(name,secs)`, `is_snoozed(name)`, `reset(name?)`,
`last_fired/last_checked(name)`.

`actions`: `notify(msg,level?)`, `prompt(rule,msg,choices)`,
`run_cmd(cwd,cmd,on_done)`, `open_git_status()`.
`choices` = list of `{ label=string, run=function }`.

`git`: `run(cwd,args,cb)`, `is_repo`, `branch`, `status`, `ahead_behind`,
`seconds_since_last_commit` — all callback-based, all main-loop-safe.

`context`: `build(cfg) -> ctx`, `find_root(start,markers)`, `clear_cache()`.

`engine`: `register(spec)`, `evaluate(name,force?)`,
`evaluate_matching(kind,event?,force?)`, `get(name)`, `list()`.

---

## 8. Backlog (prioritized, each item is a mini-spec)

Work top-down; P0 first so you can self-verify everything after.

### P0 — Tooling + test harness (do this first)

**Goal:** make the repo self-verifying so later work is safe.

Deliver:
- `.luacheckrc` with `globals = {"vim"}` (and busted globals `describe/it/before_each/assert` in `tests/`), `max_line_length = 100`, ignore unused `self`.
- `stylua.toml` (2-space, column width 100).
- `Makefile` targets: `check` (luac parse), `lint` (luacheck), `fmt` /
  `fmt-check` (stylua), `test` (plenary headless), `all`.
- `.github/workflows/ci.yml`: matrix on Neovim stable + nightly; runs
  `make lint fmt-check test`.
- `tests/minimal_init.lua` bootstrapping plenary onto `runtimepath`.
- `tests/` specs (busted style via plenary) covering:
  - `config.merge` deep-merges and preserves defaults.
  - `rule.normalize`: validation errors; enabled resolution
    (config override > spec default > true); default `cooldown`/`check_interval`.
  - `state`: `can_fire` respects cooldown + snooze; `due_for_check` respects
    `check_interval`; persistence round-trips; `reset`.
  - `engine.evaluate`: a fake rule with a synchronous `condition` fires its
    `action` only when gates allow; `force` bypasses gates; a throwing
    `condition`/`action` is contained (no error propagates) and clears
    `_evaluating`.

**Acceptance:** `make all` is green locally and in CI. Tests inject fakes for
`state`/`context` rather than hitting disk/git (use `package.loaded` overrides
in `before_each`).

**Gotchas:** tests need the `vim` global, so run under `nvim --headless`, not
bare Lua. `state` writes to `stdpath("state")` — point `cfg.state.path` at a
tmp file in tests and/or set `persist=false`.

---

### P1 — Ad-hoc reminders ("set reminders")

**Goal:** one-shot, user-set timed reminders, surviving restarts.

New `lua/workflow-assistant/reminders.lua`:
- `add(spec)` where `spec = { in_seconds=?, at=? (epoch), message, actions?=choices }`.
- Persist reminders in `state` (extend the persisted schema with a
  `reminders` list: `{ id, due, message }`). Generate `id` (e.g. `tostring(os.time())..counter`).
- A single scanning timer (reuse `tick_interval` or its own 30s timer) that, on
  tick, `vim.schedule`s and fires any reminder with `due <= now`, then removes
  it and saves. Do **not** create one libuv timer per reminder (leaks/complexity).
- On `setup`, load persisted reminders and start scanning.
- Parse relative durations for the command: `30m`, `2h`, `90s`, `1d` (a small
  `parse_duration(str) -> seconds` helper; reject unknown units clearly).

Commands: extend `commands.lua` + `init.lua` API:
`:WorkflowAssistant remind <duration> <message...>` and
`:WorkflowAssistant reminders` (list pending) and
`:WorkflowAssistant unremind <id>`.

**Acceptance:** set a reminder, restart Neovim, it still fires at the right
time; listing and cancelling work; specs cover `parse_duration` and the
due-scan logic (inject a fake clock).

**Gotchas:** keep firing on the main loop; don't fire a reminder twice if a tick
overlaps a slow `vim.ui` prompt (mark fired/remove before invoking the action).

---

### P1 — AI-driven rules (`rules/ai.lua`)

**Goal:** rules whose `condition` asks an LLM to judge project state. Off by
default; zero cost unless enabled and there's something to look at.

Design:
- Config block:
  ```lua
  ai = {
    enabled = false,
    model = "claude-haiku-4-5-20251001",
    api_key_env = "ANTHROPIC_API_KEY",   -- never store the key in config/state
    max_diff_bytes = 12000,              -- truncate context sent to the model
    min_interval = 30 * 60,              -- default check_interval for AI rules
  }
  ```
- HTTP via `vim.system({ "curl", "-s", "-X", "POST", ... })` to
  `https://api.anthropic.com/v1/messages` — no Lua HTTP dep. Read the key from
  `vim.env[cfg.ai.api_key_env]` at call time. If missing → rule no-ops (and
  `health.lua` warns when `ai.enabled`).
- Helper `ai.classify(prompt, cb)` that builds the request, runs curl async,
  `vim.schedule`s, parses JSON (`vim.json.decode`), and returns a structured
  result. Prompt the model to **reply with JSON only** (e.g.
  `{ "flag": true, "reason": "..." }`); strip stray fences before decoding;
  on any parse/HTTP error, `cb(nil)` and the rule stays silent.
- Every AI rule must gate cheaply *before* calling the API: only classify when
  there's a diff / relevant change, and set a long `check_interval` to bound
  token spend.

Ship these AI rules (all `enabled=false`):
- `spec_drift`: if the working diff touches code and a spec file exists
  (`SPEC.md`/`spec/`/configurable path), ask whether the change likely requires
  a spec update; fire with the reason.
- `docs_stale`: public API/signature changes in the diff but no docs touched →
  ask whether docs need updating.
- `commit_quality`: on staged diff, ask whether it's one logically complete
  commit or should be split; offer "Review (git status)".

**Acceptance:** with a fake `ai.classify` injected in tests, the rules fire on
`flag=true` and stay silent on `nil`/`false`; no API call happens when
`ai.enabled=false`, when the key is absent, or when there's no diff. The key
never appears in logs, `state`, or notifications.

**Gotchas:** never block the editor; enforce `max_diff_bytes` truncation; treat
all model output as untrusted (JSON-parse, don't `eval`, don't auto-run
suggested shell commands).

---

### P1 — Notification inbox + status surface

**Goal:** move from fire-and-forget to a queryable set of pending nudges, plus a
way to see them at a glance.

Introduce a lightweight **inbox** in `state` (in-memory is fine, persistence
optional): when a rule fires, record `{ id, rule, message, ts, actions }` as
"pending" until the user acts (run an action / dismiss / snooze). `actions.prompt`
should register/clear the inbox entry.

Then:
- `:WorkflowAssistant panel` — a floating window listing pending items and all
  rules (name, trigger, enabled, last_fired, snoozed_until) with keymaps:
  `<CR>` act, `s` snooze, `d` dismiss, `x` toggle-enable, `q` close.
- `require("workflow-assistant").statusline()` -> short string like
  `WA 3` (count of pending) for lualine/heirline; empty when zero.
- Optional backends, feature-detected: prefer `snacks.nvim` /`nvim-notify` for
  `actions.notify` and `fidget`/`snacks` for transient progress if present;
  fall back to `vim.notify`. Keep `vim.ui.select` as the default prompt but
  allow a configured picker.

**Acceptance:** firing a rule adds a pending item; acting/dismissing removes it;
panel reflects live state; `statusline()` returns the right count; no hard
dependency on any UI plugin.

**Gotchas:** this touches `actions.prompt` and the fire path in `engine` — keep
invariant #5 (isolation) and #1 (single `done`) intact. Don't leak inbox entries
when a rule fires repeatedly (dedupe by rule name).

---

### P2 — Non-AI "spec/docs" + generic "check xyz"

- `spec_or_docs_untouched` (pure git, cheap): if working-tree changes include
  files under a configured `src` glob but none under `spec`/`docs` globs, nudge.
  Complements the AI `spec_drift` for users without a key.
- `shell_rule` factory in a new `rules/shell.lua` and exposed as
  `require("workflow-assistant").shell_rule{ name, desc, cmd, cwd?="root",
  when = "nonzero" | "zero" | function(res)->bool, message = string|fn,
  choices? }`. Runs an arbitrary command via `run_cmd` and fires per `when`.
  This is the user-facing "check xyz" primitive — document it prominently.

**Acceptance:** `shell_rule` composes into `custom_rules`; specs cover the
`when` predicates with a fake `run_cmd`.

---

### P2 — Per-project state scoping (design decision)

Today state is keyed by rule name globally, so snoozing `unpushed_commits`
snoozes it in every repo. Decide and implement scoping by `(root, rule)`:
- Change `state` keys to `root .. "\0" .. name` (or nested table), thread `root`
  through `can_fire`/`mark_fired`/`snooze` (available via `ctx.root`).
- Migrate persisted files gracefully (accept old flat schema on load).
- Update `:WorkflowAssistant snooze/reset` to operate on the current root.

Write the tradeoff (global vs per-repo) at the top of the PR; default to
per-repo but keep a `state.scope = "global"|"project"` config escape hatch.

---

### P2 — Docs + polish

- `doc/workflow-assistant.txt` vimdoc with `:help` tags for setup, config,
  commands, and the rule-authoring contract (copy invariants #1–#3 verbatim —
  users writing rules need them).
- `health.lua`: warn when `ai.enabled` but key missing; note detected UI
  backends.
- Config validation with actionable error messages (bad rule spec → point at
  the offending `name`).

---

### P3 — Nice-to-haves

Telescope/snacks picker for rules; per-rule keymaps; a "focus mode" that
suppresses all nudges for N minutes; Atlassian/Jira ticket rule (the user has an
Atlassian connector — a rule that checks the branch's linked issue status is a
strong fit, via `jira` CLI or a configured hook).

---

## 9. Definition of done (every PR)

- All files parse; `luacheck` clean; `stylua --check` clean; tests pass
  (`make all`).
- New user-visible surface documented in `README.md` (and `doc/` once it exists).
- New external dep reflected in `health.lua` and degrades gracefully when absent.
- Invariants in section 5 preserved (call them out explicitly in the PR
  description if you touched `engine`, `triggers`, `state`, or `actions`).
- No new runtime dependency unless the backlog item authorized it and it's
  optional.

---

## 10. Suggested first session

1. Land **P0** (tooling + tests). Get `make all` green in CI. This is your
   safety net for everything after.
2. Land **ad-hoc reminders (P1)** — self-contained, high user value, exercises
   the persistence + timer paths without touching the engine core.
3. Land **AI rules (P1)** behind `ai.enabled=false`, with the fake-injected
   tests.
4. Then the **inbox/status surface (P1)** — do it after AI rules so the panel
   can display AI nudges too. This is the one that refactors the fire path;
   land it with the invariants fresh in mind.

Start by reading `engine.lua`, `state.lua`, `triggers.lua`, and one rule group
(`rules/git.lua`) end to end, then implement P0.
