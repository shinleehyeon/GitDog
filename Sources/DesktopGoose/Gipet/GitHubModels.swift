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
    var dayCount: Int = 0

    // Date ranges (for the StatsView cards).
    var firstDate: Date?
    var lastDate: Date?
    var bestDayDate: Date?
    var longestStart: Date?
    var longestEnd: Date?
    var currentStart: Date?
    var currentEnd: Date?

    /// Average contributions/day across the window.
    var average: Double { dayCount > 0 ? Double(totalLastYear) / Double(dayCount) : 0 }

    /// The core signal the dog reacts to: did the user contribute today?
    var committedToday: Bool { todayCount > 0 }

    /// Build stats from a full day list (must be sorted ascending by date).
    static func compute(from days: [ContributionDay], calendar: Calendar = .current) -> ContributionStats {
        var stats = ContributionStats()
        guard !days.isEmpty else { return stats }

        let sorted = days.sorted { $0.date < $1.date }
        stats.totalLastYear = sorted.reduce(0) { $0 + $1.count }
        stats.dayCount = sorted.count
        stats.firstDate = sorted.first?.date
        stats.lastDate = sorted.last?.date

        // Best day (max count) + its date.
        if let best = sorted.max(by: { $0.count < $1.count }) {
            stats.bestDay = best.count
            stats.bestDayDate = best.date
        }

        // "Today" = the local calendar day. If GitHub hasn't recorded a cell
        // for today yet (its graph runs on UTC), today's count is simply 0,
        // which is what we want — you haven't contributed *today* yet.
        let today = calendar.startOfDay(for: Date())
        stats.todayCount = sorted.first(where: { calendar.isDate($0.date, inSameDayAs: today) })?.count ?? 0

        // Longest streak: the longest run of consecutive contribution days,
        // tracking the start/end dates of the best run.
        var run = 0
        var runStart: Date?
        for day in sorted {
            if day.isContribution {
                if run == 0 { runStart = day.date }
                run += 1
                if run > stats.longestStreak {
                    stats.longestStreak = run
                    stats.longestStart = runStart
                    stats.longestEnd = day.date
                }
            } else {
                run = 0
            }
        }

        // Current streak: consecutive contribution days ending today. Today
        // having no contribution yet is a "grace" day — we step back to
        // yesterday so the streak only breaks once the day actually ends.
        // (Set-based so it works even when today's cell isn't in the data yet,
        //  e.g. right after midnight before GitHub adds the new column.)
        let contribDates = Set(sorted.filter { $0.isContribution }
            .map { calendar.startOfDay(for: $0.date) })
        var cursor = today
        if !contribDates.contains(cursor) {                 // grace for today
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var current = 0
        var streakStart: Date?
        var streakEnd: Date?
        while contribDates.contains(cursor) {
            current += 1
            if streakEnd == nil { streakEnd = cursor }
            streakStart = cursor
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        stats.currentStreak = current
        stats.currentStart = streakStart ?? today
        stats.currentEnd = streakEnd ?? today
        return stats
    }
}
