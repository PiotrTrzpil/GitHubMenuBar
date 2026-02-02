import Foundation

/// Known paths where the GitHub CLI binary might be installed
enum GitHubCLI {
    static let possiblePaths = [
        "/opt/homebrew/bin/gh",  // Apple Silicon Homebrew
        "/usr/local/bin/gh",      // Intel Homebrew
        "/run/current-system/sw/bin/gh",  // NixOS
        "/etc/profiles/per-user/\(NSUserName())/bin/gh"  // Nix home-manager
    ]

    /// Find the first available gh binary path
    static var path: String? {
        possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - CLI Execution

extension GitHubService {
    func runGH(_ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()

                // Find gh binary - GUI apps don't inherit shell PATH
                guard let ghPath = GitHubCLI.path else {
                    continuation.resume(throwing: GitHubError.cliError("GitHub CLI not found. Install with: brew install gh"))
                    return
                }

                process.executableURL = URL(fileURLWithPath: ghPath)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: GitHubError.cliError(errorMessage))
                    } else {
                        continuation.resume(returning: data)
                    }
                } catch {
                    continuation.resume(throwing: GitHubError.processError(error.localizedDescription))
                }
            }
        }
    }

    func runGHJSON<T: Decodable>(_ arguments: [String], as type: T.Type) async throws -> T {
        let data = try await runGH(arguments)

        // Handle empty response
        if data.isEmpty {
            if T.self == [PullRequest].self {
                return [] as! T
            } else if T.self == [ReviewRequest].self {
                return [] as! T
            }
        }

        return try decoder.decode(T.self, from: data)
    }
}
