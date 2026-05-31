// Gipet — popover UI (wide dark layout).
//   ContributionView { ProfileHeaderView, ContributionGrid, StatsView }
// Hovering a square grows it and shows an "N contributions on <date>" bubble.

import SwiftUI
import AppKit

// MARK: - Theme

enum GipetTheme {
    static let bg       = Color(red: 0.094, green: 0.106, blue: 0.122)   // popover background
    static let card     = Color(red: 0.13, green: 0.145, blue: 0.165)    // stat-card background
    static let green    = Color(red: 0.22, green: 0.83, blue: 0.33)      // accent numbers
    static let bubble   = Color(red: 0.16, green: 0.18, blue: 0.20)

    // GitHub dark contribution palette, index 0...4.
    static let levelColors: [Color] = [
        Color(red: 0.17, green: 0.19, blue: 0.22),   // 0 — empty
        Color(red: 0.05, green: 0.27, blue: 0.16),   // 1
        Color(red: 0.00, green: 0.43, blue: 0.20),   // 2
        Color(red: 0.15, green: 0.65, blue: 0.25),   // 3
        Color(red: 0.22, green: 0.83, blue: 0.33),   // 4
    ]
    static func color(level: Int) -> Color { levelColors[max(0, min(4, level))] }
}

// MARK: - Layout constants

private enum Grid {
    static let cell: CGFloat = 11
    static let gap: CGFloat = 3
    static let advance: CGFloat = cell + gap          // 14
    static let leading: CGFloat = 30                  // weekday-label column
    static let monthRow: CGFloat = 16                 // month-label row height
    static let monthGap: CGFloat = 4                  // gap below month labels
    static var squaresTop: CGFloat { monthRow + monthGap }
}

// MARK: - Root

struct ContributionView: View {
    @ObservedObject var model: GipetViewModel
    var onOpenGooseMenu: () -> Void = {}
    var onQuit: () -> Void = {}

    @State private var usernameField = ""
    @State private var tokenField = ""
    @State private var showToken = false

    var body: some View {
        Group {
            if model.isSignedIn {
                signedIn
            } else {
                signedOut.frame(width: 360)
            }
        }
        .background(GipetTheme.bg)
        .environment(\.colorScheme, .dark)
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileHeaderView(model: model)
            ContributionGrid(days: model.days)
            HStack(alignment: .top, spacing: 20) {
                StatsCard(title: "Contributions") {
                    StatItem(label: "Total in the last year",
                             value: model.stats.totalLastYear.formatted(),
                             sub: rangeText(model.stats.firstDate, model.stats.lastDate, endYear: true))
                    StatItem(label: "Best day",
                             value: "\(model.stats.bestDay)",
                             sub: fmt(model.stats.bestDayDate, "MMM d, yyyy"))
                    StatItem(label: "Average",
                             value: String(format: "%.2f", model.stats.average),
                             unit: "/ day")
                }
                StatsCard(title: "Streaks") {
                    StatItem(label: "Longest streak",
                             value: "\(model.stats.longestStreak)", unit: "days",
                             sub: rangeText(model.stats.longestStart, model.stats.longestEnd, endYear: true))
                    StatItem(label: "Current streak",
                             value: "\(model.stats.currentStreak)", unit: "days",
                             sub: rangeText(model.stats.currentStart, model.stats.currentEnd, endYear: true))
                }
            }
            ReposSection(model: model)
            footer
        }
        .padding(20)
        .frame(width: contentWidth)
    }

    /// Popover width: sized to the full year grid (the custom status-item
    /// window handles on-screen positioning).
    private var contentWidth: CGFloat {
        let weeks = weekColumns(model.days).count
        return 40 + 26 + 4 + CGFloat(max(weeks, 1)) * Grid.advance
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button(action: { model.refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if let updated = model.lastUpdated {
                (Text("Updated ") + Text(updated, style: .relative))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Menu("⚙") {
                Button("Dog menu…", action: onOpenGooseMenu)
                Button("Sign out") { model.signOut() }
                Divider()
                Button("Quit", action: onQuit)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 12))
    }

    // MARK: signed-out

    private var signedOut: some View {
        VStack(spacing: 12) {
            Text("Gipet").font(.system(size: 22, weight: .bold))
            Text("Track your GitHub streak. Your dog fetches an image\nwhenever you haven't committed today. 🐕")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                TextField("GitHub username", text: $usernameField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.track(username: usernameField) }
                Button("Track") { model.track(username: usernameField) }
                    .disabled(usernameField.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button(action: { model.signIn() }) {
                Label("Log In with GitHub", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large).buttonStyle(.borderedProminent)
            DisclosureGroup("Use a token (optional — for private contributions)", isExpanded: $showToken) {
                VStack(spacing: 6) {
                    SecureField("ghp_… personal access token", text: $tokenField)
                        .textFieldStyle(.roundedBorder)
                    Button("Use token") { model.useToken(tokenField) }
                        .disabled(tokenField.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(.top, 4)
            }.font(.system(size: 11))
            if let err = model.errorText {
                Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(3)
            }
            Button("Quit", action: onQuit).font(.system(size: 11))
        }
        .padding(20)
    }

    // MARK: helpers

}

// MARK: - Profile header

struct ProfileHeaderView: View {
    @ObservedObject var model: GipetViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openProfile) {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.user?.displayName ?? "—")
                            .font(.system(size: 20, weight: .bold))
                        if let login = model.user?.login {
                            Text(login).font(.system(size: 14)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Click to open your Github profile")
            Spacer()
            committedBadge
        }
    }

    private var avatar: some View {
        Group {
            if let img = model.avatar {
                Image(nsImage: img).resizable()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.secondary)
            }
        }
        .frame(width: 52, height: 52).clipShape(Circle())
    }

    private var committedBadge: some View {
        let done = model.stats.committedToday
        return Text(done ? "Committed today ✓" : "No commit yet 🐕")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((done ? GipetTheme.green : .orange).opacity(0.18))
            .foregroundColor(done ? GipetTheme.green : .orange)
            .clipShape(Capsule())
    }

    private func openProfile() {
        guard let login = model.user?.login,
              let url = URL(string: "https://github.com/\(login)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Grid + hover tooltip

private struct HoverCell: Equatable {
    let col: Int
    let row: Int
    let day: ContributionDay
}

struct ContributionGrid: View {
    let days: [ContributionDay]
    @State private var hovered: HoverCell?

    private let weekdayNames = ["", "Mon", "", "Wed", "", "Fri", ""]

    var body: some View {
        let weeks = weekColumns(days)
        let monthStarts = monthLabelColumns(weeks)
        let gridW = CGFloat(max(weeks.count, 1)) * Grid.advance
        let gridH = Grid.squaresTop + 7 * Grid.advance

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                // Fixed weekday-label column (stays put while the grid scrolls).
                ZStack(alignment: .topLeading) {
                    ForEach(0..<7, id: \.self) { row in
                        if !weekdayNames[row].isEmpty {
                            Text(weekdayNames[row])
                                .font(.system(size: 10)).foregroundColor(.secondary)
                                .offset(y: Grid.squaresTop + CGFloat(row) * Grid.advance - 2)
                        }
                    }
                }
                .frame(width: 26, height: gridH, alignment: .topLeading)

                // Scrollable squares (auto-scrolled to the most recent week).
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            ForEach(monthStarts, id: \.col) { ms in
                                Text(ms.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .offset(x: CGFloat(ms.col) * Grid.advance, y: 0)
                            }
                            ForEach(Array(weeks.enumerated()), id: \.offset) { col, week in
                                ForEach(0..<7, id: \.self) { row in
                                    if row < week.count, week[row].count >= 0 {
                                        let day = week[row]
                                        let isHot = hovered == HoverCell(col: col, row: row, day: day)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(GipetTheme.color(level: day.level))
                                            .frame(width: Grid.cell, height: Grid.cell)
                                            .scaleEffect(isHot ? 1.8 : 1.0)
                                            .shadow(color: .black.opacity(isHot ? 0.5 : 0), radius: 3)
                                            .offset(x: CGFloat(col) * Grid.advance,
                                                    y: Grid.squaresTop + CGFloat(row) * Grid.advance)
                                            .zIndex(isHot ? 2 : 0)
                                            .onHover { inside in
                                                if inside { hovered = HoverCell(col: col, row: row, day: day) }
                                                else if hovered?.col == col && hovered?.row == row { hovered = nil }
                                            }
                                    }
                                }
                            }
                            if let h = hovered {
                                tooltip(for: h.day)
                                    .position(x: tooltipX(h.col, width: gridW),
                                              y: Grid.squaresTop + CGFloat(h.row) * Grid.advance - 18)
                                    .zIndex(10)
                                    .allowsHitTesting(false)
                            }
                            Color.clear.frame(width: 1, height: 1)
                                .offset(x: gridW - 1).id("trailing")
                        }
                        .frame(width: gridW, height: gridH, alignment: .topLeading)
                        .animation(.easeOut(duration: 0.10), value: hovered)
                    }
                    .onAppear { proxy.scrollTo("trailing", anchor: .trailing) }
                }
            }
            legend.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func tooltip(for day: ContributionDay) -> some View {
        let n = day.count == 0 ? "No" : "\(day.count)"
        let plural = day.count == 1 ? "" : "s"
        return (Text(n).bold() + Text(" contribution\(plural) on \(fmt(day.date, "MMM d, yyyy"))"))
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(GipetTheme.bubble))
            .shadow(color: .black.opacity(0.4), radius: 4)
            .fixedSize()
    }

    private func tooltipX(_ col: Int, width: CGFloat) -> CGFloat {
        let raw = Grid.leading + CGFloat(col) * Grid.advance + Grid.cell / 2
        // Keep enough horizontal padding for longer text like
        // "7 contributions on May 30, 2026" so it doesn't clip at edges.
        let safeInset: CGFloat = 130
        return min(max(raw, safeInset), width - safeInset)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 10)).foregroundColor(.secondary)
            ForEach(0..<5, id: \.self) { lvl in
                RoundedRectangle(cornerRadius: 2)
                    .fill(GipetTheme.color(level: lvl))
                    .frame(width: Grid.cell, height: Grid.cell)
            }
            Text("More").font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}

// MARK: - Stats cards

struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 18, weight: .bold))
            HStack(alignment: .top, spacing: 28) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(GipetTheme.card))
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var unit: String? = nil
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(GipetTheme.green)
                if let unit { Text(unit).font(.system(size: 14)).foregroundColor(.secondary) }
            }
            if let sub { Text(sub).font(.system(size: 11)).foregroundColor(.secondary) }
        }
    }
}

// MARK: - Shared helpers (week layout, month labels, date formatting)

private func weekColumns(_ days: [ContributionDay]) -> [[ContributionDay]] {
    guard !days.isEmpty else { return [] }
    let cal = Calendar.current
    var weeks: [[ContributionDay]] = []
    var current: [ContributionDay] = []
    for day in days {
        let weekday = cal.component(.weekday, from: day.date) - 1   // 0=Sun
        if current.isEmpty && weekday > 0 {
            for _ in 0..<weekday {
                current.append(.init(date: day.date, count: -1, level: 0))   // leading padding
            }
        }
        current.append(day)
        if weekday == 6 { weeks.append(current); current = [] }
    }
    if !current.isEmpty { weeks.append(current) }
    return weeks
}

private struct MonthLabel { let col: Int; let label: String }

private func monthLabelColumns(_ weeks: [[ContributionDay]]) -> [MonthLabel] {
    let cal = Calendar.current
    let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = "MMM"
    var out: [MonthLabel] = []
    var lastMonth = -1
    for (col, week) in weeks.enumerated() {
        guard let firstReal = week.first(where: { $0.count >= 0 }) else { continue }
        let m = cal.component(.month, from: firstReal.date)
        if m != lastMonth {
            // Avoid crowding: only label if a few columns from the previous one.
            if out.last == nil || col - out.last!.col >= 2 {
                out.append(MonthLabel(col: col, label: df.string(from: firstReal.date)))
            }
            lastMonth = m
        }
    }
    return out
}

private func fmt(_ date: Date?, _ format: String) -> String {
    guard let date else { return "—" }
    let df = DateFormatter(); df.locale = Locale(identifier: "en_US"); df.dateFormat = format
    return df.string(from: date)
}

/// "MMM d → MMM d, yyyy"  (start without year, end with year).
private func rangeText(_ start: Date?, _ end: Date?, endYear: Bool) -> String {
    let s = fmt(start, "MMM d")
    let e = fmt(end, endYear ? "MMM d, yyyy" : "MMM d")
    return "\(s) → \(e)"
}

// MARK: - Watched repos (one-click commit)

struct ReposSection: View {
    @ObservedObject var model: GipetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repos").font(.system(size: 18, weight: .bold))
                if !model.aiAvailable {
                    Text("(no AI key — generic message)")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let path = pickFolder() { model.addRepo(path: path) }
                } label: { Label("Add folder", systemImage: "plus") }
                    .font(.system(size: 12))
            }

            if model.repos.isEmpty {
                Text("Add a local git repo to get a one-click commit & push (with an AI-written message).")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.repos) { repo in RepoRow(model: model, repo: repo) }
                }
            }
        }
    }

    private func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct RepoRow: View {
    @ObservedObject var model: GipetViewModel
    let repo: RepoState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isDirty ? "circle.fill" : "checkmark.circle.fill")
                .foregroundColor(repo.isDirty ? .orange : GipetTheme.green)
                .font(.system(size: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).font(.system(size: 13, weight: .medium))
                Text(statusText).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if repo.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("Journal") { model.journalCommit(repo: repo.path) }
                    .help("AI가 gipet-journal.md에 한 줄 추가 후 커밋 (코드 안 건드림)")
                Button("Commit") { model.commit(repo: repo.path) }
                    .disabled(!repo.isDirty)
                Button {
                    model.removeRepo(repo.path)
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(GipetTheme.card))
    }

    private var statusText: String {
        if let r = repo.lastResult { return r }
        return repo.isDirty ? "\(repo.dirtyCount) uncommitted change\(repo.dirtyCount == 1 ? "" : "s")" : "clean"
    }
}
