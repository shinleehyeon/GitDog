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
    /// Called when the user picks "Dog menu…" inside the popover.
    var onOpenGooseMenu: (() -> Void)?
    /// Called when contribution stats change, so the menu-bar icon can update.
    var onStateChange: (() -> Void)?

    private var refreshTimer: Timer?
    private var nudgeTimer: Timer?

    // While the machine is asleep / display off / screen locked we don't nag.
    private var isAsleep = false

    // Refresh contributions every 10 min; nudge the dog every 20 s while
    // today's square is still empty.
    private let refreshInterval: TimeInterval = 600
    private let nudgeInterval: TimeInterval = 20

    func configurePopover() {
        let root = ContributionView(
            model: model,
            onOpenGooseMenu: { [weak self] in
                self?.hide()
                self?.onOpenGooseMenu?()
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
                DispatchQueue.main.async { self?.onStateChange?() }
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
        let shouldFetch = invert ? model.stats.committedToday : !model.stats.committedToday
        if shouldFetch {
            NSLog("[Gipet] trigger (invert=\(invert), committedToday=\(model.stats.committedToday)) → dog fetches an image")
            onNoCommitNudge?()
        }
    }
}
