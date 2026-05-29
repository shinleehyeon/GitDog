// Port of: GooseDesktop/GooseConfig.cs

import Foundation

public enum GooseConfig {
    public class ConfigSettings {
        var Version: Int = 0

        @objc dynamic var CanAttackAtRandom: Bool { get { _canAttackAtRandom } set { _canAttackAtRandom = newValue } }
        @objc dynamic var MinWanderingTimeSeconds: Float { get { _minWanderingTimeSeconds } set { _minWanderingTimeSeconds = newValue } }
        @objc dynamic var MaxWanderingTimeSeconds: Float { get { _maxWanderingTimeSeconds } set { _maxWanderingTimeSeconds = newValue } }
        @objc dynamic var FirstWanderTimeSeconds: Float { get { _firstWanderTimeSeconds } set { _firstWanderTimeSeconds = newValue } }
        @objc dynamic var FrameRate: Float { get { _frameRate } set { _frameRate = newValue } }

        var _canAttackAtRandom: Bool = false
        var _minWanderingTimeSeconds: Float = 20
        var _maxWanderingTimeSeconds: Float = 40
        var _firstWanderTimeSeconds: Float = 20
        var _frameRate: Float = 60

        static func ReadFileIntoConfig(_ configGivenPath: String) -> ConfigSettings {
            let settings = ConfigSettings()
            let fm = FileManager.default
            if !fm.fileExists(atPath: configGivenPath) {
                print("Can't find config.goos file! Creating a new one with default values")
                WriteConfigToFile(configGivenPath, settings)
                return settings
            }
            do {
                let text = try String(contentsOfFile: configGivenPath, encoding: .utf8)
                var dict: [String: String] = [:]
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 {
                        dict[String(parts[0])] = String(parts[1])
                    }
                }
                var versionResult = -1
                if let v = dict["Version"], let parsed = Int(v) { versionResult = parsed }
                if versionResult != 0 {
                    print("config.goos is for the wrong version! Creating a new one with default values!")
                    try? fm.removeItem(atPath: configGivenPath)
                    WriteConfigToFile(configGivenPath, settings)
                    return settings
                }
                for (key, value) in dict {
                    settings.setField(key, value)
                }
                return settings
            } catch {
                print("config.goos corrupt! Creating a new one!")
                try? fm.removeItem(atPath: configGivenPath)
                WriteConfigToFile(configGivenPath, settings)
                return settings
            }
        }

        static func WriteConfigToFile(_ path: String, _ f: ConfigSettings) {
            try? GenerateTextFromSettings(f).write(toFile: path, atomically: true, encoding: .utf8)
        }

        static func GenerateTextFromSettings(_ f: ConfigSettings) -> String {
            var sb = ""
            sb += "Version=\(f.Version)\n"
            sb += "CanAttackAtRandom=\(f.CanAttackAtRandom)\n"
            sb += "MinWanderingTimeSeconds=\(f.MinWanderingTimeSeconds)\n"
            sb += "MaxWanderingTimeSeconds=\(f.MaxWanderingTimeSeconds)\n"
            sb += "FirstWanderTimeSeconds=\(f.FirstWanderTimeSeconds)\n"
            sb += "FrameRate=\(f.FrameRate)\n"
            return sb
        }

        func setField(_ name: String, _ value: String) {
            switch name {
            case "Version":                  if let v = Int(value)   { Version = v }
            case "CanAttackAtRandom":        if let v = Bool(value)  { _canAttackAtRandom = v }
            case "MinWanderingTimeSeconds":  if let v = Float(value) { _minWanderingTimeSeconds = v }
            case "MaxWanderingTimeSeconds":  if let v = Float(value) { _maxWanderingTimeSeconds = v }
            case "FirstWanderTimeSeconds":   if let v = Float(value) { _firstWanderTimeSeconds = v }
            case "FrameRate":                if let v = Float(value) { _frameRate = v }
            default: print("Loading config error: field \(name) is not valid. Setting it to the default value.")
            }
        }
    }

    public static let GOOSE_CONFIG_VERSION: Int = 0

    public static var settings: ConfigSettings = ConfigSettings()

    public static func LoadConfig(_ filePath: String) {
        settings = ConfigSettings.ReadFileIntoConfig(filePath)
    }
}
