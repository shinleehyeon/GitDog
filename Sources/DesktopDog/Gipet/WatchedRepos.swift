// Gipet — persistence + runtime state for watched git repos.

import Foundation

/// Persisted list of watched repo paths.
enum WatchedReposStore {
    private static let key = "Gipet.watchedRepos"
    private static let d = UserDefaults.standard

    static var paths: [String] {
        get { d.stringArray(forKey: key) ?? [] }
        set { d.set(Array(Set(newValue)).sorted(), forKey: key) }
    }

    static func add(_ path: String) {
        var p = paths
        if !p.contains(path) { p.append(path); paths = p }
    }

    static func remove(_ path: String) {
        paths = paths.filter { $0 != path }
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
