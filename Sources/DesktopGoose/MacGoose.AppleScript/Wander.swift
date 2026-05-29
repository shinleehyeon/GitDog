// Port of: MacGoose.AppleScript/Wander.cs

import Foundation

@objc(WanderCommand)
final class Wander: ScriptCommand {
    override func PerformCommand() -> Any? {
        guard let goose = AppDelegate.SharedAppDelegate.Goose else { return NSNumber(value: false) }
        goose.ScheduledWanderTime = GetFloatArg("duration")
        goose.SetTask(.Wander, honck: false)
        return NSNumber(value: true)
    }
}
