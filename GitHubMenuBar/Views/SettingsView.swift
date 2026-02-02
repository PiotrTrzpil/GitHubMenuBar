import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 5
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("notificationHours") private var notificationHours = 24
    @AppStorage("mergedDays") private var mergedDays = 3

    var body: some View {
        Form {
            Section {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
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
                Toggle("Show system notifications", isOn: $showNotifications)
                    .help("Show macOS notifications for new review requests")
            } header: {
                Text("Notifications")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub CLI")
                        .font(.headline)

                    Text("This app uses the `gh` CLI for GitHub access. Make sure you're authenticated:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open Terminal to authenticate") {
                        let script = """
                        tell application "Terminal"
                            activate
                            do script "gh auth login"
                        end tell
                        """
                        if let appleScript = NSAppleScript(source: script) {
                            var error: NSDictionary?
                            appleScript.executeAndReturnError(&error)
                        }
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("Authentication")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                Link("View on GitHub", destination: URL(string: "https://github.com")!)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 450)
    }
}

#Preview {
    SettingsView()
}
