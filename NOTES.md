Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **Finds `gh` wherever it lives.** Shell work now runs under your account's real login shell with the right flags for it (zsh, bash, fish), so anything your shell config puts on PATH is visible to Stoplight. Agent terminals land in that shell too.
- **Set the path yourself** when automatic can't work: Settings → General → Account has a GitHub CLI path field with a Choose… picker. Accepts the binary or its folder.
- `curl http://127.0.0.1:47391/status.json` reports the resolved `gh` path, so a teammate can tell you what their machine found.
