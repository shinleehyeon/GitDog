// Gipet — observable state shared by the popover UI and the commit watcher.

import Foundation
import AppKit
import Combine

/// ObservableObject for the popover. Network work runs off-main; every
/// @Published mutation hops back to the main actor.
final class GipetViewModel: ObservableObject {
    static let shared = GipetViewModel()

    @Published var user: GitHubUser?
    @Published var days: [ContributionDay] = []
    @Published var stats = ContributionStats()
    @Published var avatar: NSImage?
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var lastUpdated: Date?

    // Watched git repos (one-click commit feature).
    @Published var repos: [RepoState] = []
    var aiAvailable: Bool { OpenRouterClient.isConfigured }

    var isSignedIn: Bool { TokenStore.shared.isSignedIn }

    /// Today's contribution level (0...4) for the menu-bar grass square (local day).
    var todayLevel: Int {
        let cal = Calendar.current
        return days.first(where: { cal.isDateInToday($0.date) })?.level ?? 0
    }

    private let provider = GitHubDataProvider.shared

    /// Path ①: track a username with no token (public contributions only).
    func track(username: String) {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !name.isEmpty else { return }
        TokenStore.shared.username = name
        objectWillChange.send()
        refresh()
    }

    /// Path ②: paste a Personal Access Token (enables auto username + private).
    func useToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        TokenStore.shared.token = t
        objectWillChange.send()
        refresh()
    }

    /// Path ③: OAuth web flow (mirrors Git Streaks; needs configured app + bundle).
    func signIn() {
        Task {
            do {
                _ = try await GitHubTokenRequester.shared.signIn()
                await MainActor.run { self.objectWillChange.send() }
                await load()
            } catch {
                await MainActor.run { self.errorText = "fetch token error: \(error)" }
            }
        }
    }

    func signOut() {
        TokenStore.shared.signOut()
        user = nil
        days = []
        stats = ContributionStats()
        avatar = nil
    }

    /// Trigger a background refresh of user + contributions.
    func refresh() {
        guard isSignedIn else { return }
        Task { await load() }
    }

    private func load() async {
        await MainActor.run { self.isLoading = true; self.errorText = nil }
        do {
            // Resolve which login to fetch. With a token we ask the API who we
            // are; otherwise we use the manually entered username.
            let resolvedUser: GitHubUser
            if TokenStore.shared.hasToken {
                resolvedUser = try await provider.fetchUser()
            } else if let name = TokenStore.shared.username, !name.isEmpty {
                resolvedUser = GitHubUser(login: name, name: name, avatarURL: avatarURL(for: name))
            } else {
                throw APIError.decode("no username or token configured")
            }
            TokenStore.shared.cachedLogin = resolvedUser.login
            let d = try await provider.fetchContributions(login: resolvedUser.login)
            let s = ContributionStats.compute(from: d)
            await MainActor.run {
                self.user = resolvedUser
                self.days = d
                self.stats = s
                self.isLoading = false
                self.lastUpdated = Date()
            }
            await loadAvatar(resolvedUser.avatarURL)
        } catch {
            await MainActor.run {
                self.errorText = "fetch contribution error: \(error)"
                self.isLoading = false
            }
        }
    }

    /// GitHub serves public avatars at this convenience redirect — no token.
    private func avatarURL(for login: String) -> String {
        "https://github.com/\(login).png?size=80"
    }

    private func loadAvatar(_ urlString: String?) async {
        guard let s = urlString, let url = URL(string: s),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: data) else { return }
        await MainActor.run { self.avatar = img }
    }

    // MARK: - Watched repos

    /// Add a folder (must be a git repo) to the watch list, then rescan.
    func addRepo(path: String) {
        guard GitService.isGitRepo(path) else {
            errorText = "Not a git repository: \(path)"
            return
        }
        WatchedReposStore.add(path)
        scanRepos()
    }

    func removeRepo(_ path: String) {
        WatchedReposStore.remove(path)
        scanRepos()
    }

    /// Refresh each watched repo's dirty count (off-main, then publish).
    func scanRepos() {
        let paths = WatchedReposStore.paths
        Task {
            let states: [RepoState] = paths.map { p in
                RepoState(path: p, name: GitService.repoName(p), dirtyCount: GitService.dirtyCount(p))
            }
            await MainActor.run { self.repos = states }
        }
    }

    /// Stage all, generate an AI message (or fall back), commit, and push.
    func commit(repo path: String) {
        setBusy(path, true)
        Task {
            let message: String
            if OpenRouterClient.isConfigured {
                let diff = GitService.diffForMessage(path)
                if let ai = try? await OpenRouterClient.commitMessage(for: diff), !ai.isEmpty {
                    message = ai
                } else {
                    message = fallbackMessage()
                }
            } else {
                message = fallbackMessage()
            }
            let result = GitService.commitAndPush(path, message: message)
            await MainActor.run {
                self.setBusy(path, false)
                self.updateRepo(path) {
                    $0.lastResult = result.ok ? "✓ \(message)" : "✗ \(result.output)"
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    private func fallbackMessage() -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        return "chore: update (\(df.string(from: Date())))"
    }

    /// Journal mode: append an AI-written line to `gipet-journal.md` and commit
    /// only that file. Keeps the streak green without touching real code.
    func journalCommit(repo path: String) {
        setBusy(path, true)
        Task {
            let line: String
            if OpenRouterClient.isConfigured, let ai = try? await OpenRouterClient.journalEntry(), !ai.isEmpty {
                line = ai
            } else {
                line = fallbackJournalLine()
            }
            let result = appendJournalAndCommit(path: path, line: line)
            await MainActor.run {
                self.setBusy(path, false)
                self.updateRepo(path) {
                    $0.lastResult = result.ok ? "📓 \(line)" : "✗ \(result.output)"
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    private func appendJournalAndCommit(path: String, line: String) -> GitResult {
        let fileName = "gipet-journal.md"
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let entry = "- \(df.string(from: Date())) — \(line)\n"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "# Gipet Journal 📓\n\n"
            try? (header + entry).write(to: fileURL, atomically: true, encoding: .utf8)
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            return GitResult(ok: false, output: "could not write \(fileName)")
        }
        let dfMsg = DateFormatter(); dfMsg.dateFormat = "yyyy-MM-dd"
        return GitService.commitFile(path, file: fileName, message: "docs: journal \(dfMsg.string(from: Date()))")
    }

    private func fallbackJournalLine() -> String {
        let lines = [
            "오늘도 한 걸음 전진 🌱",
            "작은 커밋이 모여 큰 프로젝트가 된다",
            "꾸준함이 실력이다 💪",
            "오늘의 나, 어제보다 한 줄 더",
            "잔디는 거짓말을 하지 않는다 🟩",
        ]
        return lines.randomElement() ?? "오늘도 커밋 완료"
    }

    private func setBusy(_ path: String, _ busy: Bool) {
        updateRepo(path) { $0.isBusy = busy }
    }

    private func updateRepo(_ path: String, _ change: (inout RepoState) -> Void) {
        guard let i = repos.firstIndex(where: { $0.path == path }) else { return }
        var r = repos[i]; change(&r); repos[i] = r
    }
}
