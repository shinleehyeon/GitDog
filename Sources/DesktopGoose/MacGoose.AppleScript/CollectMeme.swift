// Port of: MacGoose.AppleScript/CollectMeme.cs

import Foundation
import AppKit

@objc(CollectMemeCommand)
final class CollectMeme: ScriptCommand {
    override func PerformCommand() -> Any? {
        do {
            let stringArg = GetStringArg()
            var url: URL? = nil
            if let s = stringArg, !s.isEmpty {
                if s.hasPrefix("http") {
                    url = URL(string: s)
                } else if !s.hasPrefix("/") {
                    let base = AppDelegate.SharedAppDelegate.MemesDirectory
                    url = URL(string: s, relativeTo: base)
                } else {
                    url = URL(fileURLWithPath: s)
                }
            }
            if let u = url, u.isFileURL, !FileManager.default.fileExists(atPath: u.path) {
                url = nil
            }
            let image: NSImage? = url.flatMap { NSImage(contentsOf: $0) }
            AppDelegate.SharedAppDelegate.Goose?.ShowNextMeme(image, url, GetStringArg("title"))
        }
        return NSNumber(value: true)
    }
}
