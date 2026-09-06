Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **Crash fix.** Resizing the panel to full height with everything expanded could overflow the stack. Frame changes are now deferred and measurements guarded.
- **Merged PRs stop being red once the base branch is green again.** One rule for headers, footer, filters, dots, and widget.
- **Quieter headers.** Collapsed section counts are off by default; turn on "only what needs attention" or "every state" in Settings → General → Sections. Footer tooltip explains the tally.
- **First run opens the panel** after the first fetch, so the tour is seen.
