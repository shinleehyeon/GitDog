// Local addition (not part of the .NET source) — character asset toggle.

import Foundation

enum CharacterKind: String, CaseIterable, Identifiable {
    case chick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chick: return "Dachshund 🐕"
        }
    }
}

final class CharacterSettings {
    static let shared = CharacterSettings()
    private let key = "DesktopGoose.character"

    var current: CharacterKind {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let kind = CharacterKind(rawValue: raw) { return kind }
            // Gipet.app first launch default should be dachshund.
            return .chick
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    private init() {}
}
