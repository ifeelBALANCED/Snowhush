import Foundation

/// A mood in one click: what falls, how much of it, and how loud it sounds. Picking one turns the sound on.
struct Preset: Codable, Equatable {
    var name: String
    var modes: [Mode]
    var intensity: Double
    var volume: Double

    /// The ones that come with the app; their names are looked up by key.
    static let builtIn: [(key: String, preset: Preset)] = [
        ("preset.winter", Preset(name: "", modes: [.snow], intensity: 0.75, volume: 0.7)),
        ("preset.autumn", Preset(name: "", modes: [.autumn], intensity: 0.5, volume: 0.65)),
        ("preset.rain", Preset(name: "", modes: [.rain], intensity: 0.6, volume: 0.7)),
        ("preset.spring", Preset(name: "", modes: [.blossom], intensity: 0.4, volume: 0.6)),
        // Steady rain masks voices and keyboards best, and little of it falls to draw the eye.
        ("preset.focus", Preset(name: "", modes: [.rain], intensity: 0.25, volume: 0.45)),
    ].map { ($0.0, Preset(name: tr($0.0), modes: $0.1.modes, intensity: $0.1.intensity, volume: $0.1.volume)) }

    /// Whether the app is set as this preset says, give or take a nudge of a slider.
    func matches(modes: [Mode], intensity: Double, volume: Double, sound: Bool) -> Bool {
        sound && Set(modes) == Set(self.modes) && abs(intensity - self.intensity) < 0.03 && abs(volume - self.volume) < 0.03
    }
}

extension Mode: Codable {}

extension Preferences {
    private static let presetsKey = "presets"

    /// The person's own presets, in the order they were saved.
    static var presets: [Preset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: presetsKey) else { return [] }
            return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: presetsKey) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
