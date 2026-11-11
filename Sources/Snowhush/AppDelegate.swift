import AppKit
import MetalKit
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
    private var device: MTLDevice!
    private var screens: [ScreenSnow] = []
    private let displays = Displays()
    private var surfaces: Surfaces = []
    private var thaws = true
    private var behindWindows = false
    private var snowfallHeld = false
    private var halloween = false
    private var statusItem: NSStatusItem!
    private let intensitySlider = MenuSlider(range: 0...1)
    private let opacitySlider = MenuSlider(range: Preferences.opacityRange, captioned: false)
    private var opacityItem: NSMenuItem!
    private let opacityRow = MenuDisclosure()
    private var opacitySliderItem: NSMenuItem!
    private var accumulateItem: NSMenuItem!
    private let accumulateRow = MenuDisclosure()
    private var surfacesItem: NSMenuItem!
    private let surfacePicker = SurfacePicker()
    private var meltItem: NSMenuItem!
    private var clearItem: NSMenuItem!
    private var halloweenItem: NSMenuItem!
    private var mixedItem: NSMenuItem!
    private var modeItems: [(item: NSMenuItem, mode: Mode)] = []
    private var maxPerformanceItem: NSMenuItem!
    private var behindWindowsItem: NSMenuItem!
    private var fullScreenItem: NSMenuItem!
    private var screenshotsItem: NSMenuItem!
    private var deepInteractionItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private let screenshots = ScreenshotWatch()
    private var screenLocked = false
    private var sessionInactive = false
    private var updater: SPUStandardUpdaterController!
    private var welcome: WelcomeController?
    private let power = PowerMonitor()
    private var halloweenTimer: Timer?
    private let ambience = Ambience()
    private var soundItem: NSMenuItem!
    private let soundSlider = MenuSlider(range: 0...1)
    private let musicSlider = MenuSlider(range: 0...1)
    private var musicChooseItem: NSMenuItem!
    private var musicSliderItem: NSMenuItem!
    private var musicStopItem: NSMenuItem!
    private var trackItem: NSMenuItem!
    private var nextTrackItem: NSMenuItem!
    private let presetsMenu = NSMenu()
    private let sleepMenu = NSMenu()
    private var sleepItem: NSMenuItem!
    private var sleepTimer: Timer?
    private var sleepEnds: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.moveIfNeeded() {
            NSApp.terminate(nil)
            return
        }
        Preferences.registerDefaults()
        guard let device = Self.lowPowerDevice() ?? MTLCreateSystemDefaultDevice() else {
            NSApp.terminate(nil)
            return
        }
        self.device = device
        surfaces = Preferences.surfaces
        thaws = Preferences.meltSnow
        behindWindows = Preferences.behindWindows
        snowfallHeld = !Preferences.welcomed
        syncScreens()
        guard !screens.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        statusItem = makeStatusItem()
        updateStatusIcon()
        refreshHalloween()
        halloweenTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshHalloween() }
        observeSystem()
        ambience.volume = Float(Preferences.soundVolume)
        ambience.musicVolume = Float(Preferences.musicVolume)
        ambience.musicFolder = Preferences.musicFolder
        ambience.on = Preferences.sound
        updateSound()
        Marquee.enabled = Preferences.deepInteraction
        screenshots.stepAside = { [weak self] aside in self?.screens.forEach { $0.stepAside(aside) } }
        screenshots.start()
        if snowfallHeld {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showWelcome() }
        }
    }

    // A menu bar app has no Dock icon to badge, so update reminders are left to Sparkle's own gentle alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    // MARK: - Displays

    /// One overlay per display: new displays get snow, removed ones lose theirs, the rest follow resolution changes.
    private func syncScreens() {
        let current = NSScreen.screens
        displays.update(screens: current)
        let ids = Set(current.compactMap(\.displayID))
        for gone in screens where !ids.contains(gone.displayID) { gone.close() }
        screens.removeAll { !ids.contains($0.displayID) }

        for screen in current {
            if let existing = screens.first(where: { $0.displayID == screen.displayID }) {
                existing.fit(to: screen)
            } else if let snow = ScreenSnow(screen: screen, device: device, displays: displays, surfaces: { [unowned self] in surfaces }) {
                snow.simulation.snowfallHeld = snowfallHeld
                snow.simulation.snowfallReleased = { [weak self] in self?.releaseSnowfall() }
                snow.halloween = halloween
                snow.modes = Preferences.modes
                snow.maxFrameRate = Preferences.maxPerformance
                snow.activityChanged = { [weak self] in self?.updateActivity() }
                snow.apply(power.budget)
                screens.append(snow)
            }
        }
        displays.snows = screens
        updateActivity()
    }

    private func releaseSnowfall() {
        snowfallHeld = false
        for snow in screens { snow.simulation.snowfallHeld = false }
    }

    private func showWelcome() {
        let welcome = WelcomeController()
        welcome.scatter = { [weak self] pieces in
            guard let self, let first = pieces.first else { return }
            let point = CGPoint(x: CGFloat(first.position.x), y: CGFloat(first.position.y))
            guard let snow = screens.first(where: { $0.window.frame.contains(point) }) ?? screens.first else { return }
            let origin = SIMD2(Float(snow.window.frame.minX), Float(snow.window.frame.minY))
            snow.simulation.scatter(pieces.map { piece in
                var local = piece
                local.position -= origin
                return local
            })
        }
        welcome.skipped = { [weak self] in self?.releaseSnowfall() }
        welcome.finished = { [weak self] in
            Preferences.welcomed = true
            self?.welcome = nil
        }
        self.welcome = welcome
        welcome.show()
    }

    // MARK: - Menu

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: tr("intensity")))
        intensitySlider.changed = { [unowned self] in select(intensity: $0) }
        let intensityItem = NSMenuItem()
        intensityItem.view = intensitySlider
        menu.addItem(intensityItem)
        // Opacity is set once and left, so it folds away like Accumulate, its value on the row.
        opacityItem = menu.addItem(withTitle: tr("opacity"), action: nil, keyEquivalent: "")
        opacityItem.view = opacityRow
        opacityRow.summaryWhileOpen = true
        opacityRow.toggled = { [unowned self] in
            opacityRow.open.toggle()
            opacitySliderItem.isHidden = !opacityRow.open
        }
        opacitySlider.changed = { [unowned self] opacity in
            Preferences.fallingOpacity = opacity
            for snow in screens { snow.simulation.fallingOpacity = Float(opacity) }
            opacityRow.summary = MenuSlider.percent(opacity)
        }
        opacitySliderItem = NSMenuItem()
        opacitySliderItem.view = opacitySlider
        opacitySliderItem.isHidden = true
        menu.addItem(opacitySliderItem)
        accumulateItem = menu.addItem(withTitle: tr("accumulate"), action: nil, keyEquivalent: "")
        accumulateItem.view = accumulateRow
        accumulateRow.toggled = { [unowned self] in
            accumulateRow.open.toggle()
            surfacesItem.isHidden = !accumulateRow.open
            if !accumulateRow.open { accumulateRow.fit(accumulateItem.title, least: surfacePicker.frame.width) }
        }
        surfacesItem = NSMenuItem()
        surfacesItem.view = surfacePicker
        surfacesItem.isHidden = true
        surfacePicker.toggled = { [unowned self] surface in toggle(surface) }
        menu.addItem(surfacesItem)
        let modes = NSMenu()
        modes.autoenablesItems = false
        mixedItem = toggle(tr("mixed"), #selector(toggleMixed), to: modes)
        modes.addItem(.separator())
        modeItems = Mode.allCases.map { mode in
            let item = toggle(tr(mode.key), #selector(chooseMode), to: modes)
            (item.view as? MenuToggle)?.staysOpen = { Preferences.mixed }
            return (item, mode)
        }
        modes.addItem(.separator())
        halloweenItem = add(tr("halloween"), #selector(toggleHalloween), to: modes)
        menu.addItem(withTitle: tr("mode"), action: nil, keyEquivalent: "").submenu = modes
        presetsMenu.autoenablesItems = false
        presetsMenu.delegate = self
        menu.addItem(withTitle: tr("presets"), action: nil, keyEquivalent: "").submenu = presetsMenu
        clearItem = add(tr("clear.snow"), #selector(clearSnow), to: menu)
        menu.addItem(withTitle: tr("sound"), action: nil, keyEquivalent: "").submenu = makeSoundMenu()
        menu.addItem(.separator())
        let settings = NSMenu()
        settings.autoenablesItems = false
        settings.addItem(.sectionHeader(title: tr("behavior")))
        meltItem = toggle(tr("melt.snow"), #selector(toggleMeltSnow), to: settings)
        deepInteractionItem = toggle(tr("deep"), #selector(toggleDeepInteraction), to: settings)
        settings.addItem(.separator())
        settings.addItem(.sectionHeader(title: tr("display")))
        behindWindowsItem = toggle(tr("behind"), #selector(toggleBehindWindows), to: settings)
        fullScreenItem = toggle(tr("full_screen"), #selector(toggleFullScreen), to: settings)
        screenshotsItem = toggle(tr("screenshots"), #selector(toggleScreenshots), to: settings)
        maxPerformanceItem = toggle(tr("performance"), #selector(toggleMaxPerformance), to: settings)
        settings.addItem(.separator())
        settings.addItem(.sectionHeader(title: tr("general")))
        loginItem = toggle(tr("login"), #selector(toggleOpenAtLogin), to: settings)
        menu.addItem(withTitle: tr("settings"), action: nil, keyEquivalent: "").submenu = settings
        menu.addItem(withTitle: tr("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        return item
    }

    private func makeSoundMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        soundItem = toggle(tr("sound.ambient"), #selector(toggleSound), to: menu)
        menu.addItem(.sectionHeader(title: tr("sound.volume")))
        soundSlider.changed = { [unowned self] volume in
            Preferences.soundVolume = volume
            ambience.volume = Float(volume)
        }
        let soundSliderItem = NSMenuItem()
        soundSliderItem.view = soundSlider
        menu.addItem(soundSliderItem)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: tr("sound.music")))
        musicChooseItem = add(tr("sound.music.choose"), #selector(chooseMusicFolder), to: menu)
        musicSlider.changed = { [unowned self] volume in
            Preferences.musicVolume = volume
            ambience.musicVolume = Float(volume)
        }
        musicSliderItem = NSMenuItem()
        musicSliderItem.view = musicSlider
        menu.addItem(musicSliderItem)
        trackItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        trackItem.isEnabled = false
        nextTrackItem = add(tr("sound.music.next"), #selector(nextTrack), to: menu)
        musicStopItem = add(tr("sound.music.stop"), #selector(stopMusic), to: menu)
        ambience.trackChanged = { [weak self] in self?.refreshTrack() }
        menu.addItem(.separator())
        sleepMenu.autoenablesItems = false
        sleepMenu.delegate = self
        sleepItem = menu.addItem(withTitle: tr("sleep"), action: nil, keyEquivalent: "")
        sleepItem.submenu = sleepMenu
        add(tr("sound.custom"), #selector(openCustomSounds), to: menu)
        add(tr("sound.credits"), #selector(openSoundCredits), to: menu)
        return menu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let toggle = MenuToggle(action: action, target: self)
        toggle.fit(title)
        item.view = toggle
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === presetsMenu { return fillPresets() }
        if menu === sleepMenu { return fillSleep() }
        intensitySlider.value = Preferences.intensity
        opacitySlider.value = Preferences.fallingOpacity
        opacityRow.summary = MenuSlider.percent(Preferences.fallingOpacity)
        opacityRow.fit(opacityItem.title, least: 0)
        let modes = Mode.allCases.filter(Preferences.modes.contains)
        mixedItem.state = Preferences.mixed ? .on : .off
        for (item, mode) in modeItems { item.state = modes.contains(mode) ? .on : .off }
        // Rain neither heaps up nor lies about to clear away.
        let heaps = modes.filter { $0 != .rain }
        meltItem.isHidden = heaps.isEmpty
        clearItem.isHidden = heaps.isEmpty
        meltItem.title = tr(heaps.contains(.snow) ? "melt.snow" : heaps == [.blossom] ? "melt.blossom" : "melt.autumn")
        clearItem.title = tr("clear", heaps)
        (meltItem.view as? MenuToggle)?.fit(meltItem.title)
        // Top to bottom, as they lie on the screen. Rain splashes on the ground whatever it says.
        let choices: [Surfaces] = [.widgets, .windows, .dock] + (heaps.isEmpty ? [] : [.ground])
        if surfacePicker.choices != choices { surfacePicker.choices = choices }
        surfacePicker.on = surfaces
        let lit = choices.filter(surfaces.contains)
        let every = lit.count == choices.count
        accumulateRow.summary = every ? tr("all") : lit.isEmpty ? tr("off") : ""
        accumulateRow.summaryIcons = every || lit.isEmpty ? [] : lit
        // Unfolded, the summary isn't shown: the menu keeps its width while the icons are switched.
        if !accumulateRow.open { accumulateRow.fit(accumulateItem.title, least: surfacePicker.frame.width) }
        meltItem.state = thaws ? .on : .off
        meltItem.isEnabled = !surfaces.isEmpty
        deepInteractionItem.state = Preferences.deepInteraction ? .on : .off
        deepInteractionItem.isEnabled = surfaces.contains(.windows)
        clearItem.isEnabled = screens.contains { $0.simulation.hasSnow || $0.simulation.spriteCount > 0 }
        halloweenItem.state = Halloween.isWanted ? .on : .off
        halloweenItem.isEnabled = modes == [.snow]
        maxPerformanceItem.state = Preferences.maxPerformance ? .on : .off
        behindWindowsItem.state = behindWindows ? .on : .off
        fullScreenItem.state = Preferences.showOverFullScreen ? .on : .off
        fullScreenItem.isEnabled = !behindWindows
        screenshotsItem.state = Preferences.showInScreenshots ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        soundItem.state = Preferences.sound ? .on : .off
        soundSlider.value = Preferences.soundVolume
        musicSlider.value = Preferences.musicVolume
        let folder = Preferences.musicFolder
        musicChooseItem.title = folder.map { "\(tr("sound.music.folder")) \($0.lastPathComponent)" } ?? tr("sound.music.choose")
        musicSliderItem.isHidden = folder == nil
        musicStopItem.isHidden = folder == nil
        refreshTrack()
        sleepItem.title = sleepEnds.map { "\(tr("sleep")) · \(Self.minutes(until: $0))" } ?? tr("sleep")
    }

    private func select(intensity: Double) {
        Preferences.intensity = intensity
        for snow in screens { snow.simulation.intensity = Float(intensity) }
        updateStatusIcon()
        updateSound()
    }

    private func toggle(_ surface: Surfaces) {
        surfaces.formSymmetricDifference(surface)
        Preferences.surfaces = surfaces
        for snow in screens {
            snow.simulation.accumulates = !surfaces.isEmpty
            snow.simulation.groundSettles = surfaces.contains(.ground)
        }
        if surfaces.isDisjoint(with: .tracked) { screens.forEach { $0.dropWindowSnow() } }
        if let menu = statusItem.menu {
            menuNeedsUpdate(menu)
            menu.items.forEach { $0.view?.needsDisplay = true }
        }
    }

    @objc private func toggleMeltSnow() {
        thaws.toggle()
        Preferences.meltSnow = thaws
        for snow in screens { snow.simulation.thaws = thaws }
    }

    @objc private func toggleDeepInteraction() {
        Preferences.deepInteraction.toggle()
        Marquee.enabled = Preferences.deepInteraction
    }

    @objc private func clearSnow() {
        let direction = screens.first?.simulation.breezeDirection ?? -1
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for snow in screens { snow.simulation.blowAway(direction: direction, calm: calm) }
    }

    @objc private func toggleBehindWindows() {
        behindWindows.toggle()
        Preferences.behindWindows = behindWindows
        for snow in screens { snow.window.behindWindows = behindWindows }
    }

    @objc private func toggleFullScreen() {
        Preferences.showOverFullScreen.toggle()
        for snow in screens { snow.overFullScreen = Preferences.showOverFullScreen }
    }

    @objc private func toggleScreenshots() {
        Preferences.showInScreenshots.toggle()
        for snow in screens {
            snow.window.showsInScreenshots = Preferences.showInScreenshots
            snow.dock.window.showsInScreenshots = Preferences.showInScreenshots
        }
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Snowhush: login item change failed: \(error)")
        }
    }

    /// Mixed, a third mode picked takes the place of the one picked before the other.
    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let mode = modeItems.first(where: { $0.item === sender })?.mode else { return }
        if Preferences.mixed {
            let mix = Preferences.mix
            guard !mix.contains(mode) else { return }
            Preferences.mix = [mix[1], mode]
        } else {
            guard mode != Preferences.mode else { return }
        }
        Preferences.mode = mode
        switchModes()
    }

    /// Mixed, the mode picked last falls along with the one picked before it; unmixed, it falls alone.
    @objc private func toggleMixed() {
        Preferences.mixed.toggle()
        let mode = Preferences.mode
        if Preferences.mixed, !Preferences.mix.contains(mode) {
            Preferences.mix = [Preferences.mix[1], mode]
        } else if Preferences.mixed {
            Preferences.mix = [Preferences.mix.first { $0 != mode } ?? .snow, mode]
        }
        switchModes()
    }

    private func switchModes() {
        refreshHalloween()
        updateStatusIcon()
        let direction = screens.first?.simulation.breezeDirection ?? -1
        let calm = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for snow in screens { snow.simulation.switchMode(to: Preferences.modes, direction: direction, calm: calm) }
        updateSound()
    }

    @objc private func toggleMaxPerformance() {
        Preferences.maxPerformance.toggle()
        for snow in screens { snow.maxFrameRate = Preferences.maxPerformance }
    }

    @objc private func toggleHalloween() {
        Halloween.toggle()
        refreshHalloween()
    }

    private func updateStatusIcon() {
        statusItem.button?.image = Self.icon(halloween: halloween, dimmed: Preferences.intensity <= 0)
    }

    private static let symbol: [Mode: String] = [.snow: "snowflake", .autumn: "leaf", .rain: "cloud.rain"]

    /// The integrated GPU on a Mac with two: asking for the default device would wake the discrete one and hold it
    /// awake for as long as the snow falls. The devices left unused are let go before the discrete GPU powers up.
    private static func lowPowerDevice() -> MTLDevice? {
        autoreleasepool { MTLCopyAllDevices().first { $0.isLowPower } }
    }

    private static func icon(halloween: Bool, dimmed: Bool) -> NSImage? {
        let image = halloween ? Halloween.icon : Preferences.mode == .blossom ? Blossom.icon
            : NSImage(systemSymbolName: Self.symbol[Preferences.mode] ?? "snowflake", accessibilityDescription: "Snowhush")
        guard dimmed, let image else { return image }
        // Dimmed by hand: the button's appearsDisabled also disables the slider in its menu, so Off could not be left.
        let faded = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        faded.isTemplate = image.isTemplate
        faded.accessibilityDescription = image.accessibilityDescription
        return faded
    }

    private func refreshHalloween() {
        guard Halloween.isOn != halloween else { return }
        halloween.toggle()
        updateStatusIcon()
        for snow in screens { snow.halloween = halloween }
        updateSound()
    }

    // MARK: - System

    private func observeSystem() {
        power.changed = { [unowned self] in screens.forEach { $0.apply(power.budget) } }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        observe(.default, NSWindow.didChangeOcclusionStateNotification) { _ in }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.syncScreens() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.screens.forEach { $0.spaceChanged() } }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.screens.forEach { $0.watchWindows() } }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        _ change: @escaping (AppDelegate) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            self.updateActivity()
        })
    }

    private func updateActivity() {
        let awake = !screensAsleep && !screenLocked && !sessionInactive
        for snow in screens {
            snow.occlusionChanged()
            snow.setActive(awake && !snow.givesWay && (snow.window.occlusionState.contains(.visible) || snow.fading), asleep: !awake)
        }
        updateSound()
    }

    // MARK: - Presets

    private func fillPresets() {
        presetsMenu.removeAllItems()
        let modes = Preferences.modes, intensity = Preferences.intensity, volume = Preferences.soundVolume, sound = Preferences.sound
        func item(_ preset: Preset, _ tag: Int) {
            let item = add(preset.name, #selector(applyPreset), to: presetsMenu)
            item.tag = tag
            item.state = preset.matches(modes: modes, intensity: intensity, volume: volume, sound: sound) ? .on : .off
        }
        for (index, entry) in Preset.builtIn.enumerated() { item(entry.preset, index) }
        let own = Preferences.presets
        if !own.isEmpty {
            presetsMenu.addItem(.separator())
            for (index, preset) in own.enumerated() {
                item(preset, 1000 + index)
                // Held Option turns each of the person's presets into its removal, as Finder's menus do.
                let remove = add(String(format: tr("preset.delete"), preset.name), #selector(deletePreset), to: presetsMenu)
                remove.tag = 1000 + index
                remove.keyEquivalentModifierMask = .option
                remove.isAlternate = true
            }
        }
        presetsMenu.addItem(.separator())
        add(tr("preset.save"), #selector(savePreset), to: presetsMenu)
    }

    private func preset(tagged tag: Int) -> Preset? {
        tag >= 1000 ? Preferences.presets[safe: tag - 1000] : Preset.builtIn[safe: tag]?.preset
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = preset(tagged: sender.tag), !preset.modes.isEmpty else { return }
        Preferences.mixed = preset.modes.count > 1
        if Preferences.mixed { Preferences.mix = Array(preset.modes.prefix(2)) }
        Preferences.mode = preset.modes.last!
        switchModes()
        select(intensity: preset.intensity)
        Preferences.soundVolume = preset.volume
        ambience.volume = Float(preset.volume)
        if !Preferences.sound { toggleSound() }
    }

    @objc private func savePreset() {
        let alert = NSAlert()
        alert.messageText = tr("preset.save.title")
        alert.informativeText = tr("preset.save.prompt")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = tr("preset.name")
        alert.accessoryView = field
        alert.addButton(withTitle: tr("save"))
        alert.addButton(withTitle: tr("cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = Preset(name: name, modes: Preferences.modes, intensity: Preferences.intensity, volume: Preferences.soundVolume)
        var own = Preferences.presets.filter { $0.name != name }
        own.append(preset)
        Preferences.presets = own
    }

    @objc private func deletePreset(_ sender: NSMenuItem) {
        var own = Preferences.presets
        guard own.indices.contains(sender.tag - 1000) else { return }
        own.remove(at: sender.tag - 1000)
        Preferences.presets = own
    }

    // MARK: - Sleep timer

    private static let sleepChoices: [TimeInterval] = [15, 30, 60, 90, 120].map { $0 * 60 }

    private func fillSleep() {
        sleepMenu.removeAllItems()
        let off = add(tr("sleep.off"), #selector(chooseSleep), to: sleepMenu)
        off.tag = 0
        off.state = sleepEnds == nil ? .on : .off
        sleepMenu.addItem(.separator())
        let format = DateComponentsFormatter()
        format.allowedUnits = [.hour, .minute]
        format.unitsStyle = .short
        for seconds in Self.sleepChoices {
            let item = add(format.string(from: seconds) ?? "", #selector(chooseSleep), to: sleepMenu)
            item.tag = Int(seconds)
        }
        if let ends = sleepEnds {
            sleepMenu.addItem(.separator())
            let left = sleepMenu.addItem(withTitle: String(format: tr("sleep.left"), Self.minutes(until: ends)), action: nil, keyEquivalent: "")
            left.isEnabled = false
        }
    }

    private static func minutes(until date: Date) -> String {
        let format = DateComponentsFormatter()
        format.allowedUnits = [.hour, .minute]
        format.unitsStyle = .short
        return format.string(from: max(60, date.timeIntervalSinceNow.rounded(.up))) ?? ""
    }

    private func cancelSleep() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEnds = nil
    }

    @objc private func chooseSleep(_ sender: NSMenuItem) {
        cancelSleep()
        guard sender.tag > 0 else { return }
        if !Preferences.sound { toggleSound() }
        let seconds = TimeInterval(sender.tag)
        sleepEnds = Date().addingTimeInterval(seconds)
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.fallAsleep() }
        timer.tolerance = 5
        // Common modes, so it still ends on time while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    /// The sound, music too, fades out over half a minute and stays off; the snow keeps falling.
    private func fallAsleep() {
        sleepTimer = nil
        sleepEnds = nil
        guard Preferences.sound else { return }
        Preferences.sound = false
        ambience.fadeOut(over: 30)
        updateSound()
    }

    // MARK: - Sound

    /// Heard while the snow can be seen somewhere: not with the screens asleep or locked, nor while full-screen apps
    /// cover every display it falls on.
    private func updateSound() {
        guard ambience.on else { return ambience.update(modes: [], halloween: false, intensity: 0, audible: false) }
        let awake = !screensAsleep && !screenLocked && !sessionInactive
        ambience.update(
            modes: Preferences.modes,
            halloween: halloween,
            intensity: Preferences.intensity,
            audible: awake && screens.contains { !$0.givesWay }
        )
    }

    @objc private func toggleSound() {
        Preferences.sound.toggle()
        if !Preferences.sound { cancelSleep() }
        ambience.on = Preferences.sound
        updateSound()
    }

    @objc private func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Preferences.musicFolder ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.message = tr("sound.music.prompt")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard MusicPlayer.hasMusic(in: folder) else {
            let alert = NSAlert()
            alert.messageText = tr("sound.music.empty")
            alert.informativeText = folder.lastPathComponent
            alert.runModal()
            return
        }
        Preferences.musicFolder = folder
        ambience.musicFolder = folder
        if !Preferences.sound { toggleSound() }
    }

    /// The track playing, by its file name, under the folder; hidden with no music.
    private func refreshTrack() {
        guard let trackItem else { return }
        let track = ambience.track
        trackItem.title = track.map { "♪ " + $0.deletingPathExtension().lastPathComponent } ?? ""
        trackItem.isHidden = track == nil
        nextTrackItem.isHidden = track == nil
    }

    @objc private func nextTrack() {
        ambience.skipTrack()
    }

    @objc private func stopMusic() {
        Preferences.musicFolder = nil
        ambience.musicFolder = nil
    }

    @objc private func openCustomSounds() {
        NSWorkspace.shared.open(Ambience.prepareCustomFolder())
    }

    @objc private func openSoundCredits() {
        guard let credits = Bundle.main.url(forResource: "CREDITS", withExtension: "txt", subdirectory: "Sounds") else { return }
        NSWorkspace.shared.open(credits)
    }
}
