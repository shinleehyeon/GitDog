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
        applyCharacterChoice()
        installGlobalHotkey()
    }

    private func installGlobalHotkey() {
        let cmdCtrl = UInt32(cmdKey | controlKey)
        // kVK_ANSI_G = 5  → Cmd+Ctrl+G   → pop the menu near the cursor
        // kVK_ANSI_M = 46 → Cmd+Ctrl+M   → force the goose to fetch a meme right now
        HotkeyManager.shared.register(keyCode: 5,  modifiers: cmdCtrl) { [weak self] in
            self?.popupMenuAtCursor()
        }
        HotkeyManager.shared.register(keyCode: 46, modifiers: cmdCtrl) { [weak self] in
            self?.Goose?.SetTask(.CollectWindow_Meme, honck: false)
        }
    }

    private func popupMenuAtCursor() {
        guard let menu = statusItem?.menu else { return }
        // Accessory apps don't get focus by default; activate so the menu can take input.
        NSApplication.shared.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation        // screen coords, bottom-left origin
        menu.popUp(positioning: nil, at: mouse, in: nil)
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
        item.menu = menu
        self.statusItem = item
        refreshTitle()
    }

    private func refreshTitle() {
        statusItem?.button?.title = CharacterSettings.shared.current == .goose ? "🪿" : "🐕"
        statusItem?.menu?.items.forEach { mi in
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
