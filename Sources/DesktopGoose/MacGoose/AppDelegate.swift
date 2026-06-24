// Port of: MacGoose/AppDelegate.cs

import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox          // cmdKey, controlKey for global hotkey modifiers

@objc(AppDelegate)
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var PreferencesWindow: NSWindow?

    static var SharedAppDelegate: AppDelegate {
        NSApplication.shared.delegate as! AppDelegate
    }

    private(set) var Goose: MacintoshGoose?
    // Last dad joke shown, so the celebration doesn't repeat back-to-back.
    private var lastJoke: String?

    // Memes and Notes live in Application Support so users can add their own.
    // On first launch, built-in defaults are seeded from the app bundle.
    private static func gipetSupportDir(_ sub: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Gipet/\(sub)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var MemesDirectory: URL { AppDelegate.gipetSupportDir("Memes") }
    var NotesDirectory: URL { AppDelegate.gipetSupportDir("Notes") }
    static var HomeDirectory: String { NSHomeDirectory() }

    // Character toggle (goose/dachshund).
    private var statusItem: NSStatusItem?

    // Gipet — GitHub streak popover + commit watcher.
    private let gipet = MainStatusItemMenuManager()
    private var gooseMenu: NSMenu?
    private var rightClickMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register the gipet:// scheme so the GitHub OAuth callback reaches us.
        AppDeeplinkHandler.shared.register()
    }

    // Modern URL delivery path (preferred over the raw Apple Event).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == GipetGitHub.callbackScheme {
            GitHubTokenRequester.shared.handleCallback(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        GooseConfig.settings = MacGooseSettings()
        seedBundleResources()
        Goose = MacintoshGoose(memesDirectory: MemesDirectory.path,
                               notesDirectory: NotesDirectory.path)
        NSApplication.shared.activate(ignoringOtherApps: true)
        installStatusItem()
        installGipet()
        applyCharacterChoice()
        installGlobalHotkey()
        installRightClickMove()
    }

    private func installGipet() {
        gipet.configurePopover()
        // No commit today → send the dog to fetch something: randomly an
        // image (Memes/) or a note (Notes/).
        gipet.onNoCommitNudge = { [weak self] in
            let task: Goose.GooseTask = Bool.random() ? .CollectWindow_Meme : .CollectWindow_Notepad
            self?.Goose?.SetTask(task, honck: false)
        }
        // Commit reminder bubble — fires once a minute while you haven't committed.
        gipet.onNoCommitSay = { [weak self] in
            self?.Goose?.Say("커밋해! 🐾", duration: 5)
        }
        // Periodic dad joke for fun.
        gipet.onTellJoke = { [weak self] in
            let joke = DadJokes.random(avoiding: self?.lastJoke)
            self?.lastJoke = joke
            self?.Goose?.Say(joke, duration: 6)
        }
        // Committed today → the dog tells a random dad joke (no immediate repeat).
        gipet.onDidCommit = { [weak self] in
            let joke = DadJokes.random(avoiding: self?.lastJoke)
            self?.lastJoke = joke
            self?.Goose?.Say(joke, duration: 6)
        }
        // "Dog menu…" inside the popover pops the classic goose menu at the cursor.
        gipet.onOpenGooseMenu = { [weak self] in
            self?.popupGooseMenuAtCursor()
        }
        // Stats changed → refresh the menu-bar icon (mood + streak).
        gipet.onStateChange = { [weak self] in
            self?.refreshTitle()
        }
        gipet.start()
    }

    private func installRightClickMove() {
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            guard let goose = self?.Goose else { return }
            let screenPos = NSEvent.mouseLocation
            let screenH = NSScreen.main?.frame.height ?? 0
            let gamePos = Vector2(Float(screenPos.x), Float(screenH - screenPos.y))
            goose.lockedTarget = gamePos
            goose.onLockedTargetArrival = { }
            goose.SetTask(.Wander, honck: false)
            goose.clickIndicatorScreenPos = screenPos
            goose.clickIndicatorStartTime = Time.time
        }
    }

    private func installGlobalHotkey() {
        let cmdCtrl = UInt32(cmdKey | controlKey)
        // kVK_ANSI_G = 5  → Cmd+Ctrl+G   → pop the menu near the cursor
        // kVK_ANSI_M = 46 → Cmd+Ctrl+M   → force the goose to fetch a meme right now
        // kVK_ANSI_B = 11 → Cmd+Ctrl+B   → force the goose to fetch a note right now
        HotkeyManager.shared.register(keyCode: 5,  modifiers: cmdCtrl) { [weak self] in
            self?.popupGooseMenuAtCursor()
        }
        HotkeyManager.shared.register(keyCode: 46, modifiers: cmdCtrl) { [weak self] in
            self?.Goose?.SetTask(.CollectWindow_Meme, honck: false)
        }
        HotkeyManager.shared.register(keyCode: 11, modifiers: cmdCtrl) { [weak self] in
            self?.Goose?.SetTask(.CollectWindow_Notepad, honck: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ShowPreferences()
        return true
    }

    @objc func openMemesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(MemesDirectory)
    }

    @objc func openNotesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(NotesDirectory)
    }

    // Copy bundled Memes/ and Notes/ into Application Support on first launch.
    // Existing user files are never overwritten.
    private func seedBundleResources() {
        seed(bundleSubdir: "Memes", into: MemesDirectory)
        seed(bundleSubdir: "Notes", into: NotesDirectory)
    }

    private func seed(bundleSubdir: String, into dest: URL) {
        guard let bundleDir = Bundle.main.url(forResource: bundleSubdir, withExtension: nil) else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil) else { return }
        for src in items {
            let target = dest.appendingPathComponent(src.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: src, to: target)
        }
    }

    func ShowPreferences() {
        // Original loads PreferencesWindow.nib — that's a UI asset we don't have a Swift equivalent for.
        // Fall back: open the user's defaults plist location, no-op otherwise.
        PreferencesWindow?.makeKeyAndOrderFront(self)
    }

    func windowWillClose(_ notification: Notification) {
        if let gw = notification.object as? GooseWindow {
            gw.CloseAction?()
        }
    }

    func windowWillMiniaturize(_ notification: Notification) {
        if let gw = notification.object as? GooseWindow {
            gw.CloseAction?()
        }
    }

    func window(_ window: NSWindow, shouldPopUpDocumentPathMenu menu: NSMenu) -> Bool {
        return true
    }

    func window(_ window: NSWindow, shouldDragDocumentWith event: NSEvent,
                from dragImageLocation: NSPoint, with pasteboard: NSPasteboard) -> Bool {
        return false
    }

    // MARK: - Character toggle menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        for kind in CharacterKind.allCases {
            let mi = NSMenuItem(title: kind.displayName,
                                action: #selector(pickCharacter(_:)),
                                keyEquivalent: "")
            mi.target = self
            mi.representedObject = kind.rawValue
            mi.state = (CharacterSettings.shared.current == kind) ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "말풍선 💬",   action: #selector(menuSpeak),      keyEquivalent: "").target = self
        menu.addItem(withTitle: "Honk",       action: #selector(menuHonk),       keyEquivalent: "h").target = self
        menu.addItem(withTitle: "Nab Mouse",  action: #selector(menuNabMouse),   keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Wander",     action: #selector(menuWander),     keyEquivalent: "w").target = self
        menu.addItem(withTitle: "Heart Trail", action: #selector(menuHeartTrail), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Track Mud",  action: #selector(menuTrackMud),   keyEquivalent: "m").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Memes", action: #selector(openMemesFolder(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Notes", action: #selector(openNotesFolder(_:)), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",       action: #selector(menuQuit), keyEquivalent: "q").target = self
        // Left-click opens the Gipet popover; right-click shows the goose menu.
        self.gooseMenu = menu
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
        refreshTitle()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRight {
            showGooseMenu(from: sender)
        } else {
            gipet.toggle(from: sender)
        }
    }

    private func showGooseMenu(from button: NSStatusBarButton) {
        guard let menu = gooseMenu, let item = statusItem else { return }
        item.menu = menu                    // attach so the button draws it...
        button.performClick(nil)            // ...then pop it,
        item.menu = nil                     // and detach so left-click stays ours.
    }

    private func popupGooseMenuAtCursor() {
        guard let menu = gooseMenu else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // Pill-shaped status item: [dot] [7 day bars] [today count].
    //   dot   — green if committed today, red if not, neutral gray when logged out
    //   bars  — last 7 days, colored by each day's contribution level (0 = faint)
    //   count — today's commit count; nil (logged out) draws an empty pill, no number
    private func statusBarImage(levels: [Int], count: Int?,
                                committed: Bool, isDark: Bool) -> NSImage {
        // Layout metrics. `s` scales the whole pill — bump it to grow the icon
        // (capped by the menu-bar thickness, which downsizes anything taller).
        let s: CGFloat = 1.2
        let H: CGFloat = 18 * s
        let pillX: CGFloat = 1 * s
        let dotR: CGFloat = 3 * s, dotCX: CGFloat = 9.5 * s
        let barW: CGFloat = 3.6 * s, advance: CGFloat = 5.4 * s, barH: CGFloat = 10 * s
        let barsStartX: CGFloat = 16 * s
        let cy = H / 2

        // GitHub contribution palette (level 0…4); 0 = faint placeholder.
        let empty = isDark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.14)
        let levelColors: [NSColor] = [
            empty,
            NSColor(srgbRed: 0.608, green: 0.914, blue: 0.659, alpha: 1), // #9be9a8
            NSColor(srgbRed: 0.251, green: 0.769, blue: 0.388, alpha: 1), // #40c463
            NSColor(srgbRed: 0.188, green: 0.631, blue: 0.306, alpha: 1), // #30a14e
            NSColor(srgbRed: 0.129, green: 0.431, blue: 0.224, alpha: 1), // #216e39
        ]
        let dotColor: NSColor
        if count == nil {
            dotColor = isDark ? NSColor(white: 1, alpha: 0.40) : NSColor(white: 0, alpha: 0.32)  // logged out
        } else if committed {
            dotColor = isDark ? NSColor(srgbRed: 0.247, green: 0.725, blue: 0.314, alpha: 1)     // #3fb950
                              : NSColor(srgbRed: 0.180, green: 0.643, blue: 0.310, alpha: 1)      // #2ea44f
        } else {
            dotColor = NSColor(srgbRed: 0.941, green: 0.333, blue: 0.420, alpha: 1)               // #f0556b
        }
        let textColor = isDark ? NSColor(white: 0.957, alpha: 1) : NSColor(white: 0.114, alpha: 1)
        let pillFill   = isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.05)
        let pillStroke = isDark ? NSColor(white: 1, alpha: 0.20) : NSColor(white: 0, alpha: 0.12)

        // Number font — rounded heavy, like the mockup's Baloo 2.
        let fontSize: CGFloat = 11.5 * s
        let base = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let font: NSFont = {
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: d, size: fontSize) ?? base
            }
            return base
        }()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let numStr: NSString? = count.map { "\($0)" as NSString }
        let numSize = numStr?.size(withAttributes: attrs) ?? .zero

        let barsEndX = barsStartX + CGFloat(6) * advance + barW   // 7 bars
        let numStartX = barsEndX + 5 * s
        // Logged out (no number) → pill ends just after the bars.
        let pillRight = numStr == nil ? barsEndX + 6 * s : numStartX + numSize.width + 7 * s
        let W = pillRight + 1 * s

        let img = NSImage(size: NSSize(width: ceil(W), height: H))
        img.lockFocus()

        // Pill background.
        let pill = NSBezierPath(roundedRect: NSRect(x: pillX, y: 1.5 * s, width: pillRight - pillX, height: H - 3 * s),
                                xRadius: 7.5 * s, yRadius: 7.5 * s)
        pillFill.setFill(); pill.fill()
        pillStroke.setStroke(); pill.lineWidth = 1; pill.stroke()

        // Left status dot.
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotCX - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()

        // Seven day bars (oldest → newest, today rightmost).
        for i in 0..<7 {
            let lvl = i < levels.count ? max(0, min(4, levels[i])) : 0
            levelColors[lvl].setFill()
            let x = barsStartX + CGFloat(i) * advance
            NSBezierPath(roundedRect: NSRect(x: x, y: cy - barH / 2, width: barW, height: barH),
                         xRadius: 1.3 * s, yRadius: 1.3 * s).fill()
        }

        // Today's commit count (skipped when logged out).
        numStr?.draw(at: NSPoint(x: numStartX, y: (H - numSize.height) / 2), withAttributes: attrs)

        img.unlockFocus()
        img.isTemplate = false   // keep real colors, not monochrome
        return img
    }

    /// Most recent 7 calendar days (up to today) as contribution levels, padded
    /// at the front if fewer are available.
    private func recent7Levels(_ vm: GipetViewModel) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var levels = vm.days.filter { $0.date <= today }.suffix(7).map { $0.level }
        while levels.count < 7 { levels.insert(0, at: 0) }
        return levels
    }

    private func refreshTitle() {
        let vm = GipetViewModel.shared
        if vm.isSignedIn, !vm.days.isEmpty, let button = statusItem?.button {
            let isDark = button.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            button.image = statusBarImage(levels: recent7Levels(vm),
                                          count: vm.stats.todayCount,
                                          committed: vm.stats.committedToday,
                                          isDark: isDark)
            button.imagePosition = .imageOnly
            button.title = ""
        } else if let button = statusItem?.button {
            // Logged out → the same pill, but empty (gray bars, neutral dot, no number).
            let isDark = button.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            button.image = statusBarImage(levels: Array(repeating: 0, count: 7),
                                          count: nil, committed: false, isDark: isDark)
            button.imagePosition = .imageOnly
            button.title = ""
        }
        gooseMenu?.items.forEach { mi in
            if let raw = mi.representedObject as? String,
               let kind = CharacterKind(rawValue: raw) {
                mi.state = (CharacterSettings.shared.current == kind) ? .on : .off
            }
        }
    }

    private func applyCharacterChoice() {
        Goose?.swapCharacter(to: CharacterSettings.shared.current)
    }

    @objc private func pickCharacter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = CharacterKind(rawValue: raw) else { return }
        CharacterSettings.shared.current = kind
        applyCharacterChoice()
        refreshTitle()
    }

    @objc private func menuSpeak() {
        let joke = DadJokes.random(avoiding: lastJoke)
        lastJoke = joke
        Goose?.Say(joke, duration: 6)
    }
    @objc private func menuHonk()       { Goose?.PlaySound(.HONCC) }
    @objc private func menuNabMouse()   { Goose?.SetTask(.NabMouse, honck: false) }
    @objc private func menuWander()     { Goose?.SetTask(.Wander,   honck: false) }
    @objc private func menuHeartTrail() { Goose?.SetTask(.HeartTrail, honck: false) }
    @objc private func menuTrackMud()   { Goose?.SetTask(.TrackMud, honck: false) }
    @objc private func menuQuit()       { NSApp.terminate(nil) }
}
