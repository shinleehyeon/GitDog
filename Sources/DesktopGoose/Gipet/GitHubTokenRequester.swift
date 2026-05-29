// Gipet — GitHub OAuth web flow (mirrors Git Streaks' `GitHubTokenRequester`
// + `AppDeeplinkHandler`).
//
// Flow, identical in shape to Git Streaks:
//   1. Open the browser to  https://github.com/login/oauth/authorize
//      with redirect_uri = gipet://callback  (Git Streaks used githubstreak://).
//   2. GitHub redirects back to the app via the custom URL scheme with `?code=`.
//   3. Exchange the code at  https://github.com/login/oauth/access_token
//      for an access token, then persist it.
//
// ⚠️ Fill in your own OAuth app credentials below. Create one at
//    https://github.com/settings/developers  →  "New OAuth App"
//    Authorization callback URL:  gipet://callback
//    Then paste Client ID / Client Secret here.

import Foundation
import AppKit

enum GipetGitHub {
    // Registered OAuth app credentials (github.com/settings/developers).
    static let clientID     = "Ov23lianGqavYyWfNqjD"
    static let clientSecret = "2463d7139055509450cbd8d43e1e99c779bf4749"
    static let scope        = "read:user"
    static let callbackScheme = "gipet"
    static let redirectURI  = "gipet://callback"

    static var isConfigured: Bool {
        !clientID.hasPrefix("YOUR_") && !clientSecret.hasPrefix("YOUR_")
    }
}

/// Persists the GitHub access token + cached login. (UserDefaults for
/// simplicity; move to Keychain for production secrecy.)
final class TokenStore {
    static let shared = TokenStore()
    private let tokenKey = "Gipet.githubToken"
    private let loginKey = "Gipet.githubLogin"
    private let userKey  = "Gipet.githubUsername"
    private let d = UserDefaults.standard

    /// OAuth / Personal Access Token. Optional — only needed for username
    /// auto-detect (api.github.com/user) and private contributions.
    var token: String? {
        get { d.string(forKey: tokenKey) }
        set {
            d.set(newValue, forKey: tokenKey)
            APIClient.shared.accessToken = newValue
        }
    }
    /// Manually entered username — lets us load public contributions with no token.
    var username: String? {
        get { d.string(forKey: userKey) }
        set { d.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userKey) }
    }
    var cachedLogin: String? {
        get { d.string(forKey: loginKey) }
        set { d.set(newValue, forKey: loginKey) }
    }

    var hasToken: Bool { token?.isEmpty == false }
    var hasUsername: Bool { username?.isEmpty == false }
    /// "Signed in" = we have *some* way to load contributions.
    var isSignedIn: Bool { hasToken || hasUsername }

    func signOut() {
        token = nil
        username = nil
        cachedLogin = nil
    }

    private init() {
        // Re-arm the API client with any token saved from a previous session.
        APIClient.shared.accessToken = token
    }
}

struct AccessTokenResponse: Decodable {
    let access_token: String?
    let error: String?
    let error_description: String?
}

/// Drives the OAuth web flow and receives the deeplink callback.
final class GitHubTokenRequester {
    static let shared = GitHubTokenRequester()

    private var continuation: CheckedContinuation<String, Error>?
    private var state: String = ""

    /// Begin login: open the browser. Resolves with the access token once the
    /// deeplink callback arrives and the code is exchanged.
    func signIn() async throws -> String {
        guard GipetGitHub.isConfigured else {
            throw APIError.decode("OAuth not configured — set GipetGitHub.clientID/clientSecret")
        }
        // A non-cryptographic anti-CSRF nonce derived from process+time inputs.
        state = "gipet-\(ProcessInfo.processInfo.globallyUniqueString.prefix(12))"

        var comps = URLComponents(string: "https://github.com/login/oauth/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: GipetGitHub.clientID),
            URLQueryItem(name: "redirect_uri", value: GipetGitHub.redirectURI),
            URLQueryItem(name: "scope", value: GipetGitHub.scope),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = comps.url else { throw APIError.badURL }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            NSWorkspace.shared.open(url)
        }
    }

    /// Called by AppDeeplinkHandler / application(open:) when
    /// `gipet://callback?...` is opened.
    func handleCallback(_ url: URL) {
        NSLog("[Gipet] callback received: \(url.absoluteString)")
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = comps.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            NSLog("[Gipet] callback missing code")
            continuation?.resume(throwing: APIError.decode("oauth callback missing code"))
            continuation = nil
            return
        }
        // State is a CSRF nonce. We log a mismatch but don't hard-fail: on a
        // freshly-launched instance handling the URL, `state` is empty, yet we
        // still want to complete the exchange so the user isn't stuck.
        let returnedState = items.first(where: { $0.name == "state" })?.value
        if !state.isEmpty, returnedState != state {
            NSLog("[Gipet] oauth state mismatch (expected \(state), got \(returnedState ?? "nil"))")
        }
        Task { await exchange(code: code) }
    }

    private func exchange(code: String) async {
        do {
            guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
                throw APIError.badURL
            }
            let resp = try await APIClient.shared.post(AccessTokenResponse.self, url, form: [
                "client_id": GipetGitHub.clientID,
                "client_secret": GipetGitHub.clientSecret,
                "code": code,
                "redirect_uri": GipetGitHub.redirectURI,
                "state": state,
            ])
            guard let token = resp.access_token, !token.isEmpty else {
                throw APIError.decode(resp.error_description ?? resp.error ?? "no access_token")
            }
            NSLog("[Gipet] token exchange ok")
            TokenStore.shared.token = token
            continuation?.resume(returning: token)
            // Update the UI even if no signIn() continuation is pending
            // (e.g. a freshly-launched instance handled the callback).
            await MainActor.run {
                GipetViewModel.shared.objectWillChange.send()
                GipetViewModel.shared.refresh()
            }
        } catch {
            NSLog("[Gipet] token exchange failed: \(error)")
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

/// Handles the `gipet://` custom URL scheme (mirrors `AppDeeplinkHandler`).
final class AppDeeplinkHandler: NSObject {
    static let shared = AppDeeplinkHandler()

    /// Register for GetURL apple events. Call from applicationWillFinishLaunching.
    func register() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: str) else { return }
        if url.scheme == GipetGitHub.callbackScheme {
            GitHubTokenRequester.shared.handleCallback(url)
        }
    }
}
