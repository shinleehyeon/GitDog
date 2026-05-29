// Gipet — popover UI. Mirrors Git Streaks' view tree:
//   ContributionView { ProfileHeaderView, SquaresView, StatsView }

import SwiftUI
import AppKit

// GitHub's contribution palette (light theme greens), index 0...4 by level.
enum GipetTheme {
    static let levelColors: [Color] = [
        Color(red: 0.92, green: 0.93, blue: 0.94),  // 0 — empty
        Color(red: 0.61, green: 0.85, blue: 0.55),  // 1
        Color(red: 0.25, green: 0.70, blue: 0.36),  // 2
        Color(red: 0.13, green: 0.55, blue: 0.27),  // 3
        Color(red: 0.09, green: 0.38, blue: 0.18),  // 4
    ]
    static func color(level: Int) -> Color {
        levelColors[max(0, min(4, level))]
    }
}

struct ContributionView: View {
    @ObservedObject var model: GipetViewModel
    var onOpenGooseMenu: () -> Void = {}
    var onQuit: () -> Void = {}

    @State private var usernameField = ""
    @State private var tokenField = ""
    @State private var showToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isSignedIn {
                ProfileHeaderView(model: model)
                Divider()
                SquaresView(days: model.days)
                StatsView(stats: model.stats)
                Divider()
                footer
            } else {
                signedOut
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Text("Gipet")
                .font(.system(size: 22, weight: .bold))
            Text("Track your GitHub streak. Your dog fetches an image\nwhenever you haven't committed today. 🐕")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // ① Username only — no token required (public contributions).
            HStack(spacing: 6) {
                TextField("GitHub username", text: $usernameField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.track(username: usernameField) }
                Button("Track") { model.track(username: usernameField) }
                    .disabled(usernameField.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // ③ OAuth (mirrors Git Streaks "Log In with GitHub").
            Button(action: { model.signIn() }) {
                Label("Log In with GitHub", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            // ② Optional Personal Access Token.
            DisclosureGroup("Use a token (optional — for private contributions)", isExpanded: $showToken) {
                VStack(spacing: 6) {
                    SecureField("ghp_… personal access token", text: $tokenField)
                        .textFieldStyle(.roundedBorder)
                    Button("Use token") { model.useToken(tokenField) }
                        .disabled(tokenField.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 11))

            if let err = model.errorText {
                Text(err).font(.system(size: 10)).foregroundColor(.red).lineLimit(3)
            }
            Button("Quit", action: onQuit).font(.system(size: 11))
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Button(action: { model.refresh() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
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
}

struct ProfileHeaderView: View {
    @ObservedObject var model: GipetViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openProfile) {
                HStack(spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.user?.displayName ?? "—")
                            .font(.system(size: 15, weight: .semibold))
                        if let login = model.user?.login {
                            Text("@\(login)").font(.system(size: 12)).foregroundColor(.secondary)
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

    private func openProfile() {
        guard let login = model.user?.login,
              let url = URL(string: "https://github.com/\(login)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var avatar: some View {
        Group {
            if let img = model.avatar {
                Image(nsImage: img).resizable()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var committedBadge: some View {
        let done = model.stats.committedToday
        return Text(done ? "Committed today ✓" : "No commit yet 🐕")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((done ? Color.green : Color.orange).opacity(0.18))
            .foregroundColor(done ? .green : .orange)
            .clipShape(Capsule())
    }
}

/// The contribution grid — 7 rows (weekdays) × N week columns.
struct SquaresView: View {
    let days: [ContributionDay]

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let columns = weekColumns()
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { idx, week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = row < week.count ? week[row] : nil
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(day.map { GipetTheme.color(level: $0.level) } ?? Color.clear)
                                    .frame(width: cell, height: cell)
                                    .help(day.map { tooltip($0) } ?? "")
                            }
                        }
                        .id(idx)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 7 * cell + 6 * gap + 4)
            .onAppear { proxy.scrollTo(columns.count - 1, anchor: .trailing) }
        }
    }

    /// Group days into week columns, padding the first week so weekday rows align.
    private func weekColumns() -> [[ContributionDay]] {
        guard !days.isEmpty else { return [] }
        let cal = Calendar.current
        var weeks: [[ContributionDay]] = []
        var current: [ContributionDay] = []
        // GitHub columns start on Sunday (weekday 1).
        var expectedRow = 0
        for day in days {
            let weekday = cal.component(.weekday, from: day.date) - 1  // 0=Sun
            if current.isEmpty && weekday > 0 {
                // pad leading empty rows of the first week
                expectedRow = weekday
                for _ in 0..<weekday { current.append(.init(date: day.date, count: -1, level: 0)) }
                _ = expectedRow
            }
            current.append(day)
            if weekday == 6 {        // Saturday closes the column
                weeks.append(current)
                current = []
            }
        }
        if !current.isEmpty { weeks.append(current) }
        return weeks
    }

    private func tooltip(_ day: ContributionDay) -> String {
        guard day.count >= 0 else { return "" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let n = day.count == 0 ? "No" : "\(day.count)"
        let plural = day.count == 1 ? "" : "s"
        return "\(n) contribution\(plural) on \(fmt.string(from: day.date))"
    }
}

struct StatsView: View {
    let stats: ContributionStats

    var body: some View {
        HStack(spacing: 0) {
            stat("\(stats.currentStreak)", "Current Streak")
            divider
            stat("\(stats.longestStreak)", "Longest Streak")
            divider
            stat("\(stats.totalLastYear)", "Total in the last year")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold))
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 30)
    }
}
