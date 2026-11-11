import AVFoundation

/// One sound of a mode: a bed that loops for as long as the mode falls, or a call heard now and then.
private struct Layer {
    /// The file in the app's `Sounds/` folder, without its extension; a call names the first of `name-1`, `name-2`…
    let name: String
    let gain: Float
    /// Seconds between calls at full intensity; nil for a bed.
    var every: ClosedRange<Double>? = nil
    var variants = 1
    /// How far a call may sit to either side, 0 for the middle.
    var spread: Float = 0.6
}

/// The sound of what falls: beds that loop under it and calls now and then, faded across mode changes, following the
/// intensity, and silent while nobody can see the snow. A folder of the person's own music can play underneath.
///
/// Files stream from disk instead of being held in memory, and the engine lets go of the audio device once all is
/// quiet, so the app costs nothing while the sound is off.
final class Ambience {
    private static let layers: [Mode: [Layer]] = [
        .snow: [
            Layer(name: "snow-night", gain: 0.9),
            Layer(name: "snow-wind", gain: 0.45),
        ],
        .autumn: [
            Layer(name: "autumn-trees", gain: 0.85),
            Layer(name: "autumn-leaves", gain: 0.5),
        ],
        .rain: [
            Layer(name: "rain-leaves", gain: 0.85),
            Layer(name: "rain-window", gain: 0.5),
            Layer(name: "thunder", gain: 0.55, every: 70...160, variants: 3, spread: 0.4),
        ],
        .blossom: [
            Layer(name: "blossom-breeze", gain: 0.6),
            Layer(name: "blossom-birds", gain: 0.6),
        ],
    ]
    private static let halloweenLayers = [
        Layer(name: "halloween-night", gain: 0.6),
        Layer(name: "owl", gain: 0.5, every: 35...90, variants: 2),
        Layer(name: "crow", gain: 0.35, every: 60...150, variants: 2, spread: 0.8),
    ]
    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf", "flac", "aac"]
    /// The person's own beds, one folder per mode, used in place of the built-in ones when not empty.
    static let customFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Snowhush/Sounds", isDirectory: true)

    private let engine = AVAudioEngine()
    private var voices: [String: Voice] = [:]
    private var music: MusicPlayer?
    private var ticker: Timer?
    private var quietSince: CFTimeInterval?

    var on = false {
        didSet {
            fadeSeconds = 3
            refresh()
        }
    }
    /// How long a sound takes to come in or go, from none to all of it.
    private var fadeSeconds: Float = 3

    /// Turns the sound off slowly, as a sleep timer ends.
    func fadeOut(over seconds: Float) {
        on = false
        fadeSeconds = seconds
    }
    var volume: Float = 0.7 { didSet { refresh() } }
    var musicVolume: Float = 0.5 { didSet { refresh() } }
    var musicFolder: URL? {
        didSet {
            guard musicFolder != oldValue else { return }
            music?.stop()
            music = musicFolder.map { MusicPlayer(folder: $0, engine: engine) }
            music?.trackChanged = { [weak self] in self?.trackChanged() }
            refresh()
        }
    }
    /// The person's track now playing, if any.
    var track: URL? { music?.track }
    var trackChanged: () -> Void = {}

    func skipTrack() { music?.skip() }

    private var modes: [Mode] = []
    private var halloween = false
    private var intensity = 0.0
    /// Somebody can see the snow: the screens are awake and unlocked, and it isn't hidden for a full-screen app.
    private var audible = false

    init() {
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    func update(modes: [Mode], halloween: Bool, intensity: Double, audible: Bool) {
        self.modes = modes
        self.halloween = halloween
        self.intensity = intensity
        self.audible = audible
        refresh()
    }

    /// Every sound's level worked out again, and the fade toward it started.
    private func refresh() {
        let heard = on && audible
        var wanted: [String: (layer: Layer, files: [URL], gain: Float)] = [:]
        if heard, intensity > 0 {
            // Gentle snow still whispers; a storm is loud, but never twice as loud as a drizzle.
            let level = volume * Float(0.45 + 0.55 * intensity)
            let weight: Float = modes.count > 1 ? 0.7 : 1
            for mode in modes {
                for (layer, files) in Self.layers(for: mode) {
                    wanted["\(mode.key)/\(layer.name)"] = (layer, files, level * weight * layer.gain)
                }
            }
            if halloween {
                for (layer, files) in Self.layers(named: "halloween", builtIn: Self.halloweenLayers) {
                    wanted["halloween/\(layer.name)"] = (layer, files, level * layer.gain)
                }
            }
        }
        for (key, want) in wanted where voices[key] == nil {
            guard let voice = Voice(layer: want.layer, files: want.files, engine: engine) else { continue }
            voices[key] = voice
        }
        for (key, voice) in voices {
            voice.target = wanted[key]?.gain ?? 0
            voice.pace = 0.5 + intensity
        }
        music?.target = heard ? musicVolume * volume : 0

        let sounding = voices.values.contains { $0.target > 0 } || (music?.target ?? 0) > 0
        if sounding {
            quietSince = nil
            if !engine.isRunning { start() }
        }
        if sounding || voices.values.contains(where: { $0.level > 0 }) || (music?.level ?? 0) > 0 { tick() }
    }

    private func start() {
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("Snowhush: audio engine failed to start: \(error)")
            return
        }
        for voice in voices.values where voice.target > 0 { voice.play() }
        if let music, music.target > 0 { music.play() }
    }

    /// The output changed, headphones in or out: the engine has stopped and its players lost what was queued.
    private func restart() {
        let wasRunning = voices.values.contains { $0.isPlaying } || music?.isPlaying == true
        for voice in voices.values { voice.stop() }
        music?.stop()
        guard wasRunning else { return }
        start()
    }

    private func tick() {
        guard ticker == nil else { return }
        // In the common modes, so a fade goes on, and the volume slider is heard, while the menu is open.
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Levels move toward their targets, a mode fading over three seconds; once all is quiet a while, the engine stops.
    private func step() {
        let delta: Float = 1.0 / 20 / fadeSeconds
        var moving = false
        for (key, voice) in voices {
            moving = voice.step(delta) || moving
            if voice.target == 0, voice.level == 0 {
                voice.detach()
                voices[key] = nil
            }
        }
        if let music { moving = music.step(delta) || moving }
        let sounding = voices.values.contains { $0.level > 0 } || (music?.level ?? 0) > 0
        if sounding || moving {
            quietSince = nil
            return
        }
        let now = CACurrentMediaTime()
        guard let since = quietSince else {
            quietSince = now
            return
        }
        guard now - since > 2 else { return }
        ticker?.invalidate()
        ticker = nil
        music?.stop()
        engine.stop()
    }

    /// The beds and calls of `mode`: the person's own, if its folder has any, otherwise the built-in ones.
    private static func layers(for mode: Mode) -> [(Layer, [URL])] {
        layers(named: mode.key, builtIn: layers[mode] ?? [])
    }

    private static func layers(named name: String, builtIn: [Layer]) -> [(Layer, [URL])] {
        let custom = audioFiles(in: customFolder.appendingPathComponent(name, isDirectory: true), deep: false)
        if !custom.isEmpty {
            let gain = 0.8 / Float(custom.count).squareRoot()
            return custom.map { (Layer(name: $0.deletingPathExtension().lastPathComponent, gain: gain), [$0]) }
        }
        return builtIn.compactMap { layer in
            let names = layer.variants == 1 && layer.every == nil ? [layer.name] : (1...layer.variants).map { "\(layer.name)-\($0)" }
            let files = names.compactMap { Bundle.main.url(forResource: $0, withExtension: "m4a", subdirectory: "Sounds") }
            return files.isEmpty ? nil : (layer, files)
        }
    }

    static func audioFiles(in folder: URL, deep: Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let found: [URL]
        if deep {
            let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            found = (walk?.allObjects as? [URL]) ?? []
        } else {
            found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        }
        return found.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Creates the custom folders, each mode's, with a note on what goes in them.
    static func prepareCustomFolder() -> URL {
        let manager = FileManager.default
        for name in Mode.allCases.map(\.key) + ["halloween"] {
            try? manager.createDirectory(at: customFolder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let note = customFolder.appendingPathComponent("README.txt")
        if !manager.fileExists(atPath: note.path) {
            let text = """
            Drop your own sounds into a mode's folder (snow, autumn, rain, blossom, halloween) to hear them in place of
            Snowhush's. Every file in the folder loops at once, layered: use seamless loops (m4a, mp3, wav, aiff, caf,
            flac). Empty the folder to hear the built-in sounds again. Changes are heard the next time the mode starts.
            """
            try? text.write(to: note, atomically: true, encoding: .utf8)
        }
        return customFolder
    }
}

/// A layer's player, its level faded by hand on its own mixer.
private final class Voice {
    private let layer: Layer
    private let files: [AVAudioFile]
    private let player = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    private weak var engine: AVAudioEngine?
    /// Bumped on every stop, so completions of what was queued before don't queue more.
    private var generation = 0
    private var nextCall: CFTimeInterval = 0
    private(set) var isPlaying = false
    var target: Float = 0
    var level: Float = 0
    /// How much more often calls come, with the intensity.
    var pace = 1.0

    init?(layer: Layer, files urls: [URL], engine: AVAudioEngine) {
        let readable = urls.compactMap { try? AVAudioFile(forReading: $0) }.filter { $0.length > 0 }
        guard let format = readable.first?.processingFormat else { return nil }
        // A player takes one format; a dropped-in file of another rate or channel count would bring the app down.
        let files = readable.filter { $0.processingFormat == format }
        self.layer = layer
        self.files = files
        self.engine = engine
        engine.attach(player)
        engine.attach(mixer)
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixer.outputVolume = 0
    }

    func play() {
        guard !isPlaying, engine?.isRunning == true else { return }
        isPlaying = true
        if layer.every != nil { scheduleCall(first: true) }
        if layer.every == nil {
            // Each time from somewhere else in the recording, so the same moment doesn't open every session.
            let file = files[0]
            let start = AVAudioFramePosition.random(in: 0..<max(file.length, 1))
            player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
            queueLoop()
            queueLoop()
        }
        player.play()
    }

    private func queueLoop() {
        let generation = generation
        player.scheduleFile(files[0], at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == generation, self.isPlaying else { return }
                self.queueLoop()
            }
        }
    }

    func stop() {
        generation += 1
        isPlaying = false
        player.stop()
    }

    func detach() {
        stop()
        engine?.detach(player)
        engine?.detach(mixer)
    }

    /// Moves the level a step toward the target; true while it is still moving.
    func step(_ delta: Float) -> Bool {
        if target > 0, !isPlaying { play() }
        if level < target { level = min(level + delta, target) } else if level > target { level = max(level - delta, target) }
        mixer.outputVolume = level
        if level == 0, target == 0, isPlaying { stop() }
        if layer.every != nil, isPlaying, level > 0, CACurrentMediaTime() >= nextCall { call() }
        return level != target
    }

    private func call() {
        let file = files.randomElement()!
        player.pan = Float.random(in: -layer.spread...layer.spread)
        player.volume = Float.random(in: 0.55...1)
        player.scheduleFile(file, at: nil)
        scheduleCall(first: false)
    }

    private func scheduleCall(first: Bool) {
        guard let every = layer.every else { return }
        // The first call waits a while, so a mode doesn't open with thunder.
        let wait = Double.random(in: every) / pace * (first ? 0.6 : 1)
        nextCall = CACurrentMediaTime() + wait
    }
}

/// The person's own music, shuffled, one track after another.
final class MusicPlayer {
    private let folder: URL
    private let player = AVAudioPlayerNode()
    private weak var engine: AVAudioEngine?
    private var queue: [URL] = []
    private var connected: AVAudioFormat?
    private var generation = 0
    private(set) var isPlaying = false
    var target: Float = 0
    var level: Float = 0

    init(folder: URL, engine: AVAudioEngine) {
        self.folder = folder
        self.engine = engine
        engine.attach(player)
        player.volume = 0
    }

    func play() {
        guard !isPlaying, engine?.isRunning == true else { return }
        isPlaying = true
        next()
        player.play()
    }

    /// The track playing, nil before the first or when the folder holds nothing playable.
    private(set) var track: URL?
    var trackChanged: () -> Void = {}

    /// Whether the folder holds any music at all.
    static func hasMusic(in folder: URL) -> Bool { !Ambience.audioFiles(in: folder, deep: true).isEmpty }

    /// On to another track at once.
    func skip() {
        guard isPlaying else { return }
        generation += 1
        player.stop()
        next()
        player.play()
    }

    private func next() {
        guard let engine else { return }
        // Every file in the folder may be tried once; a broken or unsupported one is passed over, not stalled on.
        if queue.isEmpty { queue = Ambience.audioFiles(in: folder, deep: true).shuffled() }
        for _ in 0..<queue.count {
            let url = queue.removeFirst()
            if queue.isEmpty { queue = Ambience.audioFiles(in: folder, deep: true).shuffled().filter { $0 != url } }
            guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { continue }
            // Tracks differ in rate: the player is joined anew in the format of each.
            if connected != file.processingFormat {
                engine.disconnectNodeOutput(player)
                engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
                connected = file.processingFormat
            }
            let generation = generation
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == generation, self.isPlaying else { return }
                    self.player.stop()
                    self.next()
                    self.player.play()
                }
            }
            track = url
            trackChanged()
            return
        }
        track = nil
        trackChanged()
    }

    func stop() {
        generation += 1
        isPlaying = false
        player.stop()
        if track != nil {
            track = nil
            trackChanged()
        }
    }

    func step(_ delta: Float) -> Bool {
        if target > 0, !isPlaying { play() }
        if level < target { level = min(level + delta, target) } else if level > target { level = max(level - delta, target) }
        player.volume = level
        if level == 0, target == 0, isPlaying { stop() }
        return level != target
    }

    deinit {
        stop()
        engine?.detach(player)
    }
}
