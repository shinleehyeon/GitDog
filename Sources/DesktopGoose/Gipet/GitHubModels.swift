// Gipet — GitHub contribution data models.
// Reconstructed to mirror Git Streaks' observed types: ContributionStats,
// lastYearContributions, ProfileHeaderView's user model.

import Foundation

/// One cell of the contribution calendar.
struct ContributionDay: Codable, Equatable {
    let date: Date          // local-midnight date
    let count: Int          // exact contribution count for that day
    let level: Int          // 0...4, matches GitHub's data-level

    var isContribution: Bool { count > 0 || level > 0 }
}

/// Authenticated GitHub user (from https://api.github.com/user).
struct GitHubUser: Codable, Equatable {
    let login: String
    let name: String?
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarURL = "avatar_url"
    }

    var displayName: String { name?.isEmpty == false ? name! : login }
}

/// Computed streak/total figures shown in StatsView.
/// Mirrors Git Streaks' `ContributionStats` / `lastYearContributions`.
struct ContributionStats: Equatable {
    var todayCount: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var totalLastYear: Int = 0
    var bestDay: Int = 0

    /// The core signal the dog reacts to: did the user contribute today?
    var committedToday: Bool { todayCount > 0 }

    /// Build stats from a full day list (must be sorted ascending by date).
    static func compute(from days: [ContributionDay], calendar: Calendar = .current) -> ContributionStats {
        var stats = ContributionStats()
        guard !days.isEmpty else { return stats }

        let sorted = days.sorted { $0.date < $1.date }
        stats.totalLastYear = sorted.reduce(0) { $0 + $1.count }
        stats.bestDay = sorted.map(\.count).max() ?? 0

        let today = calendar.startOfDay(for: .distantFutureSafeNow())
        if let todayDay = sorted.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            stats.todayCount = todayDay.count
        }

        // Longest streak: the longest run of consecutive contribution days.
        var run = 0
        for day in sorted {
            if day.isContribution {
                run += 1
                stats.longestStreak = max(stats.longestStreak, run)
            } else {
                run = 0
            }
        }

        // Current streak: count back from today. Today being 0 is a "grace"
        // day (the streak only breaks once the day ends), matching how
        // contribution-streak trackers behave.
        let byDay = Dictionary(uniqueKeysWithValues: sorted.map {
            (calendar.startOfDay(for: $0.date), $0)
        })
        var cursor = today
        var current = 0
        var isFirst = true
        while let day = byDay[cursor] {
            if day.isContribution {
                current += 1
            } else if !isFirst {
                break   // a real gap before today ends the streak
            }
            isFirst = false
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        stats.currentStreak = current
        return stats
    }
}

private extension Date {
    /// `Date()` is unavailable in some sandboxed contexts; this is the normal
    /// wall-clock "now" used everywhere in the app.
    static func distantFutureSafeNow() -> Date { Date() }
}
