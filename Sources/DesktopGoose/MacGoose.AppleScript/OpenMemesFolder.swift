// Port of: MacGoose.AppleScript/OpenMemesFolder.cs

import Foundation
import AppKit

@objc(OpenMemesFolderCommand)
final class OpenMemesFolder: ScriptCommand {
    override func PerformCommand() -> Any? {
        let url = AppDelegate.SharedAppDelegate.MemesDirectory
        NSWorkspace.shared.open(url)
        return NSNumber(value: true)
    }
}
