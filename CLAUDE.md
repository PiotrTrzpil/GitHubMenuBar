# GitHub Menu Bar

A native macOS menu bar app for GitHub activity. Uses GitHub CLI (`gh`) for authentication and data fetching.

## Prerequisites

- macOS 14.0+
- Xcode 15.2+
- GitHub CLI: `brew install gh && gh auth login`

## Build Commands

```bash
just run          # Debug build and run
just build        # Debug build only
just app          # Release .app bundle
just install      # Install to ~/Applications
just test         # Run tests
just clean        # Clean build artifacts
```

## Architecture

- **Swift 5.9 / SwiftUI** with `@Observable` and `@MainActor` for thread safety
- **Menu bar:** NSStatusItem with NSPanel (see `AppDelegate` in GitHubMenuBarApp.swift)
- **No external dependencies** - pure Swift + AppKit

## Code Organization

```
GitHubMenuBar/
├── GitHubMenuBarApp.swift  # Entry point, AppDelegate, menu bar setup
├── Models/                 # Data structures (Codable, Hashable, Identifiable)
├── Services/               # Business logic and state management
├── Views/                  # SwiftUI components
├── Theme/                  # Centralized colors
└── Utilities/              # Extensions
Tests/                      # XCTest unit tests
```

## Key Patterns

- **State:** Single `GitHubService` singleton holds `GitHubState`, injected via `@Environment`
- **Fetching:** `GitHubService+Fetching.swift` - calls gh CLI commands
- **Enrichment:** `GitHubService+Enrichment.swift` - adds detail via REST API
- **CLI wrapper:** `GitHubService+CLI.swift` - `runGH()` and `runGHJSON()` helpers
- **Concurrency:** Uses `async let` and `TaskGroup` for parallel operations
- **Persistence:** UserDefaults for settings, manager singletons for complex state

## Adding Code

- **New data:** Add model to `Models/`, fetch in `GitHubService+Fetching.swift`
- **New UI:** Add view to `Views/`, use existing row/section patterns
- **New colors:** Add to `Theme/AppColors.swift`
- **New settings:** Add UserDefaults key, update `SettingsView.swift`

## Testing

Unit tests in `Tests/` cover business logic only - no network calls required.
Run with `just test` or `swift test`.
