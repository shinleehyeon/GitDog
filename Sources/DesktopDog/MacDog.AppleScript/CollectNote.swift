// Port of: MacGoose.AppleScript/CollectNote.cs

import Foundation

@objc(CollectNoteCommand)
final class CollectNote: ScriptCommand {
    override func PerformCommand() -> Any? {
        AppDelegate.SharedAppDelegate.Goose?.ShowNote(GetStringArg() ?? "", GetStringArg("title"))
        return NSNumber(value: true)
    }
}
