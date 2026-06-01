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

    // The goose reads memes/notes directly from these project folders.
    // Drop a PNG into MemesDirectory and the next time the goose runs a
    // CollectWindow_Meme task it will pick from the new file list.
    static let ProjectMemesDir = "/Users/shinleehyeon/Dev/Projects/gipet/desktop-dog/Memes"
    static let ProjectNotesDir = "/Users/shinleehyeon/Dev/Projects/gipet/desktop-dog/Notes"

    var MemesDirectory: URL {
        URL(fileURLWithPath: AppDelegate.ProjectMemesDir, isDirectory: true)
    }
    var NotesDirectory: URL {
        URL(fileURLWithPath: AppDelegate.ProjectNotesDir, isDirectory: true)
    }
    static var HomeDirectory: String { NSHomeDirectory() }

    // Character toggle (goose/dachshund).
    private var statusItem: NSStatusItem?

    // Gipet — GitHub streak popover + commit watcher.
    private let gipet = MainStatusItemMenuManager()
    private var gooseMenu: NSMenu?

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
        // No copy step — the goose reads straight from the project Memes/ and Notes/ dirs.
        // This is the ONE place to edit images: AppDelegate.ProjectMemesDir.
        try? FileManager.default.createDirectory(atPath: AppDelegate.ProjectMemesDir,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: AppDelegate.ProjectNotesDir,
                                                 withIntermediateDirectories: true)
        Goose = MacintoshGoose(memesDirectory: AppDelegate.ProjectMemesDir,
                               notesDirectory: AppDelegate.ProjectNotesDir)
        NSApplication.shared.activate(ignoringOtherApps: true)
        installStatusItem()
        installGipet()
        applyCharacterChoice()
        installGlobalHotkey()
    }

    private func installGipet() {
        gipet.configurePopover()
        // No commit today → send the dog to fetch something: randomly an
        // image (Memes/) or a note (Notes/).
        gipet.onNoCommitNudge = { [weak self] in
            self?.Goose?.Say("커밋해! 🐾", duration: 5)
            let task: Goose.GooseTask = Bool.random() ? .CollectWindow_Meme : .CollectWindow_Notepad
            self?.Goose?.SetTask(task, honck: false)
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

    private func installGlobalHotkey() {
        let cmdCtrl = UInt32(cmdKey | controlKey)
        // kVK_ANSI_G = 5  → Cmd+Ctrl+G   → pop the menu near the cursor
        // kVK_ANSI_M = 46 → Cmd+Ctrl+M   → force the goose to fetch a meme right now
        HotkeyManager.shared.register(keyCode: 5,  modifiers: cmdCtrl) { [weak self] in
            self?.popupGooseMenuAtCursor()
        }
        HotkeyManager.shared.register(keyCode: 46, modifiers: cmdCtrl) { [weak self] in
            self?.Goose?.SetTask(.CollectWindow_Meme, honck: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ShowPreferences()
        return true
    }

    @objc func openMemesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(AppDelegate.SharedAppDelegate.MemesDirectory)
    }

    @objc func openNotesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(AppDelegate.SharedAppDelegate.NotesDirectory)
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

    // GitHub contribution colors (level 0...4) → a small rounded grass square.
    private func grassSquareImage(level: Int) -> NSImage {
        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.22, alpha: 1), // 0 empty
            NSColor(calibratedRed: 0.05, green: 0.27, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.43, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.65, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.83, blue: 0.33, alpha: 1),
        ]
        let c = colors[max(0, min(4, level))]
        let size = NSSize(width: 13, height: 13)
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(x: 1.5, y: 1.5, width: 10, height: 10)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        c.setFill()
        path.fill()
        img.unlockFocus()
        img.isTemplate = false   // keep the real green color, not monochrome
        return img
    }

    private func refreshTitle() {
        let charEmoji = CharacterSettings.shared.current == .goose ? "🪿" : "🐕"
        let vm = GipetViewModel.shared
        if vm.isSignedIn, !vm.days.isEmpty {
            // Today's grass square (GitHub colors) + today's commit count.
            statusItem?.button?.image = grassSquareImage(level: vm.todayLevel)
            statusItem?.button?.imagePosition = .imageLeading
            statusItem?.button?.title = " \(charEmoji) \(vm.stats.todayCount)"
        } else {
            statusItem?.button?.image = nil
            statusItem?.button?.title = charEmoji
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

    @objc private func menuHonk()       { Goose?.PlaySound(.HONCC) }
    @objc private func menuNabMouse()   { Goose?.SetTask(.NabMouse, honck: false) }
    @objc private func menuWander()     { Goose?.SetTask(.Wander,   honck: false) }
    @objc private func menuHeartTrail() { Goose?.SetTask(.HeartTrail, honck: false) }
    @objc private func menuTrackMud()   { Goose?.SetTask(.TrackMud, honck: false) }
    @objc private func menuQuit()       { NSApp.terminate(nil) }
}
