import ServiceManagement
import SwiftUI

// MARK: - CLI Status

enum CLIStatus {
    case notFound
    case notAuthenticated(path: String)
    case authenticated(path: String, user: String)

    static func check() -> CLIStatus {
        guard let ghPath = GitHubCLI.path else {
            return .notFound
        }

        // Check auth status
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                // Parse username from output like "Logged in to github.com account username"
                if let match = output.range(of: "account ([\\w-]+)", options: .regularExpression) {
                    let accountPart = output[match]
                    let username = accountPart.replacingOccurrences(of: "account ", with: "")
                    return .authenticated(path: ghPath, user: username)
                }
                return .authenticated(path: ghPath, user: "unknown")
            } else {
                return .notAuthenticated(path: ghPath)
            }
        } catch {
            return .notAuthenticated(path: ghPath)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 5
    @AppStorage("notificationHours") private var notificationHours = 24
    @AppStorage("mergedDays") private var mergedDays = 3

    // Auto-unmute settings
    @AppStorage("autoUnmuteOnActivity") private var autoUnmuteOnActivity = true
    @AppStorage("autoUnmuteOnlyHumans") private var autoUnmuteOnlyHumans = true
    @AppStorage("autoUnmuteOnlyMentions") private var autoUnmuteOnlyMentions = true

    @State private var cliStatus: CLIStatus = .notFound
    @State private var isCheckingStatus = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Start at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
            } header: {
                Text("General")
            }

            Section {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }

                Picker("Show merged PRs from last", selection: $mergedDays) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                }

                Picker("Show notifications from last", selection: $notificationHours) {
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                    Text("48 hours").tag(48)
                }
            } header: {
                Text("Data")
            }

            Section {
                Toggle("Auto-unmute on new activity", isOn: $autoUnmuteOnActivity)
                    .help("Automatically unmute PRs when there's new activity")

                if autoUnmuteOnActivity {
                    Toggle("Only human activity", isOn: $autoUnmuteOnlyHumans)
                        .help("Don't unmute for bot comments or reviews")
                        .padding(.leading, 16)

                    Toggle("Only @mentions", isOn: $autoUnmuteOnlyMentions)
                        .help("Only unmute when someone mentions you in a comment")
                        .padding(.leading, 16)
                }
            } header: {
                Text("Muted PRs")
            }

            Section {
                if isCheckingStatus {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking GitHub CLI...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    switch cliStatus {
                    case .notFound:
                        cliNotFoundView

                    case .notAuthenticated(let path):
                        cliNotAuthenticatedView(path: path)

                    case .authenticated(let path, let user):
                        cliAuthenticatedView(path: path, user: user)
                    }
                }
            } header: {
                Text("GitHub CLI")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            checkCLIStatus()
        }
    }

    // MARK: - CLI Status Views

    private var cliNotFoundView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("GitHub CLI not found", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.error)

            Text("Install the GitHub CLI to use this app:")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Install with Homebrew") {
                let script = """
                tell application "Terminal"
                    activate
                    do script "brew install gh && gh auth login"
                end tell
                """
                runAppleScript(script)
            }
            .padding(.top, 4)
        }
    }

    private func cliNotAuthenticatedView(path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not authenticated", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundColor(AppColors.warning)

            HStack {
                Text("CLI path:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            Button("Authenticate") {
                let script = """
                tell application "Terminal"
                    activate
                    do script "gh auth login"
                end tell
                """
                runAppleScript(script)
            }
            .padding(.top, 4)

            Button("Refresh Status") {
                checkCLIStatus()
            }
            .font(.caption)
        }
    }

    private func cliAuthenticatedView(path: String, user: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Authenticated as @\(user)", systemImage: "checkmark.circle.fill")
                .foregroundColor(AppColors.success)

            HStack {
                Text("CLI path:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func checkCLIStatus() {
        isCheckingStatus = true
        DispatchQueue.global(qos: .userInitiated).async {
            let status = CLIStatus.check()
            DispatchQueue.main.async {
                self.cliStatus = status
                self.isCheckingStatus = false
            }
        }
    }

    private func runAppleScript(_ script: String) {
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // If registration fails, revert the toggle
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

#Preview {
    SettingsView()
}
