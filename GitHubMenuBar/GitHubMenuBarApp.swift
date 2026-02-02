import SwiftUI
import Combine

// MARK: - Constants

private enum Constants {
    static let menuBarIcon = "chevron.left.forwardslash.chevron.right"
    static let popoverSize = NSSize(width: 400, height: 500)
}

// MARK: - App

@main
struct GitHubMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings window - all UI is in the menu bar
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate

/// App delegate handles the menu bar status item and popover
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var statusItem: NSStatusItem = {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()

    private var popover: NSPopover?

    private var refreshTask: Task<Void, Never>?
    private var badgeSubscription: AnyCancellable?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupBadgeUpdates()

        // Hide dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Start fetching data
        refreshTask = Task {
            await GitHubService.shared.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        badgeSubscription?.cancel()
    }

    // MARK: - Setup

    @MainActor
    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: Constants.menuBarIcon,
            accessibilityDescription: "GitHub"
        )
        button.action = #selector(togglePopover)
        button.target = self
    }

    @MainActor
    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.contentSize = Constants.popoverSize
        newPopover.behavior = .transient // Automatically closes on outside click
        newPopover.animates = true
        newPopover.contentViewController = NSHostingController(
            rootView: MainMenuView()
                .environmentObject(GitHubService.shared)
        )
        popover = newPopover
    }

    @MainActor
    private func setupBadgeUpdates() {
        // Subscribe to state changes and update badge when review requests change
        badgeSubscription = GitHubService.shared.$state
            .map { $0.reviewRequests.count + $0.notifications.count }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateBadge(count: count)
            }
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Cancel any existing refresh and start a new one
            refreshTask?.cancel()
            refreshTask = Task {
                await GitHubService.shared.refresh()
            }
        }
    }

    // MARK: - Badge

    /// Update the menu bar icon with a badge count
    @MainActor
    private func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }

        if count > 0 {
            // Create attributed string with badge
            let attachment = NSTextAttachment()
            attachment.image = NSImage(
                systemSymbolName: Constants.menuBarIcon,
                accessibilityDescription: "GitHub"
            )

            let attrString = NSMutableAttributedString(attachment: attachment)
            attrString.append(NSAttributedString(string: " \(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.systemRed
            ]))

            button.attributedTitle = attrString
            button.image = nil
        } else {
            button.attributedTitle = NSAttributedString()
            button.image = NSImage(
                systemSymbolName: Constants.menuBarIcon,
                accessibilityDescription: "GitHub"
            )
        }
    }
}
