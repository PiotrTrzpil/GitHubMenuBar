import SwiftUI

// MARK: - Constants

private enum Constants {
    static let menuBarIcon = "chevron.left.forwardslash.chevron.right"
    static let mainPanelWidth: CGFloat = 400
    static let previewPanelWidth: CGFloat = 320
    static let dividerWidth: CGFloat = 1
    static let panelHeight: CGFloat = 500
    static let menuBarPadding: CGFloat = 4
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

/// App delegate handles the menu bar status item and panel
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    private lazy var statusItem: NSStatusItem = {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()

    private var menuPanel: MenuPanel?
    private var settingsWindow: NSWindow?
    private var colorPreviewWindow: NSWindow?
    private var eventMonitor: Any?

    private var refreshTask: Task<Void, Never>?
    private var badgeObservationTask: Task<Void, Never>?

    /// The fixed X position for the panel's left edge (set when first shown)
    private var panelLeftEdgeX: CGFloat?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        registerDefaults()
        setupStatusItem()
        setupPanel()
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
        badgeObservationTask?.cancel()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "soundEnabled": true,
            "soundNewReviewRequest": true,
            "soundCIFailure": true,
            "soundPRApproved": true,
            "soundNewMention": true,
        ])
    }

    @MainActor
    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: Constants.menuBarIcon,
            accessibilityDescription: "GitHub"
        )
        button.action = #selector(togglePanel)
        button.target = self
    }

    @MainActor
    private func setupPanel() {
        let panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.mainPanelWidth, height: Constants.panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.transient, .ignoresCycle]

        let hostingView = NSHostingView(
            rootView: PanelContentView()
                .environment(GitHubService.shared)
        )
        panel.contentView = hostingView

        menuPanel = panel
    }

    @MainActor
    private func setupBadgeUpdates() {
        // Use observation tracking to react to state and muted PRs changes
        badgeObservationTask = Task { @MainActor [weak self] in
            var lastCount = -1
            while !Task.isCancelled {
                let count = withObservationTracking {
                    let service = GitHubService.shared
                    // Count review requests (incoming reviews can't be muted)
                    let reviewCount = service.state.reviewRequests.count

                    // Count open PRs needing attention, excluding muted ones
                    let unmutedAttentionPRs = service.state.openPRs.filter {
                        $0.needsAttention == true && !service.mutedPRIds.contains($0.id)
                    }.count

                    // Note: notifications intentionally don't affect the badge
                    return reviewCount + unmutedAttentionPRs
                } onChange: {
                    // This closure is called when any observed property changes
                }

                // Only update badge if count changed (like removeDuplicates)
                if count != lastCount {
                    self?.updateBadge(count: count)
                    lastCount = count
                }

                // Wait for the next change notification
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Actions

    @MainActor
    @objc private func togglePanel() {
        guard let panel = menuPanel else { return }

        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    @MainActor
    private func showPanel() {
        guard let panel = menuPanel, let button = statusItem.button else { return }

        // Get the button's position in screen coordinates
        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        // Get the screen that contains the button
        let screen = NSScreen.screens.first { $0.frame.contains(buttonFrameOnScreen.origin) } ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        // Calculate the full width when preview is expanded
        let fullWidth = Constants.mainPanelWidth + Constants.dividerWidth + Constants.previewPanelWidth

        // Ideal position: main panel right-aligned with button
        var mainPanelX = buttonFrameOnScreen.maxX - Constants.mainPanelWidth

        // Check if full panel would go off the right edge of the screen
        let rightEdgeWhenExpanded = mainPanelX + fullWidth
        if rightEdgeWhenExpanded > screenFrame.maxX {
            // Shift left so the expanded panel fits on screen
            mainPanelX = screenFrame.maxX - fullWidth
        }

        // Also ensure the panel doesn't go off the left edge
        if mainPanelX < screenFrame.minX {
            mainPanelX = screenFrame.minX
        }

        let panelY = buttonFrameOnScreen.minY - Constants.panelHeight - Constants.menuBarPadding

        // Store the left edge position so preview can expand to the right
        panelLeftEdgeX = mainPanelX

        // Set initial frame (main panel only)
        panel.setFrame(
            NSRect(x: mainPanelX, y: panelY, width: Constants.mainPanelWidth, height: Constants.panelHeight),
            display: true
        )

        panel.makeKeyAndOrderFront(nil)

        // Set up event monitor to close panel when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanel()
        }
    }

    @MainActor
    func closePanel() {
        menuPanel?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        // Reset hover state
        GitHubService.shared.state.previewState.hoveredPRId = nil
        panelLeftEdgeX = nil
    }

    // MARK: - Settings Window

    @MainActor
    func showSettings() {
        // Close panel first
        closePanel()

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()

        settingsWindow = window
    }

    // MARK: - Color Preview (DevMode)

    @MainActor
    func showColorPreview() {
        closePanel()

        if let window = colorPreviewWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()

        colorPreviewWindow = window
    }

    // MARK: - Panel Resizing

    /// Resize the panel to show/hide preview pane (expands to the right)
    @MainActor
    func setPreviewVisible(_ visible: Bool) {
        guard let panel = menuPanel, let leftEdge = panelLeftEdgeX else { return }

        let newWidth = visible
            ? Constants.mainPanelWidth + Constants.dividerWidth + Constants.previewPanelWidth
            : Constants.mainPanelWidth

        let currentFrame = panel.frame
        let newFrame = NSRect(
            x: leftEdge,  // Keep left edge fixed
            y: currentFrame.origin.y,
            width: newWidth,
            height: currentFrame.height
        )

        guard panel.frame != newFrame else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
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

// MARK: - Menu Panel

/// Custom panel that behaves like a popover but with precise positioning control
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Close when losing focus (like clicking in another app)
        AppDelegate.shared?.closePanel()
    }
}

// MARK: - Panel Content View

/// Wrapper view that adds the rounded background styling
@MainActor
private struct PanelContentView: View {
    @Environment(GitHubService.self) var service

    private var hoveredPR: PullRequest? {
        guard let hoveredId = service.state.previewState.hoveredPRId else { return nil }
        return service.state.openPRs.first { $0.id == hoveredId }
    }

    var body: some View {
        HStack(spacing: 0) {
            MainMenuContent()
                .frame(width: 400)
                .contentShape(Rectangle())
                .onHover { hovering in
                    service.setMainPaneHovered(hovering)
                }

            if let pr = hoveredPR {
                Divider()

                PRPreviewView(pr: pr)
                    .frame(width: 320)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        .onChange(of: hoveredPR?.id) { _, newValue in
            AppDelegate.shared?.setPreviewVisible(newValue != nil)
        }
    }
}

// MARK: - Main Menu Content (extracted from MainMenuView)

private struct MainMenuContent: View {
    @Environment(GitHubService.self) var service

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Content
            if service.state.isLoading && service.state.lastUpdated == nil {
                LoadingView()
            } else if let error = service.state.error {
                ErrorView(error: error)
            } else {
                ContentScrollView()
            }

            Divider()

            // Footer
            FooterView()
        }
    }
}
