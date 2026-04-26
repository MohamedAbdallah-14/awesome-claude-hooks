# Automation Hooks

These hooks reduce the repetitive manual steps that happen after Claude writes code: formatting, testing, committing, pushing, and keeping housekeeping files in sync. Each hook fires automatically when Claude uses a write or stop event, so you get the action without having to issue a follow-up prompt.

## Opt-in vs opt-out

Hooks that **mutate your git history or push code** are **opt-in** (disabled by default). You must set an environment variable to turn them on. This prevents surprise commits on repositories where you haven't decided to trust the automation.

Hooks that **only format files** are **opt-out** (enabled by default). They are low-risk, reversible, and consistent with normal editor behavior.

| Hook | Event | Trigger | What it does | Default |
|---|---|---|---|---|
| `auto-prettier.sh` | PostToolUse | Write/Edit/MultiEdit on JS/TS/CSS/JSON/MD | Runs `prettier --write` on the file | **ON** (opt-out) |
| `auto-format-on-save.sh` | PostToolUse | Write/Edit/MultiEdit on any supported type | Runs the language-appropriate formatter (prettier, black, gofmt, dart format, rustfmt, shfmt) | **ON** (opt-out) |
| `auto-run-tests.sh` | PostToolUse | Write/Edit/MultiEdit on source files | Finds the related test file and runs it | **OFF** (`CLAUDE_AUTO_TEST_ENABLED=1`) |
| `auto-git-commit.sh` | Stop | Session ends with file changes | Stages modified tracked files and commits with a `claude:` message | **OFF** (`CLAUDE_AUTO_COMMIT=1`) |
| `auto-push.sh` | Stop | Session ends; last commit is a `claude:` commit | Pushes current branch to upstream | **OFF** (`CLAUDE_AUTO_PUSH=1`) |
| `auto-changelog.sh` | Stop | Session ends with file changes | Appends a dated entry to CHANGELOG.md | **OFF** (`CLAUDE_AUTO_CHANGELOG=1`) |
| `auto-update-readme.sh` | PostToolUse | Write/Edit on package.json / pubspec.yaml / pyproject.toml / Cargo.toml | Updates version badges and `version:` lines in README.md | **OFF** (`CLAUDE_AUTO_UPDATE_README=1`) |

## Settings.json snippet

Add the hooks you want under your `~/.claude/settings.json` or project `.claude/settings.json`. The example below enables all seven. Remove any you don't want.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-prettier.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-format-on-save.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-run-tests.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-update-readme.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-git-commit.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-push.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/automation/auto-changelog.sh"
          }
        ]
      }
    ]
  },
  "env": {
    "CLAUDE_AUTO_TEST_ENABLED": "1",
    "CLAUDE_AUTO_COMMIT": "1",
    "CLAUDE_AUTO_PUSH": "1",
    "CLAUDE_AUTO_CHANGELOG": "1",
    "CLAUDE_AUTO_UPDATE_README": "1"
  }
}
```

Replace `/path/to/hooks` with the absolute path to the directory where you cloned this repo.

## Configuration reference

### auto-prettier.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_PRETTIER_SKIP_PATTERNS` | `node_modules:dist:build:.next:vendor` | Colon-separated path fragments to skip |

### auto-format-on-save.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTOFORMAT_ENABLED` | `1` | Set to `0` to disable entirely |
| `CLAUDE_AUTOFORMAT_SKIP_TYPES` | _(none)_ | Colon-separated extensions to skip, e.g. `py:rs` |

### auto-run-tests.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_TEST_ENABLED` | `0` | Set to `1` to enable |
| `CLAUDE_AUTO_TEST_TIMEOUT` | `60` | Seconds before the test run is killed |

### auto-git-commit.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_COMMIT` | `0` | Set to `1` to enable |
| `CLAUDE_AUTO_COMMIT_BRANCH_PROTECTION` | `main master` | Space-separated branches to never commit on |

### auto-push.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_PUSH` | `0` | Set to `1` to enable |
| `CLAUDE_AUTO_PUSH_PROTECTED` | `main master` | Space-separated branches to never push |

### auto-changelog.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_CHANGELOG` | `0` | Set to `1` to enable |
| `CLAUDE_CHANGELOG_FILE` | `{repo_root}/CHANGELOG.md` | Override the changelog path |

### auto-update-readme.sh

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_UPDATE_README` | `0` | Set to `1` to enable |

## Warning

Test automation hooks on a dev branch before enabling them on any repository with a CI/CD pipeline or protected branch rules. The git-commit and push hooks in particular will create real commits and push to your remote. Enable them only after you have verified the behavior on a throwaway branch.

`auto-format-on-save` and `auto-prettier` are safe to enable immediately — they only modify the file Claude just wrote, and the change is visible in your working tree before any commit.
