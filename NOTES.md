Signed and notarized by Apple. The **Update** button in the popover footer does the rest.

## Install or update

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/timmywheels/stoplight/main/install.sh)"
```

## What's new

- **Branch patterns resolved the wrong branch.** GitHub returns refs alphabetically, 100 per page, so `rc/*` on a busy repo only ever saw the oldest page. Stoplight now pages through every matching ref and picks the newest commit.
- **New row buttons reach existing configs.** Adversarial review never appeared if you'd customized your buttons before it shipped; actions added in a later version now join once, while anything you unchecked stays off.
- **A missing local clone reports itself** instead of silently hiding the Fix and Review buttons.
- **Commits shown per branch** (Settings → Sources, default 1, up to 10): see the last few commits on a followed branch and which one broke it.
- Agent picker reads "Coding agent" now that it does more than fix failures.
