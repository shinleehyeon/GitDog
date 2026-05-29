// Gipet — status-bar popover + commit watcher.
// Mirrors Git Streaks' `MainStatusItemMenuManager`: a popover shown from the
// menu-bar item. Adds the dog hook — when today's contributions are 0, it
// nudges the dog to go fetch an image.

import AppKit
import SwiftUI

final class MainStatusItemMenuManager: NSObject {
    private let model = GipetViewModel.shared
    private let popover = NSPopover()

    /// Called when the dog should fetch an image (no commit today).
    var onNoCommitNudge: (() -> Void)?
    /// Called when the user picks "Dog menu…" inside the popover.
    var onOpenGooseMenu: (() -> Void)?

    private var refreshTimer: Timer?
    private var nudgeTimer: Timer?

    // Refresh contributions every 10 min; nudge the dog every 30 min while
    // today's square is still empty.
    private let refreshInterval: TimeInterval = 600
    private let nudgeInterval: TimeInterval = 1800

    func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let root = ContributionView(
            model: model,
            onOpenGooseMenu: { [weak self] in
                self?.popover.performClose(nil)
                self?.onOpenGooseMenu?()
            },
            onQuit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: root)
    }

    /// Toggle the popover anchored to the status-bar button.
    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            model.refresh()
        }
    }

    /// Kick off background refresh + the no-commit watcher.
    func start() {
        model.refresh()

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
    }

    /// If the user is signed in and hasn't committed today, send the dog.
    /// Only acts once real contribution data has loaded, so we never nag on
    /// the default (empty) stats while the first fetch is still in flight.
    private func checkAndNudge() {
        guard model.isSignedIn, !model.isLoading, !model.days.isEmpty else { return }
        if !model.stats.committedToday {
            NSLog("[Gipet] no commit today → dog fetches an image")
            onNoCommitNudge?()
        }
    }
}
