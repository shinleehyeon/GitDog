import Foundation
import Combine

/// User-adjustable behavior weights. Each value is 0–5:
///   0 = never, 1 = rarely, 5 = very often.
final class BehaviorSettings: ObservableObject {
    static let shared = BehaviorSettings()

    @Published var memeWeight: Int      { didSet { save("b.meme",   memeWeight) } }
    @Published var noteWeight: Int      { didSet { save("b.note",   noteWeight) } }
    @Published var mudWeight: Int       { didSet { save("b.mud",    mudWeight) } }
    @Published var nabMouseWeight: Int  { didSet { save("b.nab",    nabMouseWeight) } }
    @Published var friendsWeight: Int   { didSet { save("b.friends",friendsWeight) } }

    private init() {
        let d = UserDefaults.standard
        memeWeight     = d.object(forKey: "b.meme")    as? Int ?? 5
        noteWeight     = d.object(forKey: "b.note")    as? Int ?? 1
        mudWeight      = d.object(forKey: "b.mud")     as? Int ?? 1
        nabMouseWeight = d.object(forKey: "b.nab")     as? Int ?? 0
        friendsWeight  = d.object(forKey: "b.friends") as? Int ?? 1
    }

    private func save(_ key: String, _ value: Int) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .behaviorSettingsChanged, object: nil)
    }

    /// Build the weighted task list for the Goose's Deck picker.
    /// BringFriends is handled separately via a time-based gate, not this list.
    func buildWeightedList() -> [Goose.GooseTask] {
        var list: [Goose.GooseTask] = []
        list += Array(repeating: .CollectWindow_Meme,    count: memeWeight)
        list += Array(repeating: .CollectWindow_Notepad, count: noteWeight)
        list += Array(repeating: .TrackMud,              count: mudWeight)
        list += Array(repeating: .NabMouse,              count: nabMouseWeight)
        return list.isEmpty ? [.Wander] : list
    }
}

extension Notification.Name {
    static let behaviorSettingsChanged = Notification.Name("BehaviorSettingsChanged")
}
