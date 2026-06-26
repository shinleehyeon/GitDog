// Gipet — runs git for the watched-folder one-click commit feature.

import Foundation

struct GitResult {
    let ok: Bool
    let output: String
}

enum GitService {
    /// Run a git subcommand inside `repo` and capture combined output.
    @discardableResult
    static func run(_ args: [String], in repo: String) -> GitResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: repo, isDirectory: true)
        // Keep git non-interactive (never prompt for credentials/editor).
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return GitResult(ok: false, output: "failed to launch git: \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return GitResult(ok: proc.terminationStatus == 0, output: out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isGitRepo(_ path: String) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], in: path).output == "true"
    }

    /// Number of changed/untracked entries (0 = clean).
    static func dirtyCount(_ path: String) -> Int {
        let r = run(["status", "--porcelain"], in: path)
        guard r.ok else { return 0 }
        return r.output.isEmpty ? 0 : r.output.split(separator: "\n").count
    }

    /// Diff used to feed the AI, capped so we don't send a huge payload.
    static func diffForMessage(_ path: String, maxChars: Int = 6000) -> String {
        // Stage everything first so new files appear in the diff.
        run(["add", "-A"], in: path)
        let stat = run(["diff", "--cached", "--stat"], in: path).output
        let diff = run(["diff", "--cached", "--unified=0"], in: path).output
        let combined = stat.isEmpty ? diff : "\(stat)\n\n\(diff)"
        return String(combined.prefix(maxChars))
    }

    /// Stage all, commit with `message`, then push. Returns the final result.
    static func commitAndPush(_ path: String, message: String) -> GitResult {
        let add = run(["add", "-A"], in: path)
        guard add.ok else { return add }
        let commit = run(["commit", "-m", message], in: path)
        guard commit.ok else { return commit }
        return push(in: path)
    }

    /// Push, setting upstream automatically if the branch has none.
    /// Surfaces push failures (auth/permission/offline) instead of hiding them.
    private static func push(in repo: String) -> GitResult {
        var r = run(["push"], in: repo)
        let lower = r.output.lowercased()
        if !r.ok, lower.contains("no upstream") || lower.contains("set-upstream") {
            r = run(["push", "-u", "origin", "HEAD"], in: repo)
        }
        if r.ok {
            return GitResult(ok: true, output: "committed & pushed")
        }
        return GitResult(ok: false, output: "committed locally; push failed — \(String(r.output.prefix(160)))")
    }

    static func repoName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Commit ONLY `file` (relative to repo) then push — used by the journal
    /// feature so unrelated working-tree changes aren't swept in.
    static func commitFile(_ path: String, file: String, message: String) -> GitResult {
        let add = run(["add", "--", file], in: path)
        guard add.ok else { return add }
        let commit = run(["commit", "-m", message, "--", file], in: path)
        guard commit.ok else { return commit }
        return push(in: path)
    }
}
