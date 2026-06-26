// Port of: MacGoose.AppleScript/OpenNotesFolder.cs

import Foundation
import AppKit

@objc(OpenNotesFolderCommand)
final class OpenNotesFolder: ScriptCommand {
    override func PerformCommand() -> Any? {
        let url = AppDelegate.SharedAppDelegate.NotesDirectory
        NSWorkspace.shared.open(url)
        return NSNumber(value: true)
    }
}
