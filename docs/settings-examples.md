# settings.json Examples

Complete, copy-paste settings.json files. Replace `HOOKS_DIR` with the absolute path to your hooks directory — typically `~/.claude/hooks-lib/hooks` if you cloned this repo to `~/.claude/hooks-lib`.

**Quick replace:**
```bash
HOOKS_DIR=~/.claude/hooks-lib/hooks
sed "s|HOOKS_DIR|$HOOKS_DIR|g" example.json > ~/.claude/settings.json
```

---

## 1. Minimal

Just a completion notification. Drop this in and you have one useful behavior with zero risk.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

Swap `sound-complete.sh` for `macos-notify.sh`, `linux-notify.sh`, or `discord-notify.sh` depending on your platform and preference.

---

## 2. Developer Default

Notifications when done, secrets scanning on all writes and bash calls, basic git safety, TypeScript and JSON validation after edits. This is a reasonable starting point for solo developers.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/git/protect-main-branch.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/protect-dotenv.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/validate-json-yaml.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/tsc-check.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/sound-complete.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/cost/session-stats.sh"
          }
        ]
      }
    ]
  }
}
```

---

## 3. Security-Hardened

All security hooks active. Suitable for working on codebases that handle sensitive data, as a global config, or when onboarding Claude to an existing codebase where you don't fully know what's in it yet.

Every write and bash call goes through secrets scanning. Git operations are validated. Bash commands are audited against a blocklist. SSH key files and credential files are protected.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/bash-guard.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/git/protect-main-branch.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/protect-dotenv.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/protect-ssh-keys.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/protect-credentials.sh"
          }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/audit-file-reads.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/scan-bash-output.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/validate-json-yaml.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/session-audit-log.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

---

## 4. Full Quality

All quality hooks active. Context injection on every tool call so Claude knows the current state of the codebase. Suitable as a project-local `.claude/settings.json` on a codebase where you want Claude to self-correct after every edit.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/context/inject-git-context.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/context/inject-test-results.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/validate-json-yaml.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/prettier-gate.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/eslint-gate.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/tsc-check.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/python-lint.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/dart-analyze.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/context/inject-typescript-errors.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/context/session-summary.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

Note: the per-language linters (eslint, tsc, python, dart) each check the file extension before running, so having all of them active on `Write|Edit|MultiEdit` is safe — they self-filter.

---

## 5. Maximum Automation

Auto-format on every save, auto-run tests at session end, auto-commit staged changes, auto-update changelog. This is aggressive. Read the warnings.

**Warnings:**
- `auto-commit.sh` commits staged changes when Claude's session ends. Only enable this if you have a solid review process or are working in a personal branch.
- `auto-run-tests.sh` at session end adds latency before the session closes — can be several seconds on large test suites.
- `auto-changelog.sh` modifies `CHANGELOG.md` — can conflict with manual changelog edits.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/git/protect-main-branch.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/automation/auto-format-on-save.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/validate-json-yaml.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/eslint-gate.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/tsc-check.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/automation/auto-run-tests.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/automation/auto-changelog.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/automation/auto-commit.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

The Stop hooks run in order: tests first, then changelog (so test results can influence it), then commit (so both are included).

---

## 6. Team Setup

Slack notifications so the team sees when Claude finishes a task, conventional commit enforcement, full audit logging for compliance, and git safety rails. Use this as a project-local `.claude/settings.json` in a shared repo.

Requires: `SLACK_WEBHOOK_URL` exported in your shell environment (add to `~/.zshrc` or `~/.bashrc`).

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/bash-guard.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/git/protect-main-branch.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/cost/log-tool-usage.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/security/protect-dotenv.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/cost/log-tool-usage.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/validate-json-yaml.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/eslint-gate.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/quality/tsc-check.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/git/validate-commit-message.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash HOOKS_DIR/cost/session-timer.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/cost/daily-usage-report.sh"
          },
          {
            "type": "command",
            "command": "bash HOOKS_DIR/notifications/slack-notify.sh"
          }
        ]
      }
    ]
  }
}
```

**Slack notification setup:**

```bash
# Add to ~/.zshrc or ~/.bashrc
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
export SLACK_CHANNEL="#claude-activity"   # optional, depends on hook implementation
```

The `slack-notify.sh` hook reads `SLACK_WEBHOOK_URL` from the environment and posts a message with the session ID and a brief summary when Claude finishes.

---

## Path Setup Reference

All examples above use `HOOKS_DIR` as a placeholder. Here are the common path configurations:

| Setup | `HOOKS_DIR` value |
|-------|------------------|
| Cloned to `~/.claude/hooks-lib` | `~/.claude/hooks-lib/hooks` |
| Cloned to `~/repos/awesome-claude-hooks` | `~/repos/awesome-claude-hooks/hooks` |
| Individual scripts in `~/.claude/hooks` | `~/.claude/hooks` |

You can also set `HOOKS_DIR` as a shell variable and generate your settings file:

```bash
export HOOKS_DIR=~/.claude/hooks-lib/hooks

cat > ~/.claude/settings.json << EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash $HOOKS_DIR/notifications/sound-complete.sh"}
        ]
      }
    ]
  }
}
EOF
```

Note: shell variable expansion in `settings.json` doesn't happen at runtime — the path must be literal in the file. The `~` shorthand is expanded by the shell, so it works. `$HOOKS_DIR` in the file itself won't expand.
