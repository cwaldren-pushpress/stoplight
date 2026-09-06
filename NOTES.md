Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **Adversarial review.** A row button (and ⇧⌘F) hands the PR to your agent with a review prompt: severity-ordered findings, file:line, no code changes. Editable in Settings → Agent.
- **Agent callbacks.** Claude Code launches get per-worktree hooks; the row shows *agent working*, *needs you*, or *agent done*, and you get a notification. Other agents get the two `open stoplight://…` commands in their prompt.
- **Fix a red branch.** On a followed branch that's red, Fix forks a fresh branch off it in a worktree and asks the agent to open a PR.
- **Search, GitHub-style.** ⌘L: bare words, `author:` `repo:` `branch:` `is:red` `#n`, with completion chips. Author matches login, display name, or your label.
- **Branch patterns.** Follow `owner/repo@rc/*` and Stoplight tracks the newest release branch, lists PRs targeting it, and notifies when a new one is cut.
- **Merged rows** show a `⑂ main` badge colored by the base branch's current CI, in GitHub's merged purple.
- **Panel:** drag from the top handle, pin (top-right), collapse-all toggle, fits its content, dividers span the width, buttons wrap on narrow widths, footer adapts.
- **Reliability:** removed an App Group file write that could freeze the app; failed fetches retry in 15s; `curl http://127.0.0.1:47391/status.json` for diagnostics.
- Copy commit hash, configurable row buttons, Esc in text fields, and a long tail of fixes.
