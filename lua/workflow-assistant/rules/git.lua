-- Git-centric built-in rules: uncommitted changes, unpushed commits,
-- and "fetch + review incoming work".
local git = require("workflow-assistant.git")
local actions = require("workflow-assistant.actions")

local M = {}

local function short(root) return vim.fn.fnamemodify(root, ":t") end

function M.rules(cfg)
  local commit_after = cfg.git.commit_after

  return {
    {
      name = "uncommitted_changes",
      desc = "Uncommitted changes have sat for a while",
      trigger = "timer",
      check_interval = 5 * 60,
      cooldown = 45 * 60,
      condition = function(ctx, done)
        git.is_repo(ctx.root, function(is)
          if not is then return done(false) end
          git.status(ctx.root, function(lines)
            if not lines or #lines == 0 then return done(false) end
            git.seconds_since_last_commit(ctx.root, function(secs)
              -- nil = no commits yet -> worth a nudge.
              if secs == nil or secs > commit_after then
                done(true, { dirty = #lines })
              else
                done(false)
              end
            end)
          end)
        end)
      end,
      action = function(ctx, payload, rule)
        actions.prompt(
          rule,
          ("%d uncommitted change(s) in %s"):format(payload.dirty, short(ctx.root)),
          {
            { label = "Review (git status)", run = actions.open_git_status },
            {
              label = "Stage all + commit",
              run = function()
                actions.run_cmd(ctx.root, { "git", "add", "-A" }, function()
                  vim.ui.input({ prompt = "Commit message: " }, function(msg)
                    if not msg or msg == "" then return end
                    actions.run_cmd(ctx.root, { "git", "commit", "-m", msg }, function(res)
                      local okc = res.code == 0
                      actions.notify(
                        okc and "Committed." or ("Commit failed: " .. (res.stderr or "")),
                        okc and vim.log.levels.INFO or vim.log.levels.ERROR
                      )
                    end)
                  end)
                end)
              end,
            },
          }
        )
      end,
    },

    {
      name = "unpushed_commits",
      desc = "Local commits are ahead of upstream",
      trigger = "timer",
      check_interval = 5 * 60,
      cooldown = 30 * 60,
      condition = function(ctx, done)
        git.is_repo(ctx.root, function(is)
          if not is then return done(false) end
          git.ahead_behind(ctx.root, function(ab)
            if ab and ab.ahead > 0 then
              done(true, ab)
            else
              done(false)
            end
          end)
        end)
      end,
      action = function(ctx, payload, rule)
        actions.prompt(rule, ("%d commit(s) not pushed"):format(payload.ahead), {
          {
            label = "Push now",
            run = function()
              actions.run_cmd(ctx.root, { "git", "push" }, function(res)
                local okp = res.code == 0
                actions.notify(
                  okp and "Pushed." or ("Push failed: " .. (res.stderr or "")),
                  okp and vim.log.levels.INFO or vim.log.levels.ERROR
                )
              end)
            end,
          },
        })
      end,
    },

    {
      name = "review_incoming",
      desc = "Fetch and review incoming upstream work",
      trigger = "timer",
      check_interval = cfg.git.fetch_interval,
      cooldown = cfg.git.fetch_interval,
      condition = function(ctx, done)
        git.is_repo(ctx.root, function(is)
          if not is then return done(false) end
          local check = function()
            git.ahead_behind(ctx.root, function(ab)
              if ab and ab.behind > 0 then
                done(true, ab)
              else
                done(false)
              end
            end)
          end
          if cfg.git.auto_fetch then
            git.run(ctx.root, { "fetch", "--quiet" }, function() check() end)
          else
            check()
          end
        end)
      end,
      action = function(ctx, payload, rule)
        actions.prompt(
          rule,
          ("%d incoming commit(s) upstream — review before continuing"):format(payload.behind),
          {
            {
              label = "Show incoming log",
              run = function()
                if not pcall(vim.cmd, "Git log --oneline HEAD..@{upstream}") then
                  actions.notify("git log HEAD..@{upstream} to inspect incoming commits.")
                end
              end,
            },
            {
              label = "Pull (rebase)",
              run = function()
                actions.run_cmd(ctx.root, { "git", "pull", "--rebase" }, function(res)
                  local okp = res.code == 0
                  actions.notify(
                    okp and "Pulled (rebased)." or ("Pull failed: " .. (res.stderr or "")),
                    okp and vim.log.levels.INFO or vim.log.levels.ERROR
                  )
                end)
              end,
            },
          }
        )
      end,
    },
  }
end

return M
