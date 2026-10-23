// Gipet — popover UI (warm cream two-column layout).
//   ContributionView { PetSidebar | (ProfileHeader, Grid, StatPills, Repos, footer) }
// Hovering a square grows it and shows an "N contributions on <date>" bubble.

import SwiftUI
import AppKit
import ServiceManagement

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

/// Reported so the status-item window can grow/shrink with content (carousel page, repos…).
private struct PopoverHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContributionView: View {
    @ObservedObject var model: GipetViewModel
    var onOpenDogMenu: () -> Void = {}
    var onQuit: () -> Void = {}
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var refreshHovered = false
    @State private var gearHovered = false
    @State private var ballHovered = false
    @State private var dogHovered = false
    var body: some View {
        Group {
            if model.isSignedIn {
                signedIn
            } else {
                signedOut.frame(width: 360)
            }
        }
        .background(GipetTheme.cardBg)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PopoverHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(PopoverHeightKey.self) { h in
            guard h > 1 else { return }
            onContentHeightChange(h)
        }
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
            ContributionCarousel(days: model.days, activity: model.activity,
                                  onPageChange: { onContentHeightChange(0) })
            ReposSection(model: model)
            DogSizeSlider()
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
                    .opacity(refreshHovered ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.12), value: refreshHovered)
            .onHover { refreshHovered = $0 }
            Button(action: { model.throwBall() }) {
                Text("🎾 Ball")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GipetTheme.green)
                    .opacity(ballHovered ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.12), value: ballHovered)
            .onHover { ballHovered = $0 }
            Button(action: { model.toggleDog() }) {
                Label(model.dogVisible ? "Hide" : "Show", systemImage: "pawprint.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GipetTheme.green)
                    .opacity(dogHovered ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.12), value: dogHovered)
            .onHover { dogHovered = $0 }
            .help(model.dogVisible ? "데스크탑 강아지 끄기" : "데스크탑 강아지 켜기")
            if model.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if let updated = model.lastUpdated {
                (Text("Updated ") + Text(updated, style: .relative))
                    .font(.system(size: 12))
                    .foregroundColor(GipetTheme.inkSoft)
            }
            Menu {
                LaunchAtLoginToggle()
                Divider()
                Button("Sign out") { model.signOut() }
                Divider()
                Button("Quit", action: onQuit)
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(gearHovered ? GipetTheme.ink : GipetTheme.inkSoft)
                    .scaleEffect(gearHovered ? 1.1 : 1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .animation(.easeOut(duration: 0.12), value: gearHovered)
            .onHover { gearHovered = $0 }
        }
    }

    // MARK: signed-out

    @State private var patInput: String = ""
    @State private var showPATField: Bool = false

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

            // PAT direct input (for reviewers / users who prefer token auth)
            if showPATField {
                HStack(spacing: 6) {
                    TextField("GitHub Personal Access Token", text: $patInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { submitPAT() }
                    Button("붙여넣기") {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            patInput = str
                        }
                    }
                    .font(.system(size: 11))
                    Button("확인") { submitPAT() }
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }

            Button(showPATField ? "취소" : "토큰으로 로그인") {
                showPATField.toggle()
                patInput = ""
            }
            .font(.system(size: 11)).foregroundColor(GipetTheme.inkSoft)
            .padding(.top, 10)

            Button("Quit", action: onQuit)
                .font(.system(size: 11)).foregroundColor(GipetTheme.inkSoft)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .frame(width: 360)
    }

    private func submitPAT() {
        let t = patInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.useToken(t)
        showPATField = false
        patInput = ""
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

// MARK: - Contribution carousel (잔디 ↔ 활동 그래프)

private enum ContributionPage: Int, CaseIterable, Identifiable {
    case grid = 0
    case activity = 1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .grid: return "Commits"
        case .activity: return "Activity"
        }
    }
}

struct ContributionCarousel: View {
    let days: [ContributionDay]
    let activity: ContributionActivity
    var onPageChange: () -> Void = {}
    @State private var page: ContributionPage = .grid
    @State private var dragOffset: CGFloat = 0

    private var pageHeight: CGFloat {
        switch page {
        case .grid:
            return Grid.squaresTop + 7 * Grid.advance + 22
        case .activity:
            return 248
        }
    }

    private func setPage(_ p: ContributionPage) {
        guard p != page else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            page = p
            dragOffset = 0
        }
        // Let SwiftUI settle, then ask the status window to remeasure.
        DispatchQueue.main.async { onPageChange() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Segmented: Commits | Activity
                HStack(spacing: 2) {
                    ForEach(ContributionPage.allCases) { p in
                        Button { setPage(p) } label: {
                            Text(p.title)
                                .font(.system(size: 12, weight: page == p ? .semibold : .medium))
                                .foregroundColor(page == p ? GipetTheme.ink : GipetTheme.inkSoft)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(page == p ? GipetTheme.panel : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(GipetTheme.panelBorder, lineWidth: 1))
                )

                Spacer(minLength: 0)

                Button {
                    setPage(page == .grid ? .activity : .grid)
                } label: {
                    HStack(spacing: 4) {
                        Text(page == .grid ? "Activity" : "Commits")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: page == .grid ? "chevron.right" : "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(GipetTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(GipetTheme.greenSoft.opacity(0.55))
                    )
                }
                .buttonStyle(.plain)
                .help(page == .grid ? "활동 그래프로 넘기기" : "잔디로 돌아가기")
            }

            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    ContributionGrid(days: days)
                        .frame(width: w, height: pageHeight, alignment: .top)
                    ActivityOverviewGraph(activity: activity)
                        .frame(width: w, height: pageHeight)
                }
                .frame(height: pageHeight, alignment: .top)
                .offset(x: -CGFloat(page.rawValue) * w + dragOffset)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 28)
                        .onChanged { value in
                            let raw = value.translation.width
                            guard abs(raw) > abs(value.translation.height) else { return }
                            if (page == .grid && raw > 0) || (page == .activity && raw < 0) {
                                dragOffset = raw * 0.25
                            } else {
                                dragOffset = raw
                            }
                        }
                        .onEnded { value in
                            let threshold = w * 0.18
                            if value.translation.width < -threshold, page == .grid {
                                setPage(.activity)
                            } else if value.translation.width > threshold, page == .activity {
                                setPage(.grid)
                            } else {
                                withAnimation(.easeInOut(duration: 0.22)) { dragOffset = 0 }
                            }
                        }
                )
            }
            .frame(height: pageHeight)
            .clipped()
            .animation(.easeInOut(duration: 0.22), value: pageHeight)
        }
    }
}

/// GitHub-style activity overview: summary + large 4-axis mix chart.
struct ActivityOverviewGraph: View {
    let activity: ContributionActivity

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Activity overview")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GipetTheme.ink)

                Text(summaryText)
                    .font(.system(size: 12))
                    .foregroundColor(GipetTheme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ActivityStatRow(label: "Commits", count: activity.commits,
                                    percent: activity.commitPercent)
                    ActivityStatRow(label: "Pull requests", count: activity.pullRequests,
                                    percent: activity.pullRequestPercent)
                    ActivityStatRow(label: "Code review", count: activity.codeReviews,
                                    percent: activity.codeReviewPercent)
                    ActivityStatRow(label: "Issues", count: activity.issues,
                                    percent: activity.issuePercent)
                }
            }
            .frame(width: 210, alignment: .leading)

            ActivityRadarChart(activity: activity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryText: String {
        guard !activity.isEmpty else {
            return "Sign in with a token to see your contribution mix for the last year."
        }
        if activity.commitPercent >= 70 {
            return "Mostly commits this year — \(activity.commits.formatted()) commits out of \(activity.total.formatted()) contributions."
        }
        return "\(activity.total.formatted()) contributions across commits, PRs, reviews, and issues."
    }
}

private struct ActivityStatRow: View {
    let label: String
    let count: Int
    let percent: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(percent > 0 ? GipetTheme.green : Color.white.opacity(0.15))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GipetTheme.inkSoft)
            Spacer(minLength: 4)
            Text(count.formatted())
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(GipetTheme.ink)
            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(percent > 0 ? GipetTheme.green : GipetTheme.inkSoft)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct ActivityRadarChart: View {
    let activity: ContributionActivity

    /// Axes matching the GitHub profile: review↑ issues→ PRs↓ commits←
    private var axes: [(label: String, percent: Int, angle: Double)] {
        [
            ("Code review", activity.codeReviewPercent, -.pi / 2),
            ("Issues", activity.issuePercent, 0),
            ("Pull requests", activity.pullRequestPercent, .pi / 2),
            ("Commits", activity.commitPercent, .pi),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            // Keep labels outside the plot; plot uses the remaining square.
            let labelPad: CGFloat = 36
            let plot = min(geo.size.width - labelPad * 2, geo.size.height - labelPad * 2)
            let radius = max(plot * 0.48, 40)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Soft panel behind the chart
                RoundedRectangle(cornerRadius: 14)
                    .fill(GipetTheme.panel.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(GipetTheme.panelBorder, lineWidth: 1)
                    )

                Canvas { context, _ in
                    // Concentric diamonds (25 / 50 / 75 / 100%)
                    for ring in [0.25, 0.5, 0.75, 1.0] {
                        var diamond = Path()
                        for (i, a) in axes.enumerated() {
                            let p = point(center: center, radius: radius * ring, angle: a.angle)
                            if i == 0 { diamond.move(to: p) } else { diamond.addLine(to: p) }
                        }
                        diamond.closeSubpath()
                        context.stroke(diamond, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
                    }

                    // Crosshair axes
                    var guides = Path()
                    for a in axes {
                        guides.move(to: center)
                        guides.addLine(to: point(center: center, radius: radius, angle: a.angle))
                    }
                    context.stroke(guides, with: .color(Color.white.opacity(0.18)), lineWidth: 1)

                    // Data polygon
                    var poly = Path()
                    for (i, a) in axes.enumerated() {
                        let r = radius * CGFloat(max(0, min(100, a.percent))) / 100
                        let p = point(center: center, radius: max(r, 3), angle: a.angle)
                        if i == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
                    }
                    poly.closeSubpath()
                    context.fill(poly, with: .color(GipetTheme.green.opacity(0.28)))
                    context.stroke(poly, with: .color(GipetTheme.green), lineWidth: 2)

                    // Vertex dots
                    for a in axes {
                        let r = radius * CGFloat(max(0, min(100, a.percent))) / 100
                        let p = point(center: center, radius: max(r, 3), angle: a.angle)
                        let dot = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                        context.fill(dot, with: .color(GipetTheme.green))
                    }
                }

                ForEach(Array(axes.enumerated()), id: \.offset) { _, a in
                    let tip = point(center: center, radius: radius + 26, angle: a.angle)
                    VStack(spacing: 2) {
                        Text(a.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GipetTheme.inkSoft)
                        if a.percent > 0 {
                            Text("\(a.percent)%")
                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                .foregroundColor(GipetTheme.green)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .position(tip)
                }
            }
        }
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle)))
    }
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

// MARK: - Launch at login

struct LaunchAtLoginToggle: View {
    @State private var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("맥 켜면 자동 실행", isOn: $isEnabled)
            .onChange(of: isEnabled) { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("[Gipet] launch-at-login toggle failed: %@", error.localizedDescription)
                    // Revert to whatever actually took effect.
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

// MARK: - Dog size

struct DogSizeSlider: View {
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("펫 크기")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GipetTheme.ink)
            Slider(value: $appearance.sizeScale, in: 0.5...2.0, step: 0.05)
                .tint(GipetTheme.green)
            Text("\(Int(appearance.sizeScale * 100))%")
                .font(.system(size: 12))
                .foregroundColor(GipetTheme.inkSoft)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Watched repos (one-click commit)

struct ReposSection: View {
    @ObservedObject var model: GipetViewModel
    @State private var addFolderHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Repos").font(.system(size: 20, weight: .bold)).foregroundColor(GipetTheme.ink)
                Spacer()
                Button {
                    if let url = pickFolder() { model.addRepo(url: url) }
                } label: {
                    Text("+ Add folder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(addFolderHovered ? GipetTheme.cardBg : GipetTheme.green)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(addFolderHovered ? GipetTheme.green : Color.clear))
                        .overlay(Capsule().strokeBorder(GipetTheme.green.opacity(0.7), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.12), value: addFolderHovered)
                .onHover { addFolderHovered = $0 }
            }

            if model.repos.isEmpty {
                Text("로컬 git 레포를 추가하면 AI 커밋 메시지와 함께 원클릭으로 커밋 & 푸시할 수 있어요.")
                    .font(.system(size: 11)).foregroundColor(GipetTheme.inkSoft)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.repos) { repo in RepoRow(model: model, repo: repo) }
                }
            }
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct RepoRow: View {
    @ObservedObject var model: GipetViewModel
    let repo: RepoState
    @State private var closeHovered = false

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
                Button("Issue") { model.createIssue(repo: repo.path) }
                    .buttonStyle(GhostPill())
                    .help("이슈 하나 열고 바로 닫기 — Activity 그래프 Issues에 반영")
                Button("PR") { model.createAndMergePR(repo: repo.path) }
                    .buttonStyle(GhostPill())
                    .help("변경 없으면 저널/책 한 줄 자동 추가 → 브랜치 → 리뷰 → merge")
                Button("Commit") { model.commit(repo: repo.path) }
                    .buttonStyle(SolidPill(enabled: true))
                    .help("변경 없으면 저널/책 한 줄 자동 추가 후 커밋 & push")
                Button {
                    model.removeRepo(repo.path)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(closeHovered ? GipetTheme.orange : GipetTheme.inkSoft)
                        .scaleEffect(closeHovered ? 1.15 : 1)
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.12), value: closeHovered)
                .onHover { closeHovered = $0 }
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
        GhostPillBody(configuration: configuration)
    }
}

private struct GhostPillBody: View {
    let configuration: GhostPill.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(isHovered ? GipetTheme.ink : GipetTheme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(isHovered ? GipetTheme.panel : GipetTheme.cardBg))
            .overlay(Capsule().strokeBorder(isHovered ? GipetTheme.green.opacity(0.6) : GipetTheme.panelBorder, lineWidth: 1))
            .scaleEffect(isHovered ? 1.04 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct SolidPill: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        SolidPillBody(configuration: configuration, enabled: enabled)
    }
}

private struct SolidPillBody: View {
    let configuration: SolidPill.Configuration
    let enabled: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(enabled ? .white : GipetTheme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(enabled ? (isHovered ? GipetTheme.green.opacity(0.82) : GipetTheme.green) : GipetTheme.panel))
            .scaleEffect(enabled && isHovered ? 1.04 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
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

