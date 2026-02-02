# GitHub Menu Bar

A native macOS menu bar app for monitoring your GitHub activity.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Open PRs** — Track your pull requests with CI status, review progress, and conflict detection
- **Review Requests** — See PRs waiting for your review
- **Merged PRs** — Recently merged PRs with diff stats
- **Notifications** — GitHub notifications
- **Issues** — Your open issues with recent activity
- **Attention Indicators** — Visual cues for PRs needing attention (conflicts, CI failures)
- **PR Muting** — Mute noisy PRs; auto-unmute when someone @mentions you or leaves a review
- **Configurable** — Adjust refresh interval, notification window, and merged PR timeframe
- **Auto-refresh** — Configurable interval (default: 5 minutes)

## Requirements

- macOS 14.0 (Sonoma) or later
- [GitHub CLI](https://cli.github.com/) installed and authenticated

## Installation

### 1. Install GitHub CLI

```bash
brew install gh
gh auth login
```

### 2. Build and Install

```bash
# Using just (recommended)
just install

# Or manually
swift build -c release
```

### Build Commands

| Command | Description |
|---------|-------------|
| `just build` | Debug build |
| `just app` | Build .app bundle |
| `just run` | Build and run |
| `just install` | Install to ~/Applications |
| `just clean` | Clean build artifacts |

## Usage

1. Launch the app — it appears in your menu bar
2. Click the icon to see your GitHub activity
3. Click any item to open it in your browser

## How It Works

Uses the `gh` CLI instead of direct API calls:

- **No OAuth setup** — Uses your existing `gh auth` credentials
- **Rate limiting handled** — The CLI manages this automatically
- **Secure** — No tokens stored in the app

## Troubleshooting

**"GitHub authentication required"**
```bash
gh auth login
```

**App doesn't appear in menu bar**

Check Activity Monitor for existing instances.

**Data not updating**
```bash
gh auth status
```

## License

MIT
