// Port of: MacGoose/MainClass.cs

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // Menu-bar app; the original used Info.plist for this.
app.run()
