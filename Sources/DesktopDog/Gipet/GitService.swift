// Gipet — sandbox-safe git service using SwiftGitX (libgit2) for local operations.
// Push uses a temporary remote with an embedded OAuth token in the URL, avoiding
// the need to import libgit2 directly (which breaks Xcode's package resolver).

import Foundation
import SwiftGitX

// MARK: - Result type

struct GitResult {
    let ok: Bool
    let output: String
}

// MARK: - GitService

enum GitService {

    // MARK: - Helpers

    static func isGitRepo(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(".git").path)
    }

    static func repoName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    // MARK: - Status

    static func dirtyCount(_ path: String) -> Int {
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: path)) else { return 0 }
        return (try? repo.status())?.count ?? 0
    }

    // MARK: - Diff for AI commit message

    static func diffForMessage(_ path: String, maxChars: Int = 6000) -> String {
        stageAll(repoPath: path)
        let url = URL(fileURLWithPath: path)
        guard let repo = try? Repository.open(at: url),
              let diff = try? repo.diff(to: .index) else { return "" }
        var lines: [String] = []
        for patch in diff.patches {
            lines.append("--- a/\(patch.delta.oldFile.path)")
            lines.append("+++ b/\(patch.delta.newFile.path)")
            for hunk in patch.hunks {
                lines.append(hunk.header.trimmingCharacters(in: .whitespacesAndNewlines))
                for line in hunk.lines {
                    let content = line.content.hasSuffix("\n") ? String(line.content.dropLast()) : line.content
                    lines.append(line.type.rawValue + content)
                }
            }
        }
        return String(lines.joined(separator: "\n").prefix(maxChars))
    }

    // MARK: - Commit & push

    @discardableResult
    static func commitAndPush(_ path: String, message: String) async -> GitResult {
        ensureGitUserConfig(repoPath: path)
        stageAll(repoPath: path)
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: path))
            try repo.commit(message: message)
        } catch {
            return GitResult(ok: false, output: "commit failed: \(error)")
        }
        return await push(repoPath: path)
    }

    @discardableResult
    static func commitFile(_ path: String, file: String, message: String) async -> GitResult {
        ensureGitUserConfig(repoPath: path)
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: path))
            try repo.add(path: file)
            try repo.commit(message: message)
        } catch {
            return GitResult(ok: false, output: "commit failed: \(error)")
        }
        return await push(repoPath: path)
    }

    // MARK: - Private: ensure git user config

    // App Sandbox can't read ~/.gitconfig, so write user.name/email into the
    // repo-local .git/config if missing. Uses GitHub login as the author identity.
    private static func ensureGitUserConfig(repoPath: String) {
        let configURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".git/config")
        guard var content = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        guard !content.contains("\tname =") && !content.contains("    name =") else { return }
        let login = TokenStore.shared.cachedLogin ?? "gipet-user"
        let email = "\(login)@users.noreply.github.com"
        content += "\n[user]\n\tname = \(login)\n\temail = \(email)\n"
        try? content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Private: stage all

    // Equivalent to `git add -A`. SwiftGitX's add(paths: []) calls git_index_add_all
    // with an empty strarray, which libgit2 treats as nil — processing all files
    // including deletions (removes them from the index when absent in workdir).
    private static func stageAll(repoPath: String) {
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: repoPath)) else { return }
        try? repo.add(paths: [])
    }

    // MARK: - Private: push via embedded-credential URL

    private static func push(repoPath: String) async -> GitResult {
        guard let token = TokenStore.shared.token, !token.isEmpty else {
            return GitResult(ok: false, output: "committed locally; no GitHub token — push skipped")
        }
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: repoPath)) else {
            return GitResult(ok: false, output: "committed locally; push failed — could not open repo")
        }
        guard let originURL = repo.remote["origin"]?.url,
              let authURL = injectToken(token, into: originURL) else {
            return GitResult(ok: false, output: "committed locally; push failed — no 'origin' remote or unsupported URL")
        }

        // Add a temporary remote with the token embedded in the URL so that
        // SwiftGitX's git_remote_push call picks up HTTPS credentials automatically.
        let tempName = "gipet-push"
        let tempRemote: Remote
        do {
            if let existing = repo.remote[tempName] {
                try repo.remote.remove(existing)
            }
            tempRemote = try repo.remote.add(named: tempName, at: authURL)
        } catch {
            return GitResult(ok: false, output: "committed locally; push setup failed — \(error)")
        }

        do {
            try await repo.push(remote: tempRemote)
            try? repo.remote.remove(tempRemote)
            return GitResult(ok: true, output: "committed & pushed")
        } catch {
            try? repo.remote.remove(tempRemote)
            return GitResult(ok: false, output: "committed locally; push failed — \(error)")
        }
    }

    private static func injectToken(_ token: String, into url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.hasPrefix("http") == true else { return nil }
        components.user = "x-access-token"
        components.password = token
        return components.url
    }
}
