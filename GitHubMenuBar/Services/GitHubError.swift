import Foundation

enum GitHubError: LocalizedError {
    case cliError(String)
    case processError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .cliError(let message):
            if message.contains("gh auth") || message.contains("401") {
                return "GitHub authentication required. Run 'gh auth login' in Terminal."
            }
            return "GitHub CLI error: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
