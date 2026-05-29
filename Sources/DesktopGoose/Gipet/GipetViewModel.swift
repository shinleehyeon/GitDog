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

    var isSignedIn: Bool { TokenStore.shared.isSignedIn }

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
}
