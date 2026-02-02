import SwiftUI
import AppKit

// MARK: - App Colors

/// Centralized color definitions for the app
enum AppColors {
    // MARK: - Base Colors (single source of truth)
    private static var baseOrange: Color { Color(nsColor: .systemOrange) }
    private static var baseYellow: Color { Color(nsColor: .systemYellow.blended(withFraction: 0.15, of: .black) ?? .systemYellow) }
    private static var baseGreen: Color { Color(nsColor: .systemGreen) }
    private static var baseRed: Color { Color(nsColor: .systemRed) }
    private static var basePurple: Color { Color(nsColor: .systemPurple) }
    private static var baseBlue: Color { Color(nsColor: .systemBlue) }
    private static var baseGray: Color { Color(nsColor: .systemGray) }
    private static var baseMint: Color { Color(nsColor: .systemMint) }
    private static var basePink: Color { Color(nsColor: .systemPink) }

    // MARK: - Section Badge Colors
    static var openPRs: Color { baseGreen }
    static var reviewRequests: Color { baseOrange }
    static var mergedPRs: Color { basePurple }
    static var notifications: Color { baseBlue }
    static var issues: Color { baseOrange }

    // MARK: - CI Status Colors
    static var ciSuccess: Color { baseGreen }
    static var ciFailure: Color { baseRed }
    static var ciPending: Color { baseYellow }
    static var ciUnknown: Color { baseGray }

    // MARK: - PR Age Colors
    static var ageFresh: Color { baseGreen }       // < 1 day
    static var ageRecent: Color { baseMint }       // 1-3 days
    static var ageModerate: Color { baseYellow }   // 3-7 days
    static var ageOld: Color { baseOrange }        // > 7 days

    // MARK: - Status Colors
    static var attention: Color { baseOrange }
    static var conflict: Color { baseYellow }
    static var success: Color { baseGreen }
    static var error: Color { baseRed }
    static var warning: Color { baseOrange }

    // MARK: - Notification Reason Colors
    static var reviewRequested: Color { basePurple }
    static var mention: Color { baseBlue }
    static var author: Color { baseGreen }
    static var ciActivity: Color { baseYellow }
    static var assign: Color { baseOrange }
    static var stateChange: Color { basePurple }
    static var defaultNotification: Color { baseGray }

    // MARK: - Diff Colors
    static var additions: Color { baseGreen }
    static var deletions: Color { basePink }

    // MARK: - UI Colors
    static var draft: Color { baseGray }
    static var muted: Color { baseOrange }
    static var link: Color { baseBlue }

    // MARK: - Card Backgrounds
    static func cardBackground(hovered: Bool) -> Color {
        Color.primary.opacity(hovered ? 0.12 : 0.06)
    }

    static func notificationBackground(hovered: Bool) -> Color {
        Color.primary.opacity(hovered ? 0.08 : 0.03)
    }
}
