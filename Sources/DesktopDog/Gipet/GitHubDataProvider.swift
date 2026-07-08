// Gipet — GitHub data provider.
// Mirrors Git Streaks' `GitHubDataProvider`: it pulls the public contribution
// calendar HTML from github.com (no auth needed for public profiles) and the
// signed-in user object from the REST API.
//
// Endpoints (same as observed in the Git Streaks binary):
//   https://github.com/users/<login>/contributions?from=<yyyy-MM-dd>&to=<yyyy-MM-dd>
//   https://api.github.com/user

import Foundation

final class GitHubDataProvider {
    static let shared = GitHubDataProvider()

    private let api = APIClient.shared

    // MARK: - User

    /// The signed-in user. Requires a token to have been set on APIClient.
    func fetchUser() async throws -> GitHubUser {
        guard let url = URL(string: "https://api.github.com/user") else { throw APIError.badURL }
        return try await api.json(GitHubUser.self, url, authorized: true)
    }

    // MARK: - Contributions

    /// Fetch the current calendar year's contribution days for `login`.
    ///
    /// We deliberately scrape the **public** contributions page (anonymously —
    /// `APIClient.text` never sends the token) instead of the authenticated
    /// GraphQL API. Reason: the GraphQL `contributionsCollection` seen through an
    /// OAuth-app token *undercounts* — it omits commits to org/restricted repos
    /// the app isn't approved for (measured: 624 vs the public 1306 over a
    /// trailing year). The public page is exactly what visitors see, so our
    /// numbers match the profile ("N contributions in <year>").
    ///
    /// Windowed to the current year via `?from=<year>-01-01&to=<year>-12-31`
    /// (same query shape Git Streaks uses) so the total lines up with the
    /// profile's default year view rather than a trailing-365-day sum.
    ///
    /// Tradeoff: the anonymous page is CDN-cached, so *today's* freshly-pushed
    /// commits can lag a few minutes (today may briefly read 0). Private commits
    /// never appear here at all — by design, since the public graph hides them.
    func fetchContributions(login: String) async throws -> [ContributionDay] {
        var days = try await fetchViaHTML(login: login, year: Self.currentYear)

        // The windowed (?from&to) view that gives us a clean calendar-year total
        // lags the default profile view for the most recent day(s): a commit can
        // already show on the profile while the windowed view still reads the old
        // count. So overlay the fresher per-day counts from the default page
        // (keyed by full yyyy-MM-dd, so 2025/2026 never collide), keeping the
        // higher of the two.
        if let fresh = try? await fetchDefaultHTML(login: login) {
            var freshByDate: [String: ContributionDay] = [:]
            for d in fresh { freshByDate[Self.dayKey(d.date)] = d }
            days = days.map { d in
                if let f = freshByDate[Self.dayKey(d.date)], f.count > d.count { return f }
                return d
            }
        }

        // Overlay today's count from GraphQL (authenticated, not CDN-cached)
        // so private repo commits are reflected immediately.
        let htmlTodayCount = days.first(where: { Calendar.current.isDateInToday($0.date) })?.count ?? 0
        // Each overlay source is fetched independently — a failure/throw in one
        // (rate limit, decode error, no token) must not discard a successful
        // result from the other, or we'd silently fall back to the stale
        // CDN-cached html count and flicker back down on transient errors.
        let eventsCount = (try? await fetchTodayPushCount(login: login)) ?? 0
        let cal = Calendar.current
        let graphqlTodayCount: Int
        if let graphqlDays = try? await fetchViaGraphQL() {
            graphqlTodayCount = graphqlDays.first(where: { cal.isDateInToday($0.date) })?.count ?? 0
        } else {
            graphqlTodayCount = 0
        }
        let bestCount = max(htmlTodayCount, eventsCount, graphqlTodayCount)
        NSLog("[Gipet] today: html=%d events=%d graphql=%d", htmlTodayCount, eventsCount, graphqlTodayCount)
        if bestCount > htmlTodayCount {
            var foundToday = false
            days = days.map { d in
                guard cal.isDateInToday(d.date) else { return d }
                foundToday = true
                return ContributionDay(date: d.date, count: bestCount, level: max(d.level, 1))
            }
            // Today's entry may be absent from the HTML calendar (CDN lag / new day).
            if !foundToday {
                days.append(ContributionDay(date: Date(), count: bestCount, level: min(bestCount, 4)))
                days.sort { $0.date < $1.date }
            }
        }

        return days
    }

    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dayKey(_ date: Date) -> String { keyFormatter.string(from: date) }

    // MARK: - Events API (private commit detection)

    private struct GitHubEvent: Decodable {
        let type: String
        let created_at: String
        struct Payload: Decodable { let size: Int? }
        let payload: Payload?
    }

    /// Count commits pushed today (local time) via the authenticated Events API.
    /// Catches private repo commits that anonymous HTML scraping misses.
    /// Returns 0 if no token or if the call fails.
    func fetchTodayPushCount(login: String) async throws -> Int {
        guard api.accessToken != nil else { return 0 }
        guard let url = URL(string: "https://api.github.com/users/\(login)/events?per_page=100") else {
            throw APIError.badURL
        }
        let events = try await api.json([GitHubEvent].self, url, authorized: true)
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return events
            .filter { $0.type == "PushEvent" }
            .filter { e in
                guard let date = iso.date(from: e.created_at) else { return false }
                return cal.isDateInToday(date)
            }
            .reduce(0) { $0 + ($1.payload?.size ?? 0) }
    }

    private func fetchViaHTML(login: String, year: Int) async throws -> [ContributionDay] {
        let path = "https://github.com/users/\(login)/contributions?from=\(year)-01-01&to=\(year)-12-31"
        return try await fetchHTML(path: path)
    }

    /// The default profile contributions page (no from/to) — fresher for today,
    /// but spans a trailing ~year, so it's only used to overlay recent days.
    private func fetchDefaultHTML(login: String) async throws -> [ContributionDay] {
        try await fetchHTML(path: "https://github.com/users/\(login)/contributions")
    }

    private func fetchHTML(path: String) async throws -> [ContributionDay] {
        guard let url = URL(string: path) else { throw APIError.badURL }
        let html = try await api.text(url)
        let days = Self.parseContributions(html: html)
        guard !days.isEmpty else { throw APIError.decode("contributions must be not empty") }
        return days
    }

    // MARK: - GraphQL

    private struct GraphQLResponse: Decodable {
        struct DataField: Decodable { let viewer: Viewer }
        struct Viewer: Decodable { let contributionsCollection: Collection }
        struct Collection: Decodable { let contributionCalendar: Calendar }
        struct Calendar: Decodable { let weeks: [Week] }
        struct Week: Decodable { let contributionDays: [Day] }
        struct Day: Decodable {
            let date: String
            let contributionCount: Int
            let contributionLevel: String
        }
        let data: DataField
    }

    func fetchViaGraphQL() async throws -> [ContributionDay] {
        guard let token = api.accessToken else { throw APIError.decode("no token") }
        guard let url = URL(string: "https://api.github.com/graphql") else { throw APIError.badURL }
        let query = "query{viewer{contributionsCollection{contributionCalendar{weeks{contributionDays{date contributionCount contributionLevel}}}}}}"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Gipet", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"

        var days: [ContributionDay] = []
        for week in decoded.data.viewer.contributionsCollection.contributionCalendar.weeks {
            for d in week.contributionDays {
                guard let date = fmt.date(from: d.date) else { continue }
                days.append(ContributionDay(date: date,
                                            count: d.contributionCount,
                                            level: Self.level(from: d.contributionLevel)))
            }
        }
        return days.sorted { $0.date < $1.date }
    }

    private static func level(from level: String) -> Int {
        switch level {
        case "FIRST_QUARTILE":  return 1
        case "SECOND_QUARTILE": return 2
        case "THIRD_QUARTILE":  return 3
        case "FOURTH_QUARTILE": return 4
        default:                return 0   // NONE
        }
    }

    // MARK: - HTML parsing

    /// Parse GitHub's contributions HTML into day cells.
    ///
    /// Modern GitHub markup:
    ///   <td ... class="ContributionCalendar-day" data-date="2024-12-05"
    ///       data-level="3" id="contribution-day-component-4-1" ...>
    ///   <tool-tip for="contribution-day-component-4-1" ...>12 contributions on December 5th.</tool-tip>
    ///
    /// We read date+level from each <td>, and the exact count from the matching
    /// <tool-tip> (joined by id). Count regex mirrors Git Streaks':
    /// `(\d+|No) contributions? on`.
    static func parseContributions(html: String) -> [ContributionDay] {
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)

        // id -> (date, level), and id -> exact count.
        struct Cell { var date: Date; var level: Int }
        var cells: [String: Cell] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"

        // Match each <td ...> opening tag that carries a data-date.
        let tdRe = try! NSRegularExpression(pattern: "<td\\b[^>]*data-date=\"([0-9]{4}-[0-9]{2}-[0-9]{2})\"[^>]*>", options: [])
        for m in tdRe.matches(in: html, options: [], range: full) {
            let tag = ns.substring(with: m.range)
            let dateStr = ns.substring(with: m.range(at: 1))
            guard let date = fmt.date(from: dateStr) else { continue }
            let level = firstInt(in: tag, attribute: "data-level") ?? 0
            // id lets us join to the tool-tip; if absent we key by date string.
            let id = firstString(in: tag, attribute: "id") ?? dateStr
            cells[id] = Cell(date: date, level: level)
            order.append(id)
            // Some markup variants put the count directly on the td as data-count.
            if let c = firstInt(in: tag, attribute: "data-count") {
                counts[id] = c
            }
        }

        // tool-tip text -> exact counts, joined to cells by `for`.
        let tipRe = try! NSRegularExpression(
            pattern: "<tool-tip\\b[^>]*\\bfor=\"([^\"]+)\"[^>]*>\\s*(\\d+|No)\\s+contributions?\\s+on",
            options: [.caseInsensitive])
        for m in tipRe.matches(in: html, options: [], range: full) {
            let id = ns.substring(with: m.range(at: 1))
            let n = ns.substring(with: m.range(at: 2))
            counts[id] = (n.lowercased() == "no") ? 0 : (Int(n) ?? 0)
        }

        var result: [ContributionDay] = []
        for id in order {
            guard let cell = cells[id] else { continue }
            // Prefer exact tool-tip/data-count; otherwise infer from level
            // (level 0 -> 0, level >0 -> at least 1 so streaks still count).
            let count = counts[id] ?? (cell.level > 0 ? 1 : 0)
            result.append(ContributionDay(date: cell.date, count: count, level: cell.level))
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func firstInt(in tag: String, attribute: String) -> Int? {
        guard let s = firstString(in: tag, attribute: attribute) else { return nil }
        return Int(s)
    }

    private static func firstString(in tag: String, attribute: String) -> String? {
        let ns = tag as NSString
        let re = try! NSRegularExpression(pattern: "\\b\(attribute)=\"([^\"]*)\"", options: [])
        guard let m = re.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
