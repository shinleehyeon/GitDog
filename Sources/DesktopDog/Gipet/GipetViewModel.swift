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
    /// Commits / PRs / reviews / issues mix for the activity graph page.
    @Published var activity = ContributionActivity()
    @Published var avatar: NSImage?
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var lastUpdated: Date?
    /// Desktop sprite. The menu-bar popover stays up either way.
    @Published var dogVisible: Bool = GipetViewModel.storedDogVisible

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
        activity = ContributionActivity()
        avatar = nil
    }

    // Detects when an in-flight fetch has been superseded by a newer one
    // started after it (30s timer firing again, manual refresh, etc. while a
    // previous fetch is still in flight) — without this a slow-but-earlier
    // fetch can complete AFTER a fast-but-later one and silently overwrite
    // fresher state with stale data. See LatestWinsGuardTests.
    private let loadGuard = LatestWinsGuard()

    /// Trigger a background refresh of user + contributions.
    func refresh() {
        guard isSignedIn else { return }
        Task { await load() }
    }

    /// Ask the dog to spawn/throw a ball. Crosses into AppKit territory via
    /// NotificationCenter, same pattern as behaviorSettingsChanged/appearanceSettingsChanged.
    func throwBall() {
        if !dogVisible { setDogVisible(true) }
        NotificationCenter.default.post(name: .throwBallRequested, object: nil)
    }

    func toggleDog() {
        setDogVisible(!dogVisible)
    }

    func setDogVisible(_ visible: Bool) {
        guard dogVisible != visible else { return }
        dogVisible = visible
        UserDefaults.standard.set(visible, forKey: Self.dogVisibleKey)
        NotificationCenter.default.post(name: .dogVisibilityChanged, object: nil,
                                        userInfo: ["visible": visible])
    }

    /// Merge fresh data with what's currently displayed, keeping today's cell
    /// from regressing below what's already shown. GitHub's public page is
    /// CDN-cached and the Events/GraphQL overlays can each independently lag,
    /// so a fresh fetch can occasionally read a lower "today" value than one
    /// we already displayed — that's a stale read, not a real decrease, since
    /// a day's contribution count only ever goes up. Pure/no I/O so it's unit
    /// testable independent of network timing — see GipetViewModelMergeTests.
    static func applyMonotonicToday(old: [ContributionDay], fresh: [ContributionDay],
                                     calendar: Calendar = .current) -> [ContributionDay] {
        var merged = fresh
        if let oldToday = old.first(where: { calendar.isDateInToday($0.date) }),
           let idx = merged.firstIndex(where: { calendar.isDateInToday($0.date) }),
           oldToday.count > merged[idx].count {
            merged[idx] = oldToday
        }
        return merged
    }

    private func load() async {
        let ticket = loadGuard.nextTicket()
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
            async let contribs = provider.fetchContributions(login: resolvedUser.login)
            // Activity mix needs a token (GraphQL); skip quietly for username-only.
            async let activityFetch: ContributionActivity? = {
                guard TokenStore.shared.hasToken else { return nil }
                return try? await provider.fetchContributionActivity()
            }()
            let d = try await contribs
            let act = await activityFetch
            guard loadGuard.isLatest(ticket) else { return }  // superseded — discard
            await MainActor.run {
                let merged = Self.applyMonotonicToday(old: self.days, fresh: d)
                self.user = resolvedUser
                self.days = merged
                self.stats = ContributionStats.compute(from: merged)
                if let act { self.activity = act }
                self.isLoading = false
                self.lastUpdated = Date()
            }
            await loadAvatar(resolvedUser.avatarURL)
        } catch {
            guard loadGuard.isLatest(ticket) else { return }  // superseded — discard
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
    func addRepo(url: URL) {
        let path = url.path
        guard GitService.isGitRepo(path) else {
            errorText = "Not a git repository: \(path)"
            return
        }
        WatchedReposStore.add(url)
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
    /// Clean streak repos (e.g. Classes/streaks) auto-append the next book/journal
    /// line first so there's always something to commit.
    func commit(repo path: String) {
        setBusy(path, true)
        Task {
            // Sync first so auto-written journal isn't based on a stale tip —
            // and so a later hard-reset doesn't wipe freshly written content.
            if GitService.dirtyCount(path) == 0 {
                _ = await GitService.syncToOrigin(path)
            }
            let prepared = await prepareCommit(path: path)
            guard prepared.error == nil else {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) { $0.lastResult = "✗ \(prepared.error!)" }
                }
                return
            }
            let result: GitResult
            if prepared.autoFile != nil {
                result = await GitService.commitFile(path, file: prepared.autoFile!, message: prepared.message)
            } else {
                result = await GitService.commitAndPush(path, message: prepared.message)
            }
            await MainActor.run {
                if result.ok, let next = prepared.bookNextIndex {
                    BookSource.setIndex(next, forRepo: path)
                }
                self.setBusy(path, false)
                self.updateRepo(path) {
                    $0.lastResult = result.ok ? "✓ \(prepared.message)" : "✗ \(result.output)"
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    /// Sync → auto content → branch → commit → push → PR → merge.
    func createAndMergePR(repo path: String) {
        // Guard double-taps: two overlapping runs create conflicting OPEN PRs
        // for the same book paragraph (seen as #7 + #8 both book:399).
        if repos.first(where: { $0.path == path })?.isBusy == true { return }
        setBusy(path, true)
        Task {
            // Hard reset would destroy local WIP (happened on desktop-dog).
            let wip = GitService.unrelatedDirtyPaths(path)
            if !wip.isEmpty {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) {
                        $0.lastResult = "✗ 로컬 수정 있음 — 커밋/스태시 후 PR 하세요 (\(wip.prefix(3).joined(separator: ", ")))"
                    }
                }
                return
            }
            // Order matters: sync (hard reset) MUST run before we write the
            // next book/journal line. Doing it inside commitPushPRAndMerge
            // after prepareCommit wiped the new edits → "변경사항이 없어요".
            if !(await GitService.syncToOrigin(path)) {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) {
                        $0.lastResult = "✗ origin 동기화 실패 — 네트워크/토큰을 확인해요"
                    }
                }
                return
            }
            let prepared = await prepareCommit(path: path)
            guard prepared.error == nil else {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) { $0.lastResult = "✗ \(prepared.error!)" }
                }
                return
            }
            await MainActor.run {
                self.updateRepo(path) { $0.lastResult = "PR → Approve/Comment → 머지…" }
            }
            let result = await GitService.commitPushPRAndMerge(path, message: prepared.message)
            await MainActor.run {
                if result.ok, let next = prepared.bookNextIndex {
                    BookSource.setIndex(next, forRepo: path)
                }
                self.setBusy(path, false)
                self.updateRepo(path) {
                    if result.ok {
                        // result.output looks like "PR#12 · Approve · https://…"
                        $0.lastResult = "✓ \(result.output) · \(prepared.message)"
                    } else {
                        $0.lastResult = "✗ \(result.output)"
                    }
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    /// Open (then close) a GitHub issue — counts toward the Issues activity axis.
    func createIssue(repo path: String) {
        if repos.first(where: { $0.path == path })?.isBusy == true { return }
        setBusy(path, true)
        Task {
            guard let info = GitHubPRService.repoInfo(at: path) else {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) { $0.lastResult = "✗ GitHub origin을 찾을 수 없어요" }
                }
                return
            }
            guard TokenStore.shared.token?.isEmpty == false else {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) { $0.lastResult = "✗ GitHub 토큰이 필요해요" }
                }
                return
            }

            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
            let stamp = df.string(from: Date())
            let title = GitHubPRService.formatTitle(description: "issue \(stamp)")
            let body = """
            ## gipet issue
            Auto-opened from the desktop app so it counts toward GitHub **Issues** activity.

            - repo: `\(info.owner)/\(info.repo)`
            - at: \(stamp)
            """

            await MainActor.run {
                self.updateRepo(path) { $0.lastResult = "Issue 생성 중…" }
            }

            do {
                let issue = try await GitHubPRService.createIssue(
                    owner: info.owner, repo: info.repo, title: title, body: body
                )
                // Cleanup noise; opening already counted.
                await GitHubPRService.closeIssue(
                    owner: info.owner, repo: info.repo, number: issue.number
                )
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) {
                        $0.lastResult = "✓ Issue#\(issue.number) opened+closed"
                    }
                }
            } catch {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) { $0.lastResult = "✗ Issue 실패: \(error)" }
                }
            }
        }
    }

    private struct PreparedCommit {
        var message: String = ""
        var autoFile: String? = nil       // set when we wrote gipet-journal.md
        var bookNextIndex: Int? = nil     // advance BookSource on success
        var error: String? = nil
    }

    /// If the repo is clean, invent content (book paragraph or journal line).
    /// If already dirty, keep those changes and AI-label them.
    private func prepareCommit(path: String) async -> PreparedCommit {
        if GitService.dirtyCount(path) > 0 {
            return PreparedCommit(message: await commitMessage(for: path))
        }
        // streaks-style: auto-create the next journal/book entry.
        if BookSource.isAvailable(forRepo: path) {
            let paras = BookSource.paragraphs(forRepo: path)
            let idx = BookSource.currentIndex(forRepo: path)
            guard idx < paras.count else {
                return PreparedCommit(message: "", error: "책 끝! (\(paras.count)문단 완료)")
            }
            if let err = appendToJournalFile(path: path, block: paras[idx] + "\n\n") {
                return PreparedCommit(message: "", error: err)
            }
            return PreparedCommit(
                message: "book: \(idx + 1)/\(paras.count)",
                autoFile: "gipet-journal.md",
                bookNextIndex: idx + 1
            )
        }
        let line: String
        if OpenRouterClient.isConfigured, let ai = try? await OpenRouterClient.journalEntry(), !ai.isEmpty {
            line = ai
        } else {
            line = fallbackJournalLine()
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let entry = "- \(df.string(from: Date())) — \(line)\n"
        let header = "# Gipet Journal 📓\n\n"
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent("gipet-journal.md")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            if let err = writeJournal(fileURL, content: header + entry) {
                return PreparedCommit(message: "", error: err)
            }
        } else if let err = appendToJournalFile(path: path, block: entry) {
            return PreparedCommit(message: "", error: err)
        }
        let dfMsg = DateFormatter(); dfMsg.dateFormat = "yyyy-MM-dd"
        return PreparedCommit(
            message: "docs: journal \(dfMsg.string(from: Date()))",
            autoFile: "gipet-journal.md"
        )
    }

    private func appendToJournalFile(path: String, block: String) -> String? {
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent("gipet-journal.md")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return writeJournal(fileURL, content: block)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return "could not write gipet-journal.md"
        }
        handle.seekToEndOfFile()
        handle.write(block.data(using: .utf8) ?? Data())
        try? handle.close()
        return nil
    }

    private func writeJournal(_ url: URL, content: String) -> String? {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "could not create gipet-journal.md: \(error.localizedDescription)"
        }
    }

    private func commitMessage(for path: String) async -> String {
        if OpenRouterClient.isConfigured {
            let diff = GitService.diffForMessage(path)
            if let ai = try? await OpenRouterClient.commitMessage(for: diff), !ai.isEmpty {
                return ai
            }
        }
        return fallbackMessage()
    }

    private func fallbackMessage() -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        return "chore: update (\(df.string(from: Date())))"
    }

    /// Journal mode: append an AI-written line to `gipet-journal.md` and commit
    /// only that file. Keeps the streak green without touching real code.
    func journalCommit(repo path: String) {
        // Local-only book mode: when explicitly enabled + a book file exists,
        // write the book out one paragraph per commit instead of the AI journal.
        // Off by default, so shipped builds keep the normal journal.
        if BookSource.isAvailable(forRepo: path) { bookCommit(repo: path); return }
        setBusy(path, true)
        Task {
            let line: String
            if OpenRouterClient.isConfigured, let ai = try? await OpenRouterClient.journalEntry(), !ai.isEmpty {
                line = ai
            } else {
                line = fallbackJournalLine()
            }
            let result = await appendJournalAndCommit(path: path, line: line)
            await MainActor.run {
                self.setBusy(path, false)
                self.updateRepo(path) {
                    $0.lastResult = result.ok ? "📓 \(line)" : "✗ \(result.output)"
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    private func appendJournalAndCommit(path: String, line: String) async -> GitResult {
        let fileName = "gipet-journal.md"
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let entry = "- \(df.string(from: Date())) — \(line)\n"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "# Gipet Journal 📓\n\n"
            do {
                try (header + entry).write(to: fileURL, atomically: true, encoding: .utf8)
                NSLog("[Gipet] journal created: %@", fileURL.path)
            } catch {
                NSLog("[Gipet] journal create failed: %@", error.localizedDescription)
                return GitResult(ok: false, output: "could not create \(fileName): \(error.localizedDescription)")
            }
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            try? handle.close()
            NSLog("[Gipet] journal appended: %@", fileURL.path)
        } else {
            let readable = FileManager.default.isReadableFile(atPath: fileURL.path)
            let writable = FileManager.default.isWritableFile(atPath: fileURL.path)
            NSLog("[Gipet] journal write failed — readable=%d writable=%d path=%@", readable, writable, fileURL.path)
            return GitResult(ok: false, output: "could not write \(fileName)")
        }
        let dfMsg = DateFormatter(); dfMsg.dateFormat = "yyyy-MM-dd"
        let result = await GitService.commitFile(path, file: fileName, message: "docs: journal \(dfMsg.string(from: Date()))")
        NSLog("[Gipet] commitFile result: ok=%d output=%@", result.ok, result.output)
        return result
    }

    /// Local book mode: append the next paragraph of the external book file to
    /// `gipet-journal.md` and commit only that file. Advances the saved index
    /// only when the commit succeeds.
    private func bookCommit(repo path: String) {
        setBusy(path, true)
        Task {
            let paras = BookSource.paragraphs(forRepo: path)
            let idx = BookSource.currentIndex(forRepo: path)
            guard idx < paras.count else {
                await MainActor.run {
                    self.setBusy(path, false)
                    self.updateRepo(path) {
                        $0.lastResult = "📖 책 끝! (\(paras.count)문단 완료)"
                    }
                }
                return
            }
            let para = paras[idx]
            let result = await appendBookAndCommit(path: path, paragraph: para,
                                                   index: idx, total: paras.count)
            await MainActor.run {
                self.setBusy(path, false)
                if result.ok { BookSource.setIndex(idx + 1, forRepo: path) }
                self.updateRepo(path) {
                    let preview = para.replacingOccurrences(of: "\n", with: " ").prefix(20)
                    $0.lastResult = result.ok
                        ? "📖 \(idx + 1)/\(paras.count) — \(preview)…"
                        : "✗ \(result.output)"
                    $0.dirtyCount = GitService.dirtyCount(path)
                }
            }
        }
    }

    private func appendBookAndCommit(path: String, paragraph: String,
                                     index: Int, total: Int) async -> GitResult {
        let fileName = "gipet-journal.md"
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent(fileName)
        let block = paragraph + "\n\n"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try block.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                return GitResult(ok: false, output: "could not create \(fileName): \(error.localizedDescription)")
            }
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(block.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            return GitResult(ok: false, output: "could not write \(fileName)")
        }

        return await GitService.commitFile(path, file: fileName, message: "book: \(index + 1)/\(total)")
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

extension GipetViewModel {
    static let dogVisibleKey = "GitDog.visible"

    static var storedDogVisible: Bool {
        guard UserDefaults.standard.object(forKey: dogVisibleKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: dogVisibleKey)
    }
}

extension Notification.Name {
    static let throwBallRequested = Notification.Name("ThrowBallRequested")
    static let dogVisibilityChanged = Notification.Name("DogVisibilityChanged")
}
