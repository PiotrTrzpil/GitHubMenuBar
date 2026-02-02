# Contributing

Thanks for your interest in contributing to GitHub Menu Bar!

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Ensure you have [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
4. Build the project with `just build` or `swift build`

## Development

### Requirements

- macOS 13.0+
- Xcode 15+ or Swift 5.9+
- GitHub CLI (`gh`)

### Build Commands

```bash
just build    # Debug build
just app      # Build .app bundle
just run      # Build and run
just test     # Run tests
just clean    # Clean build artifacts
```

## Submitting Changes

1. Create a branch for your changes
2. Make your changes with clear, descriptive commits
3. Test your changes locally
4. Open a pull request with a clear description of what you changed and why

## Code Style

- Follow existing code patterns and organization
- Use SwiftUI best practices
- Keep the UI simple and focused on the menu bar experience

## Reporting Issues

When reporting bugs, please include:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Output of `gh auth status`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
