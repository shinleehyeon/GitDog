// Port of: MacGoose.AppleScript/Honk.cs

import Foundation

@objc(HonkCommand)
final class Honk: ScriptCommand {
    override func PerformCommand() -> Any? {
        AppDelegate.SharedAppDelegate.Goose?.PlaySound(.HONCC)
        return NSNumber(value: true)
    }
}
