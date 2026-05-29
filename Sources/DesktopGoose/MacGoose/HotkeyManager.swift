// Local addition — system-wide hotkeys via Carbon's RegisterEventHotKey.
// Used as a fallback for users whose menu bar is hidden by a manager app
// (Bartender, Hidden Bar, etc.). Supports multiple bindings.

import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    static let shared = HotkeyManager()
    private init() {}

    private var bindings: [UInt32: () -> Void] = [:]    // hotKeyID → handler
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var eventHandlerInstalled = false

    /// Register a system-wide hotkey. Modifiers: cmdKey, controlKey, optionKey, shiftKey.
    func register(keyCode: UInt32, modifiers: UInt32, _ handler: @escaping () -> Void) {
        installHandlerOnce()
        let id = nextID
        nextID += 1
        bindings[id] = handler

        let hotKeyID = EventHotKeyID(signature: OSType(0x44475345), id: id)  // 'DGSE'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            print("RegisterEventHotKey failed (id=\(id)): \(status)")
            return
        }
        hotKeyRefs.append(ref)
    }

    private func installHandlerOnce() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            { _, eventRef, userData -> OSStatus in
                                guard let userData, let eventRef else { return noErr }
                                var hotKeyID = EventHotKeyID()
                                GetEventParameter(eventRef,
                                                  EventParamName(kEventParamDirectObject),
                                                  EventParamType(typeEventHotKeyID),
                                                  nil,
                                                  MemoryLayout<EventHotKeyID>.size,
                                                  nil,
                                                  &hotKeyID)
                                let mgr = Unmanaged<HotkeyManager>
                                    .fromOpaque(userData).takeUnretainedValue()
                                let id = hotKeyID.id
                                DispatchQueue.main.async { mgr.bindings[id]?() }
                                return noErr
                            },
                            1, &eventSpec, selfPtr, nil)
    }
}
