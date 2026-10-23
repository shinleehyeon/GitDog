// Gipet — GitHub Pull Request create + merge.
// Mirrors the non-interactive core of petclinic_terraform/scripts/create-pr.mjs
// (push head → open PR against main → optionally merge), without the inquirer UI.

import Foundation

enum GitHubPRService {

    struct RepoInfo {
        let owner: String
        let repo: String
    }

    struct CreatedPR {
        let number: Int
        let htmlURL: String
    }

    // MARK: - Repo identity

    /// Parse `owner/repo` from a local repo's `origin` URL (HTTPS or SSH).
    static func repoInfo(at path: String) -> RepoInfo? {
        guard let repo = try? RepositoryOpen.open(at: path),
              let remoteURL = repo.originURL else { return nil }
        return parseGitHubRepo(from: remoteURL)
    }

    static func parseGitHubRepo(from remoteURL: String) -> RepoInfo? {
        // git@github.com:owner/repo.git  |  https://github.com/owner/repo.git
        let pattern = #"github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: remoteURL, range: NSRange(remoteURL.startIndex..., in: remoteURL)),
              let ownerRange = Range(match.range(withName: "owner"), in: remoteURL),
              let repoRange = Range(match.range(withName: "repo"), in: remoteURL) else {
            return nil
        }
        return RepoInfo(owner: String(remoteURL[ownerRange]), repo: String(remoteURL[repoRange]))
    }

    // MARK: - PR API

    /// Create a ready (non-draft) PR. Title/body style follows create-pr.mjs.
    static func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        head: String,
        base: String,
        body: String
    ) async throws -> CreatedPR {
        struct Body: Encodable {
            let title: String
            let head: String
            let base: String
            let body: String
            let draft: Bool
        }
        struct Response: Decodable {
            let number: Int
            let html_url: String
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls") else {
            throw APIError.badURL
        }
        // Ensure APIClient has the keychain token (same source GitService push uses).
        if APIClient.shared.accessToken == nil {
            APIClient.shared.accessToken = TokenStore.shared.token
        }
        let resp: Response = try await APIClient.shared.sendJSON(
            Response.self, url, method: "POST",
            body: Body(title: title, head: head, base: base, body: body, draft: false)
        )
        return CreatedPR(number: resp.number, htmlURL: resp.html_url)
    }

    /// GitHub PR review events that count as "Code review" contributions
    /// when submitted on someone else's PR.
    enum ReviewEvent: String, CaseIterable {
        case approve = "APPROVE"
        case requestChanges = "REQUEST_CHANGES"
        case comment = "COMMENT"

        var label: String {
            switch self {
            case .approve: return "Approve"
            case .requestChanges: return "Request changes"
            case .comment: return "Comment"
            }
        }
    }

    struct SubmittedReview {
        let event: ReviewEvent
        let id: Int?
    }

    /// Submit a formal PR review (Approve / Request changes / Comment).
    /// For the auto PR→merge button we only try `.approve` then `.comment` —
    /// `.requestChanges` would fight the immediate merge.
    @discardableResult
    static func submitPullRequestReview(
        owner: String,
        repo: String,
        number: Int,
        events: [ReviewEvent] = [.approve, .comment],
        body: String? = nil
    ) async throws -> SubmittedReview {
        struct Body: Encodable {
            let body: String
            let event: String
        }
        struct Response: Decodable {
            let id: Int?
            let state: String?
            let message: String?
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)/reviews") else {
            throw APIError.badURL
        }
        ensureToken()

        var lastError: Error = APIError.decode("no review event attempted")
        for event in events {
            let text = body ?? defaultReviewBody(for: event)
            do {
                let resp: Response = try await APIClient.shared.sendJSON(
                    Response.self, url, method: "POST",
                    body: Body(body: text, event: event.rawValue)
                )
                NSLog("[Gipet] PR #%d review submitted (%@, id=%d)",
                      number, event.rawValue, resp.id ?? 0)
                return SubmittedReview(event: event, id: resp.id)
            } catch {
                lastError = error
                NSLog("[Gipet] PR #%d %@ failed — %@", number, event.rawValue, "\(error)")
            }
        }
        throw lastError
    }

    private static func defaultReviewBody(for event: ReviewEvent) -> String {
        switch event {
        case .approve:
            return "🐶 gipet review — Approve. Looks good to merge."
        case .requestChanges:
            return "🐶 gipet review — Request changes."
        case .comment:
            return "🐶 gipet review — Comment. Checked the diff, proceeding to merge."
        }
    }

    /// Returns the merge commit SHA when successful.
    @discardableResult
    static func mergePullRequest(
        owner: String,
        repo: String,
        number: Int,
        method: String = "squash"
    ) async throws -> String {
        struct Body: Encodable {
            let merge_method: String
        }
        struct Response: Decodable {
            let merged: Bool?
            let sha: String?
            let message: String?
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)/merge") else {
            throw APIError.badURL
        }
        ensureToken()
        let resp: Response = try await APIClient.shared.sendJSON(
            Response.self, url, method: "PUT",
            body: Body(merge_method: method)
        )
        guard resp.merged == true else {
            throw APIError.decode(resp.message ?? "merge rejected")
        }
        return resp.sha ?? ""
    }

    /// Close an open PR (used when merge fails so we don't leave orphans).
    static func closePullRequest(owner: String, repo: String, number: Int) async {
        struct Body: Encodable { let state: String }
        struct Response: Decodable { let number: Int? }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)") else { return }
        ensureToken()
        do {
            _ = try await APIClient.shared.sendJSON(
                Response.self, url, method: "PATCH",
                body: Body(state: "closed")
            )
        } catch {
            NSLog("[Gipet] closePullRequest #%d failed: %@", number, "\(error)")
        }
    }

    /// Merge latest `base` into the PR head so squash-merge doesn't conflict
    /// when main moved since we branched (classic stale-pull conflict).
    static func updatePullRequestBranch(owner: String, repo: String, number: Int) async {
        struct Response: Decodable { let message: String? }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls/\(number)/update-branch") else { return }
        ensureToken()
        do {
            _ = try await APIClient.shared.sendJSON(
                Response.self, url, method: "PUT",
                bodyData: Data("{}".utf8)
            )
            // Give GitHub a moment to finish the update before we merge.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        } catch {
            // 422 = already up to date / not required — fine to ignore.
            NSLog("[Gipet] updatePullRequestBranch #%d: %@", number, "\(error)")
        }
    }

    /// Close any leftover open gipet PRs so a new run doesn't stack conflicts.
    static func closeOpenGipetPullRequests(owner: String, repo: String) async {
        struct Item: Decodable {
            let number: Int
            let head: Head
            struct Head: Decodable { let ref: String }
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls?state=open&per_page=20") else { return }
        ensureToken()
        guard let items: [Item] = try? await APIClient.shared.json([Item].self, url) else { return }
        for item in items where item.head.ref.hasPrefix("gipet/pr-") {
            NSLog("[Gipet] closing leftover open PR #%d (%@)", item.number, item.head.ref)
            await closePullRequest(owner: owner, repo: repo, number: item.number)
        }
    }

    private static func ensureToken() {
        if APIClient.shared.accessToken == nil {
            APIClient.shared.accessToken = TokenStore.shared.token
        }
    }

    // MARK: - Issues

    struct CreatedIssue {
        let number: Int
        let htmlURL: String
    }

    /// Open an issue (counts toward GitHub "Issues" activity).
    static func createIssue(
        owner: String,
        repo: String,
        title: String,
        body: String
    ) async throws -> CreatedIssue {
        struct Body: Encodable {
            let title: String
            let body: String
        }
        struct Response: Decodable {
            let number: Int
            let html_url: String
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues") else {
            throw APIError.badURL
        }
        ensureToken()
        let resp: Response = try await APIClient.shared.sendJSON(
            Response.self, url, method: "POST",
            body: Body(title: title, body: body)
        )
        return CreatedIssue(number: resp.number, htmlURL: resp.html_url)
    }

    /// Close an issue so the repo doesn't pile up gipet noise.
    /// Opening still counted; closing is just cleanup.
    static func closeIssue(owner: String, repo: String, number: Int) async {
        struct Body: Encodable { let state: String }
        struct Response: Decodable { let number: Int? }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/issues/\(number)") else { return }
        ensureToken()
        do {
            _ = try await APIClient.shared.sendJSON(
                Response.self, url, method: "PATCH",
                body: Body(state: "closed")
            )
        } catch {
            NSLog("[Gipet] closeIssue #%d failed: %@", number, "\(error)")
        }
    }

    /// PR title shaped like create-pr.mjs: `[label] description`.
    static func formatTitle(description: String) -> String {
        "[🐶 gipet] \(description)"
    }

    static func formatBody(description: String, commits: [String]) -> String {
        var lines = [
            "## 무엇을 작업했나요",
            description,
            "",
        ]
        if !commits.isEmpty {
            lines.append("## 커밋 내역")
            lines.append(contentsOf: commits.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

// Tiny helper so GitHubPRService doesn't import SwiftGitX directly for URL parsing.
private enum RepositoryOpen {
    struct Info {
        let originURL: String?
    }

    static func open(at path: String) throws -> Info {
        // Read origin from .git/config — avoids pulling SwiftGitX into this file.
        let configURL = URL(fileURLWithPath: path).appendingPathComponent(".git/config")
        let content = try String(contentsOf: configURL, encoding: .utf8)
        // Match [remote "origin"] ... url = ...
        var inOrigin = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inOrigin = trimmed.contains("remote \"origin\"")
                continue
            }
            if inOrigin, trimmed.hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2 {
                    return Info(originURL: parts[1])
                }
            }
        }
        return Info(originURL: nil)
    }
}
