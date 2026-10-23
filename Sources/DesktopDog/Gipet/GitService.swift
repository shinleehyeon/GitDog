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

    /// Paths that would be wiped by `syncToOrigin` (hard reset), excluding
    /// gipet auto-content files. Used to refuse PR when the user has real WIP.
    static func unrelatedDirtyPaths(_ path: String) -> [String] {
        let allow: Set<String> = [
            "gipet-journal.md",
            ".gipet-book.txt",
            ".gipet-book-index",
        ]
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: path)),
              let entries = try? repo.status() else { return [] }
        var out: [String] = []
        for entry in entries {
            let fromWork = entry.workingTree?.newFile.path ?? ""
            let fromIndex = entry.index?.newFile.path ?? entry.index?.oldFile.path ?? ""
            let p = fromWork.isEmpty ? fromIndex : fromWork
            guard !p.isEmpty else { continue }
            let base = (p as NSString).lastPathComponent
            if !allow.contains(base) { out.append(p) }
        }
        return out
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
        restoreHeadRefIfMissing(repoPath: path)
        stageAll(repoPath: path)
        var commitOID: String?
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: path))
            let commit = try repo.commit(message: message)
            commitOID = commit.id.hex
        } catch {
            return GitResult(ok: false, output: "commit failed: \(error)")
        }
        let result = await push(repoPath: path)
        if let oid = commitOID { repairHeadRef(repoPath: path, oid: oid) }
        return result
    }

    @discardableResult
    static func commitFile(_ path: String, file: String, message: String) async -> GitResult {
        ensureGitUserConfig(repoPath: path)
        restoreHeadRefIfMissing(repoPath: path)
        var commitOID: String?
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: path))
            try repo.add(path: file)
            let commit = try repo.commit(message: message)
            commitOID = commit.id.hex
        } catch {
            return GitResult(ok: false, output: "commit failed: \(error)")
        }
        let result = await push(repoPath: path)
        if let oid = commitOID { repairHeadRef(repoPath: path, oid: oid) }
        return result
    }

    // MARK: - Branch → commit → push → PR → merge
    // Mirrors petclinic_terraform/scripts/create-pr.mjs, plus auto-merge.
    //
    // Hard rules (learned the hard way):
    // 1. Never point HEAD at a SHA whose object isn't in the local odb.
    // 2. Never delete the branch HEAD currently points to.
    // 3. Always land back on origin/<base> (fetch + verified checkout) when done.

    /// Fetch + hard-reset local base to `origin/<base>`. Call this *before*
    /// auto-writing journal/book content — never after, or the new edits get wiped.
    @discardableResult
    static func syncToOrigin(_ path: String, baseBranch: String = "main") async -> Bool {
        ensureGitUserConfig(repoPath: path)
        return await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
    }

    /// Create a feature branch, commit dirty work, push, open a PR, and merge it.
    /// Caller must already be on an up-to-date base with the desired changes staged/dirty
    /// (`syncToOrigin` → write content → then this).
    @discardableResult
    static func commitPushPRAndMerge(_ path: String, message: String,
                                     baseBranch: String = "main") async -> GitResult {
        ensureGitUserConfig(repoPath: path)

        guard let info = GitHubPRService.repoInfo(at: path) else {
            return GitResult(ok: false, output: "GitHub origin을 찾을 수 없어요")
        }
        guard TokenStore.shared.token?.isEmpty == false else {
            return GitResult(ok: false, output: "GitHub 토큰이 필요해요 (로그인 후 다시 시도)")
        }

        guard dirtyCount(path) > 0 else {
            return GitResult(ok: false, output: "커밋할 변경사항이 없어요")
        }

        // Fresh fetch (no reset — that would wipe the journal we just wrote).
        // Branching from a stale main is what made #7/#8 CONFLICTING on journal.md.
        _ = await fetch(repoPath: path)
        if !isSyncedToOrigin(repoPath: path, baseBranch: baseBranch) {
            return GitResult(ok: false, output: "main이 origin보다 오래됐어요. PR을 다시 눌러주세요")
        }

        // Close any previous gipet PRs still open (conflict leftovers).
        await GitHubPRService.closeOpenGipetPullRequests(owner: info.owner, repo: info.repo)

        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let branchName = "gipet/pr-\(df.string(from: Date()))"

        do {
            try createAndSwitchBranch(repoPath: path, named: branchName)
        } catch {
            _ = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
            return GitResult(ok: false, output: "브랜치 생성 실패: \(error)")
        }

        stageAll(repoPath: path)
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: path))
            let commit = try repo.commit(message: message)
            let oid = commit.id.hex
            repairHeadRef(repoPath: path, oid: oid)
            _ = precreateBranchRef(repoPath: path, branchName: branchName, oid: oid)
        } catch {
            _ = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
            return GitResult(ok: false, output: "commit 실패: \(error)")
        }

        let pushResult = await push(repoPath: path)
        guard pushResult.ok else {
            _ = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
            return GitResult(ok: false, output: pushResult.output)
        }

        let title = GitHubPRService.formatTitle(description: message)
        let body = GitHubPRService.formatBody(description: message, commits: [message])
        let pr: GitHubPRService.CreatedPR
        do {
            pr = try await GitHubPRService.createPullRequest(
                owner: info.owner, repo: info.repo,
                title: title, head: branchName, base: baseBranch, body: body
            )
        } catch {
            _ = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
            return GitResult(ok: false, output: "PR 생성 실패: \(error)")
        }

        // Pull latest main into the PR head before squash-merge (avoids the
        // "forgot to pull" conflict on gipet-journal.md).
        await GitHubPRService.updatePullRequestBranch(
            owner: info.owner, repo: info.repo, number: pr.number
        )

        // Formal review (Approve → Comment). Request changes is skipped here
        // because it would fight the immediate squash-merge.
        var reviewLabel = "no-review"
        do {
            let review = try await GitHubPRService.submitPullRequestReview(
                owner: info.owner, repo: info.repo, number: pr.number,
                events: [.approve, .comment]
            )
            reviewLabel = review.event.label
        } catch {
            // Don't block the merge on review failure — log and continue.
            NSLog("[Gipet] PR #%d review skipped: %@", pr.number, "\(error)")
        }

        do {
            _ = try await GitHubPRService.mergePullRequest(
                owner: info.owner, repo: info.repo, number: pr.number
            )
        } catch {
            // Don't leave conflicting OPEN PRs sitting on GitHub — close + sync.
            await GitHubPRService.closePullRequest(
                owner: info.owner, repo: info.repo, number: pr.number
            )
            _ = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
            safeDeleteBranchRef(repoPath: path, branchName: branchName)
            return GitResult(ok: false, output: "merge 실패(#\(pr.number) 닫음): \(error)")
        }

        // Land on origin/main FIRST (HEAD leaves the feature branch), THEN delete it.
        let synced = await syncBaseToOrigin(repoPath: path, baseBranch: baseBranch)
        if synced {
            safeDeleteBranchRef(repoPath: path, branchName: branchName)
        } else {
            NSLog("[Gipet] post-merge sync failed — keeping %@ so HEAD stays valid", branchName)
        }

        return GitResult(ok: true, output: "PR#\(pr.number) · \(reviewLabel) · \(pr.htmlURL)")
    }

    /// Fetch origin and hard-reset local `baseBranch` to `origin/<base>`.
    /// Must leave the worktree clean — otherwise the UI shows a phantom
    /// "1 uncommitted change" (leftover journal lines from the PR we just merged).
    @discardableResult
    private static func syncBaseToOrigin(repoPath: String, baseBranch: String) async -> Bool {
        let fetchResult = await fetch(repoPath: repoPath)
        guard fetchResult.ok else {
            NSLog("[Gipet] syncBaseToOrigin fetch failed: %@", fetchResult.output)
            return false
        }
        guard let tip = readRemoteBranchOID(repoPath: repoPath, remote: "origin", branch: baseBranch) else {
            NSLog("[Gipet] syncBaseToOrigin: no origin/%@", baseBranch)
            return false
        }
        guard commitObjectExists(repoPath: repoPath, oid: tip) else {
            NSLog("[Gipet] syncBaseToOrigin: object %@ missing after fetch", tip)
            return false
        }

        guard precreateBranchRef(repoPath: repoPath, branchName: baseBranch, oid: tip),
              pointHEAD(repoPath: repoPath, toBranch: baseBranch) else {
            return false
        }
        do {
            let repo = try Repository.open(at: URL(fileURLWithPath: repoPath))
            let commit: Commit = try repo.show(id: try OID(hex: tip))
            // Hard reset — `switch` uses SAFE checkout and leaves dirty journal
            // files behind when the index already has staged edits.
            try repo.reset(to: commit, mode: .hard)
            repairHeadRef(repoPath: repoPath, oid: tip)
            let left = dirtyCount(repoPath)
            let synced = left == 0 && isSyncedToOrigin(repoPath: repoPath, baseBranch: baseBranch)
            NSLog("[Gipet] syncBaseToOrigin → %@ @ %@ (dirty=%d synced=%d)",
                  baseBranch, String(tip.prefix(8)), left, synced ? 1 : 0)
            return synced
        } catch {
            NSLog("[Gipet] syncBaseToOrigin reset failed: %@", "\(error)")
            // Last resort: force-restore index + worktree from HEAD.
            if let repo = try? Repository.open(at: URL(fileURLWithPath: repoPath)) {
                try? repo.restore([.workingTree, .staged])
            }
            repairHeadRef(repoPath: repoPath, oid: tip)
            return dirtyCount(repoPath) == 0
                && isSyncedToOrigin(repoPath: repoPath, baseBranch: baseBranch)
        }
    }

    /// True when HEAD is `baseBranch` and its OID matches `origin/<base>`.
    private static func isSyncedToOrigin(repoPath: String, baseBranch: String) -> Bool {
        guard currentHEADBranch(repoPath: repoPath) == baseBranch,
              let local = readBranchOID(repoPath: repoPath, branchName: baseBranch),
              let remote = readRemoteBranchOID(repoPath: repoPath, remote: "origin", branch: baseBranch)
        else { return false }
        return local == remote
    }

    /// Create `named` from current HEAD and switch to it.
    private static func createAndSwitchBranch(repoPath: String, named branchName: String) throws {
        let repo = try Repository.open(at: URL(fileURLWithPath: repoPath))
        let current = try repo.branch.current
        guard let commit = current.target as? Commit else {
            throw NSError(domain: "GitService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "HEAD commit missing"])
        }

        let oid = commit.id.hex
        guard commitObjectExists(repoPath: repoPath, oid: oid) else {
            throw NSError(domain: "GitService", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "HEAD object missing — run sync first"])
        }
        guard precreateBranchRef(repoPath: repoPath, branchName: branchName, oid: oid) else {
            throw NSError(domain: "GitService", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "could not write refs/heads/\(branchName)"])
        }

        let newBranch: Branch
        if let existing = repo.branch[branchName, type: .local] {
            newBranch = existing
        } else {
            newBranch = try repo.branch.create(named: branchName, target: commit)
        }
        try repo.switch(to: newBranch)
        guard pointHEAD(repoPath: repoPath, toBranch: branchName) else {
            throw NSError(domain: "GitService", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "could not update HEAD"])
        }
        repairHeadRef(repoPath: repoPath, oid: oid)
    }

    @discardableResult
    private static func precreateBranchRef(repoPath: String, branchName: String, oid: String) -> Bool {
        var refURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git/refs/heads")
        for part in branchName.split(separator: "/") {
            refURL = refURL.appendingPathComponent(String(part))
        }
        do {
            try FileManager.default.createDirectory(
                at: refURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data((oid + "\n").utf8).write(to: refURL, options: .atomic)
            return true
        } catch {
            NSLog("[Gipet] precreateBranchRef failed: %@", error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private static func pointHEAD(repoPath: String, toBranch branchName: String) -> Bool {
        guard branchRefExists(repoPath: repoPath, branchName: branchName),
              let oid = readBranchOID(repoPath: repoPath, branchName: branchName),
              commitObjectExists(repoPath: repoPath, oid: oid) else {
            NSLog("[Gipet] pointHEAD refused — %@ missing or object absent", branchName)
            return false
        }
        let headURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git/HEAD")
        do {
            try "ref: refs/heads/\(branchName)\n".write(to: headURL, atomically: false, encoding: .utf8)
            return true
        } catch {
            NSLog("[Gipet] pointHEAD write failed: %@", error.localizedDescription)
            return false
        }
    }

    private static func branchRefExists(repoPath: String, branchName: String) -> Bool {
        branchRefURL(repoPath: repoPath, branchName: branchName)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private static func readBranchOID(repoPath: String, branchName: String) -> String? {
        guard let url = branchRefURL(repoPath: repoPath, branchName: branchName),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let oid = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return oid.count >= 40 ? oid : nil
    }

    private static func branchRefURL(repoPath: String, branchName: String) -> URL? {
        var refURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git/refs/heads")
        for part in branchName.split(separator: "/") {
            refURL = refURL.appendingPathComponent(String(part))
        }
        return refURL
    }

    /// Delete a branch ref only when HEAD is NOT on that branch.
    private static func safeDeleteBranchRef(repoPath: String, branchName: String) {
        if currentHEADBranch(repoPath: repoPath) == branchName {
            NSLog("[Gipet] refuse to delete current branch %@", branchName)
            return
        }
        guard let url = branchRefURL(repoPath: repoPath, branchName: branchName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func currentHEADBranch(repoPath: String) -> String? {
        let headURL = URL(fileURLWithPath: repoPath).appendingPathComponent(".git/HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8),
              head.hasPrefix("ref: refs/heads/") else { return nil }
        return head
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ref: refs/heads/", with: "")
    }

    private static func readRemoteBranchOID(repoPath: String, remote: String, branch: String) -> String? {
        var refURL = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".git/refs/remotes")
            .appendingPathComponent(remote)
        for part in branch.split(separator: "/") {
            refURL = refURL.appendingPathComponent(String(part))
        }
        guard let s = try? String(contentsOf: refURL, encoding: .utf8) else { return nil }
        let oid = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return oid.count >= 40 ? oid : nil
    }

    private static func commitObjectExists(repoPath: String, oid: String) -> Bool {
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: repoPath)),
              let parsed = try? OID(hex: oid) else { return false }
        return (try? repo.show(id: parsed) as Commit) != nil
    }

    // MARK: - Private: repair HEAD ref

    // Before committing: if refs/heads/<branch> is missing (libgit2 couldn't create it
    // last time), read the latest OID from the reflog and pre-create the file so that
    // libgit2 can OVERWRITE it (overwrite succeeds; new-file create fails in Sandbox).
    private static func restoreHeadRefIfMissing(repoPath: String) {
        let base = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard let head = try? String(contentsOf: base.appendingPathComponent("HEAD"), encoding: .utf8),
              head.hasPrefix("ref: ") else { return }
        let refPath = head.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ref: ", with: "")
        let refURL = base.appendingPathComponent(refPath)
        guard !FileManager.default.fileExists(atPath: refURL.path) else { return }

        // Read latest OID from the reflog for this branch
        let logURL = base.appendingPathComponent("logs").appendingPathComponent(refPath)
        guard let log = try? String(contentsOf: logURL, encoding: .utf8),
              let lastLine = log.components(separatedBy: "\n").last(where: { !$0.isEmpty }) else { return }
        let parts = lastLine.split(separator: " ", maxSplits: 3)
        guard parts.count >= 2 else { return }
        let latestOID = String(parts[1])
        guard latestOID != "0000000000000000000000000000000000000000" else { return }

        try? FileManager.default.createDirectory(at: refURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let data = Data((latestOID + "\n").utf8)
        if FileManager.default.createFile(atPath: refURL.path, contents: data) {
            NSLog("[Gipet] restoreHeadRef: pre-created \(latestOID.prefix(8)) → \(refPath)")
        }
    }

    // After committing + pushing: overwrite the ref with the new commit OID.
    // libgit2 fails to CREATE the loose ref file in the Sandbox, but overwriting
    // an existing file works — so we ensure it exists above before the commit.
    private static func repairHeadRef(repoPath: String, oid: String) {
        let base = URL(fileURLWithPath: repoPath).appendingPathComponent(".git")
        guard let head = try? String(contentsOf: base.appendingPathComponent("HEAD"), encoding: .utf8),
              head.hasPrefix("ref: ") else {
            NSLog("[Gipet] repairHeadRef: could not read HEAD at \(repoPath)")
            return
        }
        let refPath = head.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ref: ", with: "")
        let refURL = base.appendingPathComponent(refPath)
        try? FileManager.default.createDirectory(at: refURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // atomically:false writes directly — atomically:true uses a temp file which
        // can fail inside App Sandbox even when the destination path is accessible.
        let data = Data((oid + "\n").utf8)
        if FileManager.default.createFile(atPath: refURL.path, contents: data, attributes: nil) {
            NSLog("[Gipet] repairHeadRef: wrote \(oid.prefix(8)) → \(refPath)")
        } else {
            NSLog("[Gipet] repairHeadRef: createFile failed for \(refURL.path)")
        }
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

    // MARK: - Private: push / fetch via embedded-credential URL

    private static func push(repoPath: String) async -> GitResult {
        await withAuthRemote(repoPath: repoPath, tempName: "gipet-push") { repo, remote in
            try await repo.push(remote: remote)
            return "committed & pushed"
        }
    }

    private static func fetch(repoPath: String) async -> GitResult {
        await withAuthRemote(repoPath: repoPath, tempName: "gipet-fetch") { repo, remote in
            try await repo.fetch(remote: remote)
            // Auth fetch lands tips under refs/remotes/gipet-fetch/*, NOT origin/*.
            // Without mirroring, sync/isSynced read a stale origin/main and we
            // branch off an old tip → journal.md CONFLICTING PRs (#10/#11).
            mirrorRemoteTips(repoPath: repoPath, from: "gipet-fetch", to: "origin")
            return "fetched"
        }
    }

    /// Copy `refs/remotes/<from>/<branch>` → `refs/remotes/<to>/<branch>`.
    private static func mirrorRemoteTips(repoPath: String, from: String, to: String) {
        let fromRoot = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".git/refs/remotes")
            .appendingPathComponent(from)
        let toRoot = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".git/refs/remotes")
            .appendingPathComponent(to)
        guard let enumerator = FileManager.default.enumerator(
            at: fromRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let file = enumerator.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            // Relative path under fromRoot, e.g. "main" or "gipet/pr-…".
            let rel = file.path.replacingOccurrences(of: fromRoot.path + "/", with: "")
            var dest = toRoot
            for part in rel.split(separator: "/") {
                dest = dest.appendingPathComponent(String(part))
            }
            do {
                try FileManager.default.createDirectory(
                    at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if let data = try? Data(contentsOf: file) {
                    try data.write(to: dest, options: .atomic)
                }
            } catch {
                NSLog("[Gipet] mirrorRemoteTips %@ → %@ failed: %@", rel, to, error.localizedDescription)
            }
        }
        if let main = readRemoteBranchOID(repoPath: repoPath, remote: to, branch: "main") {
            NSLog("[Gipet] origin/main after fetch mirror: %@", String(main.prefix(8)))
        }
    }

    /// Shared HTTPS-token remote for push/fetch (App Sandbox can't use SSH agent).
    private static func withAuthRemote(
        repoPath: String,
        tempName: String,
        _ work: (Repository, Remote) async throws -> String
    ) async -> GitResult {
        guard let token = TokenStore.shared.token, !token.isEmpty else {
            return GitResult(ok: false, output: "no GitHub token")
        }
        guard let repo = try? Repository.open(at: URL(fileURLWithPath: repoPath)) else {
            return GitResult(ok: false, output: "could not open repo")
        }
        guard let originURL = repo.remote["origin"]?.url,
              let authURL = injectToken(token, into: originURL) else {
            return GitResult(ok: false, output: "no 'origin' remote or unsupported URL")
        }

        let tempRemote: Remote
        do {
            if let existing = repo.remote[tempName] {
                try repo.remote.remove(existing)
            }
            tempRemote = try repo.remote.add(named: tempName, at: authURL)
        } catch {
            return GitResult(ok: false, output: "auth remote setup failed — \(error)")
        }

        do {
            let msg = try await work(repo, tempRemote)
            try? repo.remote.remove(tempRemote)
            return GitResult(ok: true, output: msg)
        } catch {
            try? repo.remote.remove(tempRemote)
            return GitResult(ok: false, output: "\(error)")
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
