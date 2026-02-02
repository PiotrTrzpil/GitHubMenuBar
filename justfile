# GitHub Menu Bar

# Build debug binary
build:
    swift build

# Build release .app bundle
app:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release

    APP="GitHub Menu Bar.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/GitHubMenuBar "$APP/Contents/MacOS/"

    cat > "$APP/Contents/Info.plist" << 'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>GitHubMenuBar</string>
        <key>CFBundleIdentifier</key>
        <string>com.local.GitHubMenuBar</string>
        <key>CFBundleName</key>
        <string>GitHub Menu Bar</string>
        <key>CFBundleVersion</key>
        <string>1.0.0</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>13.0</string>
        <key>LSUIElement</key>
        <true/>
        <key>NSHighResolutionCapable</key>
        <true/>
    </dict>
    </plist>
    EOF

    echo -n "APPL????" > "$APP/Contents/PkgInfo"
    echo "Built: $APP"

# Run debug binary
run: build
    .build/debug/GitHubMenuBar

# Install to ~/Applications
install: app
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -x GitHubMenuBar 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"GitHub Menu Bar.app"
    cp -R "GitHub Menu Bar.app" ~/Applications/
    echo "Installed to ~/Applications"

# Run unit tests (no gh auth required)
test:
    swift test --filter GitHubMenuBarTests

# Run integration tests (requires gh auth)
test-integration:
    swift test --filter IntegrationTests

# Run all tests
test-all:
    swift test

# Clean build artifacts
clean:
    rm -rf .build "GitHub Menu Bar.app"
