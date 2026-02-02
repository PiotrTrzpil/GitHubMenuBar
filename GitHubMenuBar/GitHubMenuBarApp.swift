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
    static private(set) var shared: AppDelegate!

    private lazy var statusItem: NSStatusItem = {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()

    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var colorPreviewWindow: NSWindow?

    private var refreshTask: Task<Void, Never>?
    private var badgeSubscription: AnyCancellable?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

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
        // Subscribe to state and muted PRs changes, excluding muted items from badge count
        badgeSubscription = Publishers.CombineLatest(
            GitHubService.shared.$state,
            GitHubService.shared.$mutedPRIds
        )
        .map { state, mutedIds in
            // Count review requests (incoming reviews can't be muted)
            let reviewCount = state.reviewRequests.count

            // Count open PRs needing attention, excluding muted ones
            let unmutedAttentionPRs = state.openPRs.filter {
                $0.needsAttention == true && !mutedIds.contains($0.id)
            }.count

            // Note: notifications intentionally don't affect the badge
            return reviewCount + unmutedAttentionPRs
        }
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
        }
    }

    // MARK: - Settings Window

    @MainActor
    func showSettings() {
        // Close popover first
        popover?.performClose(nil)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let fittingSize = hostingView.fittingSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GitHub Menu Bar Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Color Preview (DevMode)

    @MainActor
    func showColorPreview() {
        popover?.performClose(nil)

        if let window = colorPreviewWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: ColorPreviewView())
        let fittingSize = hostingView.fittingSize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Color Preview (DevMode)"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        colorPreviewWindow = window
    }

    // MARK: - Badge

    private var dotView: NSView?

    /// Update the menu bar icon with a notification dot
    @MainActor
    private func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }

        // Always set the template icon
        button.image = NSImage(
            systemSymbolName: Constants.menuBarIcon,
            accessibilityDescription: "GitHub"
        )

        if count > 0 {
            // Add orange dot if not already present
            if dotView == nil {
                let dot = NSView(frame: NSRect(x: button.bounds.width - 8, y: button.bounds.height - 8, width: 6, height: 6))
                dot.wantsLayer = true
                dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                dot.layer?.cornerRadius = 3
                button.addSubview(dot)
                dotView = dot
            }
            dotView?.isHidden = false
        } else {
            // Hide the dot
            dotView?.isHidden = true
        }
    }
}
