// Port of: MacGoose/MacGooseSettings.cs

import Foundation
import AppKit
import CoreGraphics

final class MacGooseSettings: GooseConfig.ConfigSettings {
    static let CanAttackAtRandomKey = "CanAttackAtRandom"
    static let MinWanderingTimeKey  = "MinWanderingTimeSeconds"
    static let MaxWanderingTimeKey  = "MaxWanderingTimeSeconds"
    static let FirstWanderTimeKey   = "FirstWanderTimeSeconds"
    static let FrameRateKey         = "FrameRate"
    static let UseCustomColorsKey   = "UseCustomColors"
    static let WhiteColorKey        = "GooseWhite"
    static let OrangeColorKey       = "GooseOrange"
    static let OutlineColorKey      = "GooseOutline"
    static let EyeColorKey          = "GooseEye"
    static let MudColorKey          = "GooseMud"
    static let SoundVolumeKey       = "SoundVolume"

    private static let WhiteColorDefault   = "#ffffff"
    private static let OrangeColorDefault  = "#ffa500"
    private static let OutlineColorDefault = "#d3d3d3"
    private static let EyeColorDefault     = "#000000"
    private static let MudColorDefault     = "#8b4513"

    private var observers: [NSObjectProtocol] = []

    var UseCustomColors: Bool = false

    override var CanAttackAtRandom: Bool {
        get { UserDefaults.standard.bool(forKey: MacGooseSettings.CanAttackAtRandomKey) }
        set { super.CanAttackAtRandom = newValue }
    }
    override var MinWanderingTimeSeconds: Float {
        get { UserDefaults.standard.float(forKey: MacGooseSettings.MinWanderingTimeKey) }
        set { super.MinWanderingTimeSeconds = newValue }
    }
    override var MaxWanderingTimeSeconds: Float {
        get { UserDefaults.standard.float(forKey: MacGooseSettings.MaxWanderingTimeKey) }
        set { super.MaxWanderingTimeSeconds = newValue }
    }
    override var FirstWanderTimeSeconds: Float {
        get { UserDefaults.standard.float(forKey: MacGooseSettings.FirstWanderTimeKey) }
        set { super.FirstWanderTimeSeconds = newValue }
    }
    override var FrameRate: Float {
        get { UserDefaults.standard.float(forKey: MacGooseSettings.FrameRateKey) }
        set { super.FrameRate = newValue }
    }

    private(set) var GooseWhite:   CGColor!
    private(set) var GooseOrange:  CGColor!
    private(set) var GooseOutline: CGColor!
    private(set) var GooseEye:     CGColor!
    private(set) var GooseMud:     CGColor!

    override init() {
        super.init()
        let d = UserDefaults.standard
        d.register(defaults: [
            MacGooseSettings.CanAttackAtRandomKey: false,
            // User-tuned: bring memes more often → shorter wander interludes.
            MacGooseSettings.MinWanderingTimeKey:  Float(4),
            MacGooseSettings.MaxWanderingTimeKey:  Float(10),
            MacGooseSettings.FirstWanderTimeKey:   Float(3),
            MacGooseSettings.FrameRateKey:         Float(60),
            MacGooseSettings.UseCustomColorsKey:   false,
            MacGooseSettings.WhiteColorKey:        MacGooseSettings.WhiteColorDefault,
            MacGooseSettings.OrangeColorKey:       MacGooseSettings.OrangeColorDefault,
            MacGooseSettings.OutlineColorKey:      MacGooseSettings.OutlineColorDefault,
            MacGooseSettings.EyeColorKey:          MacGooseSettings.EyeColorDefault,
            MacGooseSettings.MudColorKey:          MacGooseSettings.MudColorDefault,
            MacGooseSettings.SoundVolumeKey:       Float(1)
        ])
        LoadColors()

        let nc = NotificationCenter.default
        // Listen for any UserDefaults change — reload colors.
        let token = nc.addObserver(forName: UserDefaults.didChangeNotification,
                                   object: d, queue: .main) { [weak self] _ in
            self?.LoadColors()
        }
        observers.append(token)
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func LoadColors() {
        let d = UserDefaults.standard
        UseCustomColors = d.bool(forKey: MacGooseSettings.UseCustomColorsKey)
        if UseCustomColors {
            GooseWhite   = MacGooseSettings.ColorFromHexString(d.string(forKey: MacGooseSettings.WhiteColorKey)   ?? MacGooseSettings.WhiteColorDefault)
            GooseOrange  = MacGooseSettings.ColorFromHexString(d.string(forKey: MacGooseSettings.OrangeColorKey)  ?? MacGooseSettings.OrangeColorDefault)
            GooseOutline = MacGooseSettings.ColorFromHexString(d.string(forKey: MacGooseSettings.OutlineColorKey) ?? MacGooseSettings.OutlineColorDefault)
            GooseEye     = MacGooseSettings.ColorFromHexString(d.string(forKey: MacGooseSettings.EyeColorKey)     ?? MacGooseSettings.EyeColorDefault)
            GooseMud     = MacGooseSettings.ColorFromHexString(d.string(forKey: MacGooseSettings.MudColorKey)     ?? MacGooseSettings.MudColorDefault)
        } else {
            GooseWhite   = MacGooseSettings.ColorFromHexString(MacGooseSettings.WhiteColorDefault)
            GooseOrange  = MacGooseSettings.ColorFromHexString(MacGooseSettings.OrangeColorDefault)
            GooseOutline = MacGooseSettings.ColorFromHexString(MacGooseSettings.OutlineColorDefault)
            GooseEye     = MacGooseSettings.ColorFromHexString(MacGooseSettings.EyeColorDefault)
            GooseMud     = MacGooseSettings.ColorFromHexString(MacGooseSettings.MudColorDefault)
        }
    }

    static func ColorFromHexString(_ hexString: String) -> CGColor {
        let text = hexString.replacingOccurrences(of: "#", with: "")
        let num = Int(text, radix: 16) ?? 0
        var r: Float = 0, g: Float = 0, b: Float = 0
        switch text.count {
        case 3:
            r = Float((num & 0xF00) >> 8) / 15
            g = Float((num & 0xF0)  >> 4) / 15
            b = Float(num & 0xF)           / 15
        case 6:
            r = Float((num & 0xFF0000) >> 16) / 255
            g = Float((num & 0xFF00)   >> 8)  / 255
            b = Float(num & 0xFF)              / 255
        default: break
        }
        return CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}
