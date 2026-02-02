import Foundation

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
