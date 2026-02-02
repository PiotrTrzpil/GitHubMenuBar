import Foundation

// MARK: - Date Formatting

extension Date {
    /// Compact relative time format (e.g., "2h ago", "3d ago")
    var compactRelativeFormatted: String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let days = components.day, days > 0 {
            if days >= 7 {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                return formatter.string(from: self)
            }
            return "\(days)d ago"
        }

        if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        }

        if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        }

        return "just now"
    }
}

// MARK: - String Extensions

extension String {
    /// Truncate string to a maximum length with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength - 3)) + "..."
    }
}

// MARK: - Array Extensions

extension Array {
    /// Safely access an element at the given index
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
