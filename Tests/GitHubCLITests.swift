import XCTest
import Foundation

/// End-to-end tests that verify the gh CLI commands work correctly.
/// These tests require `gh` to be installed and authenticated.
final class GitHubCLITests: XCTestCase {

    private var ghPath: String?

    override func setUp() {
        super.setUp()
        // Find gh binary
        let possiblePaths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/run/current-system/sw/bin/gh"
        ]
        ghPath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Helper

    private func runGH(_ arguments: [String]) throws -> Data {
        guard let ghPath = ghPath else {
            throw XCTSkip("gh CLI not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            if error.contains("gh auth") || error.contains("401") {
                throw XCTSkip("gh not authenticated: \(error)")
            }
            XCTFail("gh command failed: \(error)")
        }

        return data
    }

    // MARK: - Tests

    func testGHInstalled() throws {
        XCTAssertNotNil(ghPath, "gh CLI should be installed")
    }

    func testAuthStatus() throws {
        let data = try runGH(["auth", "status"])
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("Logged in") || output.contains("github.com"), "Should be authenticated")
    }

    func testFetchUsername() throws {
        let data = try runGH(["api", "user", "--jq", ".login"])
        let username = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotNil(username)
        XCTAssertFalse(username!.isEmpty, "Username should not be empty")
    }

    func testSearchOpenPRs() throws {
        let data = try runGH([
            "search", "prs",
            "--author", "@me",
            "--state", "open",
            "--json", "number,title,url,updatedAt,createdAt,isDraft,repository",
            "--limit", "5"
        ])

        // Should return valid JSON array (might be empty)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [[String: Any]], "Should return array of PRs")
    }

    func testSearchMergedPRs() throws {
        let data = try runGH([
            "search", "prs",
            "--author", "@me",
            "--merged",
            "--json", "number,title,url,repository,updatedAt,closedAt",
            "--limit", "5"
        ])

        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [[String: Any]], "Should return array of PRs")
    }

    func testSearchReviewRequests() throws {
        let data = try runGH([
            "search", "prs",
            "--review-requested", "@me",
            "--state", "open",
            "--json", "number,title,url,author,updatedAt,repository",
            "--limit", "5"
        ])

        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [[String: Any]], "Should return array of PRs")
    }

    func testSearchIssues() throws {
        let data = try runGH([
            "search", "issues",
            "--author", "@me",
            "--state", "open",
            "--json", "number,title,url,commentsCount,updatedAt",
            "--limit", "5"
        ])

        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [[String: Any]], "Should return array of issues")
    }

    func testFetchNotifications() throws {
        // This might return empty if no notifications
        let data = try runGH(["api", "notifications", "--jq", ".[0:5]"])

        // Even empty, should be valid JSON
        if !data.isEmpty {
            let json = try JSONSerialization.jsonObject(with: data)
            XCTAssertTrue(json is [[String: Any]], "Should return array of notifications")
        }
    }
}
