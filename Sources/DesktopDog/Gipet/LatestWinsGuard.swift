// A monotonic ticket dispenser used to detect when an in-flight async result
// has been superseded by a newer attempt started after it (e.g. the
// contribution refresh timer firing again, or a manual refresh, while a
// previous fetch is still in flight). Without this, a slow-but-earlier fetch
// can complete AFTER a fast-but-later one and silently overwrite fresher
// state with stale data.
final class LatestWinsGuard {
    private var current = 0

    /// Call once at the start of an attempt; returns a ticket to check later.
    func nextTicket() -> Int {
        current += 1
        return current
    }

    /// True if `ticket` is still the most recent one issued — i.e. no newer
    /// attempt has started since. Call right before committing a result.
    func isLatest(_ ticket: Int) -> Bool {
        ticket == current
    }
}
