// Gipet — status-bar popover + commit watcher.
// Mirrors Git Streaks' `MainStatusItemMenuManager`: a popover shown from the
// menu-bar item. Adds the dog hook — when today's contributions are 0, it
// nudges the dog to go fetch an image.

import AppKit
import SwiftUI
import Combine

final class MainStatusItemMenuManager: NSObject {
    private let model = GipetViewModel.shared

    // Custom status-item window (replaces NSPopover — see StatusItemWindow).
    private var window: StatusItemWindow?
    private var hosting: NSHostingView<ContributionView>?
    private weak var anchorButton: NSStatusBarButton?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Called when the dog should fetch an image (no commit today).
    var onNoCommitNudge: (() -> Void)?
    /// Called when the dog should remind you to commit via a speech bubble
    /// (no commit today) — fires more often than the fetch nudge.
    var onNoCommitSay: (() -> Void)?
    /// Called on a recurring timer so the dog tells a random dad joke for fun.
    var onTellJoke: (() -> Void)?
    /// Called once when we first detect today's commit — the dog celebrates
    /// with a dad-joke speech bubble.
    var onDidCommit: (() -> Void)?
    // Persists whether we've already celebrated today's commit across app restarts.
    // Stores today's date string so it auto-resets the next calendar day.
    private static let celebrateDateKey = "Gipet.celebratedCommitDate"
    private static let celebrateDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private var didCelebrateCommit: Bool {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.celebrateDateKey) ?? ""
            return stored == Self.celebrateDateFmt.string(from: Date())
        }
        set {
            if newValue {
                UserDefaults.standard.set(Self.celebrateDateFmt.string(from: Date()), forKey: Self.celebrateDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.celebrateDateKey)
            }
        }
    }
    /// Called when the user picks "Dog menu…" inside the popover.
    var onOpenDogMenu: (() -> Void)?
    /// Called when contribution stats change, so the menu-bar icon can update.
    var onStateChange: (() -> Void)?
    private var refreshTimer: Timer?
    private var nudgeTimer: Timer?
    private var sayTimer: Timer?
    private var jokeTimer: Timer?
    private var lastNudgeDate: Date = .distantPast
    private let nudgeCooldown: TimeInterval = 60

    // While the machine is asleep / display off / screen locked we don't nag.
    private var isAsleep = false

    // How often we re-fetch contributions. Configurable like Git Streaks'
    // `git-streaks-seconds-<login>` default — read from UserDefaults
    // `Gipet.refreshSeconds`, clamped to a sane range. Default 5 min keeps the
    // token-less HTML scrape well under GitHub's radar.
    //   defaults write <bundle-id> Gipet.refreshSeconds -int 600
    static let refreshSecondsKey = "Gipet.refreshSeconds"
    private var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.refreshSecondsKey)
        let seconds = stored > 0 ? stored : 300   // 0 == unset -> default 5 min
        return min(max(seconds, 30), 3600)        // clamp 30 s … 1 hour
        // 30 s floor is safe: the contributions page is github.com web (not the
        // REST API, so the 60/hr limit doesn't apply) and ETag conditional
        // requests mean unchanged polls cost a cheap 304. Below ~30 s risks
        // GitHub's secondary/abuse rate limit (429 + temporary IP block).
    }
    // nudge the dog every 15 min while today's square is still empty.
    private let nudgeInterval: TimeInterval = 900
    // The "커밋해!" reminder bubble — every 5 min.
    private let sayInterval: TimeInterval = 300
    // How often the dog tells a random dad joke for fun.
    private let jokeInterval: TimeInterval = 180

    func configurePopover() {
        let root = ContributionView(
            model: model,
            onOpenDogMenu: { [weak self] in
                self?.hide()
                self?.onOpenDogMenu?()
            },
            onQuit: { NSApp.terminate(nil) })
        let host = NSHostingView(rootView: root)
        let win = StatusItemWindow(contentView: host)
        win.appearance = NSAppearance(named: .darkAqua)
        self.hosting = host
        self.window = win

        // When the content's size changes (e.g. signed-out → grid loads),
        // resize the window and re-anchor so its top edge stays put.
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.resizeIfVisible()
                // Read after SwiftUI applies the change, so stats are current.
                DispatchQueue.main.async {
                    self?.onStateChange?()
                    self?.checkAndNudge()
                }
            }
            .store(in: &cancellables)
    }

    /// Toggle the status-item window anchored to the status-bar button.
    func toggle(from button: NSStatusBarButton) {
        if window?.isVisible == true {
            hide()
        } else {
            show(from: button)
        }
    }

    private func show(from button: NSStatusBarButton) {
        guard let window, let host = hosting else { return }
        anchorButton = button
        model.refresh()
        model.scanRepos()
        sizeWindowToContent(host: host, window: window)
        window.anchor(below: button)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installClickMonitor()
    }

    private func hide() {
        window?.orderOut(nil)
        removeClickMonitor()
    }

    private func sizeWindowToContent(host: NSHostingView<ContributionView>, window: StatusItemWindow) {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        if size.width > 1, size.height > 1 {
            window.setContentSize(size)
        }
    }

    private func resizeIfVisible() {
        guard let window, let host = hosting, window.isVisible else { return }
        // Defer one runloop tick so SwiftUI has applied the new content.
        DispatchQueue.main.async {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width > 1, size.height > 1 else { return }
            // Only touch the window if the size actually changed — and keep the
            // TOP-LEFT corner pinned so a refresh never makes it jump up/down.
            if abs(size.width - window.frame.width) < 0.5,
               abs(size.height - window.frame.height) < 0.5 { return }
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(size)
            window.setFrameTopLeftPoint(topLeft)
        }
    }

    // Close when the user clicks outside the window (transient behaviour).
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    /// Kick off background refresh + the no-commit watcher.
    // MARK: - Dev tools
    func devResetDailyState() {
        UserDefaults.standard.removeObject(forKey: Self.celebrateDateKey)
        lastNudgeDate = .distantPast
        NSLog("[DEV] Daily state reset")
    }

    func devForceRefresh() {
        model.refresh()
        NSLog("[DEV] Contribution refresh triggered")
    }

    func start() {
        model.refresh()
        model.scanRepos()

        // Timers fire on the main run loop; model/UI work is main-thread safe.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: nudgeInterval, repeats: true) { [weak self] _ in
            self?.checkAndNudge()
        }
        sayTimer = Timer.scheduledTimer(withTimeInterval: sayInterval, repeats: true) { [weak self] _ in
            self?.checkAndSay()
        }
        jokeTimer = Timer.scheduledTimer(withTimeInterval: jokeInterval, repeats: true) { [weak self] _ in
            guard let self, !self.isAsleep else { return }
            self.onTellJoke?()
        }
        // First nudge a little after launch so contributions have loaded.
        Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.checkAndNudge()
        }

        observeSleepWake()
    }

    /// Pause nudging while the system sleeps, the display sleeps, or the screen
    /// is locked — and resume on wake/unlock.
    private func observeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(goAsleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wakeUp), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(goAsleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(wakeUp), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(goAsleep), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(wakeUp), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func goAsleep() { isAsleep = true; NSLog("[Gipet] asleep/locked → pause nudges") }
    @objc private func wakeUp()   { isAsleep = false; NSLog("[Gipet] awake/unlocked → resume nudges") }

    /// If the user is signed in and hasn't committed today, send the dog.
    /// Only acts once real contribution data has loaded, so we never nag on
    /// the default (empty) stats while the first fetch is still in flight.
    ///
    /// Debug: set `Gipet.testNudgeOnCommit` to invert the trigger (fetch when
    /// you HAVE committed) so the behaviour is testable on a day you've already
    /// committed. Enable:  defaults write com.gipet.app Gipet.testNudgeOnCommit -bool YES
    private func checkAndNudge() {
        guard !isAsleep else { return }
        guard model.isSignedIn, !model.isLoading, !model.days.isEmpty else { return }
        let invert = UserDefaults.standard.bool(forKey: "Gipet.testNudgeOnCommit")
        let committed = model.stats.committedToday
        // First time today's commit shows up → dog tells a dad joke (once/day).
        if committed {
            if !didCelebrateCommit {
                didCelebrateCommit = true
                NSLog("[Gipet] committed today → dog tells a joke")
                onDidCommit?()
            }
        } else {
            didCelebrateCommit = false
        }
        let shouldFetch = invert ? committed : !committed
        if shouldFetch {
            let now = Date()
            guard now.timeIntervalSince(lastNudgeDate) >= nudgeCooldown else { return }
            lastNudgeDate = now
            NSLog("[Gipet] trigger (invert=\(invert), committedToday=\(committed)) → dog fetches an image")
            onNoCommitNudge?()
        }
    }

    /// Reminder bubble on its own (faster) cadence: if signed in and not
    /// committed today, the dog says "커밋해!" — without fetching anything.
    private func checkAndSay() {
        guard !isAsleep else { return }
        guard model.isSignedIn, !model.isLoading, !model.days.isEmpty else { return }
        let invert = UserDefaults.standard.bool(forKey: "Gipet.testNudgeOnCommit")
        let shouldSay = invert ? model.stats.committedToday : !model.stats.committedToday
        if shouldSay {
            onNoCommitSay?()
        }
    }
}
