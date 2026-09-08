Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **Agent permissions, per job.** Settings → Agent has separate pickers for fixing (defaults to asking) and reviewing (defaults to plan mode, so a review can't change anything), plus a free-text Extra arguments field applied to both.
- **The menu bar tells you when an agent needs you.** A small orange marker joins the three lights while any launched agent is waiting on input, alongside the row badge and notification.
- **Finding a pinned panel.** Clicking the dots while pinned raises the panel and pulses its edge instead of doing nothing, pulling it back on screen if it drifted off. "Bring Panel to the Menu Bar" moves it home without unpinning.
- **Repeat clicks no longer stack agent sessions** in the same worktree.
- **Commits shown per branch** (Settings → Sources, 1 to 10): see the last few commits on a followed branch and which one broke it.
- `curl http://127.0.0.1:47391/status.json` now reports agent arguments and running sessions.
