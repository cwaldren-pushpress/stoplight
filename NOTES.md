Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **One agent terminal per PR.** Launching Fix or Review again focuses the window that's already open instead of starting another, and it survives a Stoplight restart. Liveness comes from the window's own shell, so a window killed abruptly still reads as closed.
- **Click the agent badge to jump to that terminal.** Terminal and iTerm raise the exact window by title; Ghostty and Warp bring the app forward (they have no scripting API).
- **Dismiss the badge** from the row's right-click menu, which also has "Show agent terminal".
- Badges for closed windows clear on the next poll; live sessions restore their badge after a restart.
