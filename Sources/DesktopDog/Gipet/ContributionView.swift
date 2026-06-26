// Gipet — popover UI (warm cream two-column layout).
//   ContributionView { PetSidebar | (ProfileHeader, Grid, StatPills, Repos, footer) }
// Hovering a square grows it and shows an "N contributions on <date>" bubble.

import SwiftUI
import AppKit

// MARK: - Theme (warm cream / light)

enum GipetTheme {
    static let pageBg      = Color(red: 0.063, green: 0.072, blue: 0.086)  // darkest, behind the card
    static let cardBg      = Color(red: 0.094, green: 0.106, blue: 0.122)  // popover background
    static let panel       = Color(red: 0.145, green: 0.160, blue: 0.182)  // inner panels / cells bg
    static let panelBorder = Color.white.opacity(0.08)                     // hairline on panels
    static let green       = Color(red: 0.220, green: 0.830, blue: 0.330)  // accent
    static let greenSoft   = Color(red: 0.125, green: 0.300, blue: 0.180)  // mint badge bg (dark)
    static let orange      = Color(red: 0.950, green: 0.600, blue: 0.250)  // "no commit" / dirty
    static let ink         = Color(red: 0.918, green: 0.933, blue: 0.945)  // primary text
    static let inkSoft     = Color(red: 0.600, green: 0.624, blue: 0.667)  // secondary text
    static let bubble      = Color(red: 0.160, green: 0.180, blue: 0.200)

    // GitHub dark contribution palette, index 0...4.
    static let levelColors: [Color] = [
        Color(red: 0.17, green: 0.19, blue: 0.22),   // 0 — empty
        Color(red: 0.05, green: 0.27, blue: 0.16),   // 1
        Color(red: 0.00, green: 0.43, blue: 0.20),   // 2
        Color(red: 0.15, green: 0.65, blue: 0.25),   // 3
        Color(red: 0.22, green: 0.83, blue: 0.33),   // 4
    ]
    static func color(level: Int) -> Color { levelColors[max(0, min(4, level))] }

    static func panelBg(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(panel)
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(panelBorder, lineWidth: 1))
    }
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

private enum Layout {
    static let pad: CGFloat = 22
    static let main: CGFloat = 600
}

// MARK: - Root

struct ContributionView: View {
    @ObservedObject var model: GipetViewModel
    var onOpenGooseMenu: () -> Void = {}
    var onQuit: () -> Void = {}
    var body: some View {
        Group {
            if model.isSignedIn {
                signedIn
            } else {
                signedOut.frame(width: 360)
            }
        }
        .background(GipetTheme.cardBg)
        .fontDesign(.rounded)
        .environment(\.colorScheme, .dark)
    }

    /// The calendar year the contribution data covers (the fetch window is the
    /// current year), shown in the "Total <year>" stat label.
    private var contributionYear: Int {
        Calendar.current.component(.year, from: model.stats.firstDate ?? Date())
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileHeaderView(model: model)
            ContributionGrid(days: model.days)
            ReposSection(model: model)
            footer
        }
        .frame(width: Layout.main, alignment: .leading)
        .padding(Layout.pad)
    }

    private var statPills: some View {
        HStack(alignment: .top, spacing: 12) {
            StatPill(label: "Total \(contributionYear)",
                     value: model.stats.totalLastYear.formatted(),
                     sub: rangeText(model.stats.firstDate, model.stats.lastDate, endYear: true))
            StatPill(label: "Best day",
                     value: "\(model.stats.bestDay)",
                     sub: fmt(model.stats.bestDayDate, "MMM d, yyyy"))
            StatPill(label: "Average",
                     value: String(format: "%.2f", model.stats.average),
                     unit: "/ day")
            StatPill(label: "Longest",
                     value: "\(model.stats.longestStreak)", unit: "days",
                     sub: rangeText(model.stats.longestStart, model.stats.longestEnd, endYear: false))
            StatPill(label: "Current",
                     value: "\(model.stats.currentStreak)", unit: "days",
                     sub: rangeText(model.stats.currentStart, model.stats.currentEnd, endYear: false))
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Button(action: { model.refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GipetTheme.green)
            }
            .buttonStyle(.plain)
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if let updated = model.lastUpdated {
                (Text("Updated ") + Text(updated, style: .relative))
                    .font(.system(size: 12))
                    .foregroundColor(GipetTheme.inkSoft)
            }
            Menu {
Button("Sign out") { model.signOut() }
                Divider()
                Button("Quit", action: onQuit)
            } label: {
                Image(systemName: "gearshape.fill").foregroundColor(GipetTheme.inkSoft)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: signed-out

    private var signedOut: some View {
        VStack(spacing: 0) {
            Text("깃독")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(GipetTheme.ink)
                .padding(.top, 28)
                .padding(.bottom, 18)

            LoginBubble(text: "Github 계정으로 로그인")

            // Dog canvas is 750×1334 — at scaleAspectFit 200×200 the top ~55pt
            // is empty. Crop it by anchoring content to bottom and clipping.ㄹ
            LottieLoginButton(action: { model.signIn() })
                .frame(width: 200, height: 200, alignment: .bottom)
                .frame(height: 150)
                .clipped()
                .help("GitHub 계정으로 로그인 (OAuth)")

            if let err = model.errorText {
                Text(err)
                    .font(.system(size: 10)).foregroundColor(.red).lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Button("Quit", action: onQuit)
                .font(.system(size: 11)).foregroundColor(GipetTheme.inkSoft)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .frame(width: 360)
    }
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
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(GipetTheme.ink)
                        if let login = model.user?.login {
                            Text("@\(login)").font(.system(size: 14)).foregroundColor(GipetTheme.inkSoft)
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

    private var committedBadge: some View {
        let done = model.stats.committedToday
        let accent = done ? GipetTheme.green : GipetTheme.orange
        return Text(done ? "Committed today ✓" : "No commit yet 🐕")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
            .foregroundColor(accent)
    }

    private var initials: String {
        let name = model.user?.displayName ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private var avatar: some View {
        Group {
            if let img = model.avatar {
                Image(nsImage: img).resizable()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.55),
                                            Color(red: 0.96, green: 0.55, blue: 0.36)],
                                   startPoint: .top, endPoint: .bottom)
                    Text(initials).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                }
            }
        }
        .frame(width: 56, height: 56).clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
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
            .shadow(color: .black.opacity(0.45), radius: 4)
            .fixedSize()
    }

    private func tooltipX(_ col: Int, width: CGFloat) -> CGFloat {
        let raw = Grid.leading + CGFloat(col) * Grid.advance + Grid.cell / 2
        let safeInset: CGFloat = 130
        return min(max(raw, safeInset), width - safeInset)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 10, weight: .semibold)).foregroundColor(GipetTheme.inkSoft)
            ForEach(0..<5, id: \.self) { lvl in
                RoundedRectangle(cornerRadius: 3)
                    .fill(GipetTheme.color(level: lvl))
                    .frame(width: Grid.cell, height: Grid.cell)
            }
            Text("More").font(.system(size: 10, weight: .semibold)).foregroundColor(GipetTheme.inkSoft)
        }
    }
}

// MARK: - Stat pills

struct StatPill: View {
    let label: String
    let value: String
    var unit: String? = nil
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(GipetTheme.inkSoft)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .heavy)).foregroundColor(GipetTheme.green)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.system(size: 12)).foregroundColor(GipetTheme.inkSoft)
                        .lineLimit(1).fixedSize()
                }
            }
            if let sub {
                Text(sub).font(.system(size: 10.5)).foregroundColor(GipetTheme.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GipetTheme.panelBg(16))
    }
}

// MARK: - Watched repos (one-click commit)

struct ReposSection: View {
    @ObservedObject var model: GipetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Repos").font(.system(size: 20, weight: .bold)).foregroundColor(GipetTheme.ink)
                Spacer()
                Button {
                    if let path = pickFolder() { model.addRepo(path: path) }
                } label: {
                    Text("+ Add folder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(GipetTheme.green)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(GipetTheme.green.opacity(0.7), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            if model.repos.isEmpty {
                Text("Add a local git repo to get a one-click commit & push (with an AI-written message).")
                    .font(.system(size: 11)).foregroundColor(GipetTheme.inkSoft)
            } else {
                VStack(spacing: 8) {
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
        HStack(spacing: 12) {
            Circle()
                .fill(repo.isDirty ? GipetTheme.orange : GipetTheme.green)
                .frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(.system(size: 15, weight: .bold)).foregroundColor(GipetTheme.ink)
                Text(statusText).font(.system(size: 12)).foregroundColor(GipetTheme.inkSoft).lineLimit(1)
            }
            Spacer()
            if repo.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("Journal") { model.journalCommit(repo: repo.path) }
                    .buttonStyle(GhostPill())
                    .help("AI가 gipet-journal.md에 한 줄 추가 후 커밋 (코드 안 건드림)")
                Button("Commit") { model.commit(repo: repo.path) }
                    .buttonStyle(SolidPill(enabled: repo.isDirty))
                    .disabled(!repo.isDirty)
                Button {
                    model.removeRepo(repo.path)
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundColor(GipetTheme.inkSoft)
            }
        }
        .padding(14)
        .background(GipetTheme.panelBg(14))
    }

    private var statusText: String {
        if let r = repo.lastResult { return r }
        return repo.isDirty ? "\(repo.dirtyCount) uncommitted change\(repo.dirtyCount == 1 ? "" : "s")" : "clean"
    }
}

// MARK: - Button styles

struct GhostPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(GipetTheme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(GipetTheme.cardBg))
            .overlay(Capsule().strokeBorder(GipetTheme.panelBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SolidPill: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(enabled ? .white : GipetTheme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(enabled ? GipetTheme.green : GipetTheme.panel))
            .opacity(configuration.isPressed ? 0.7 : 1)
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

/// "MMM d → MMM d, yyyy"  (start without year, end with optional year).
private func rangeText(_ start: Date?, _ end: Date?, endYear: Bool) -> String {
    let s = fmt(start, "MMM d")
    let e = fmt(end, endYear ? "MMM d, yyyy" : "MMM d")
    return "\(s) → \(e)"
}

// MARK: - Behavior settings

