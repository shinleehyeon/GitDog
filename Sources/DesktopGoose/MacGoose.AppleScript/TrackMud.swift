// Port of: MacGoose.AppleScript/TrackMud.cs

import Foundation

@objc(TrackMudCommand)
final class TrackMud: ScriptCommand {
    override func PerformCommand() -> Any? {
        AppDelegate.SharedAppDelegate.Goose?.SetTask(.TrackMud, honck: false)
        return NSNumber(value: true)
    }
}
