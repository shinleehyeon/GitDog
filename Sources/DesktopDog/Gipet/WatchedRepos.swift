// Gipet — persistence + runtime state for watched git repos.

import Foundation

/// Persisted list of watched repo paths with security-scoped bookmarks (App Sandbox).
enum WatchedReposStore {
    private static let pathsKey     = "Gipet.watchedRepos"
    private static let bookmarksKey = "Gipet.watchedRepoBookmarks"
    private static let d = UserDefaults.standard

    // Active security-scoped URLs kept alive for the session.
    private static var activeURLs: [String: URL] = [:]

    static var paths: [String] {
        get { d.stringArray(forKey: pathsKey) ?? [] }
        set { d.set(Array(Set(newValue)).sorted(), forKey: pathsKey) }
    }

    /// Add a repo from an NSOpenPanel URL — saves a security-scoped bookmark.
    static func add(_ url: URL) {
        let path = url.path
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            var all = savedBookmarks
            all[path] = bookmark
            d.set(all, forKey: bookmarksKey)
        }
        var p = paths
        if !p.contains(path) { p.append(path); paths = p }
        startAccessing(url: url, path: path)
    }

    static func remove(_ path: String) {
        paths = paths.filter { $0 != path }
        var all = savedBookmarks
        all.removeValue(forKey: path)
        d.set(all, forKey: bookmarksKey)
        if let url = activeURLs.removeValue(forKey: path) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Call at app launch — resolves all saved bookmarks and starts sandbox access.
    static func restoreAccess() {
        for (path, data) in savedBookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            startAccessing(url: url, path: path)
            if stale, let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                var all = savedBookmarks; all[path] = fresh; d.set(all, forKey: bookmarksKey)
            }
        }
    }

    @discardableResult
    private static func startAccessing(url: URL, path: String) -> Bool {
        guard activeURLs[path] == nil else { return true }
        let ok = url.startAccessingSecurityScopedResource()
        if ok { activeURLs[path] = url }
        return ok
    }

    private static var savedBookmarks: [String: Data] {
        d.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
}

/// Live state of one watched repo, shown in the popover.
struct RepoState: Identifiable, Equatable {
    let path: String
    var name: String
    var dirtyCount: Int = 0
    var isBusy: Bool = false
    var lastResult: String?

    var id: String { path }
    var isDirty: Bool { dirtyCount > 0 }
}
