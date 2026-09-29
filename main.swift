import Cocoa
import AVFoundation
import ApplicationServices
import UniformTypeIdentifiers

private struct CustomSound: Codable {
    let id: String
    let name: String
    let filename: String
}

private struct SoundOption {
    let id: String
    let title: String
    let url: URL
}

private final class AudioPool {
    private var players: [AVAudioPlayer]
    private var nextPlayer = 0

    init(url: URL, volume: Float, count: Int = 10) throws {
        players = try (0..<count).map { _ in
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        }
    }

    @discardableResult func play() -> Bool {
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.currentTime = 0
        return player.play()
    }

    func setVolume(_ volume: Float) {
        for player in players { player.volume = volume }
    }
}

private final class ShotgunKeyboardApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let bundledSounds: [(id: String, title: String, file: String)] = [
        ("shotgun", "Shotgun", "shotgun.wav"),
        ("boing", "Cartoon Boing", "boing.wav"),
        ("beep", "Censor Beep", "beep.wav"),
        ("fart", "Dry Fart", "fart.wav"),
        ("pew", "Pew Pew", "pew.wav"),
        ("quack", "Quack", "quack.wav")
    ]

    private var customSounds: [CustomSound] = []
    private var selectedSoundIDs: [String] = []
    private var multipleSoundsEnabled = false
    private var pools: [String: AudioPool] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var soundsScrollView: NSScrollView?
    private var monitoringLabel: NSTextField?
    private var modeHintLabel: NSTextField?
    private var armedButton: NSButton?
    private var multipleButton: NSButton?
    private var selectAllButton: NSButton?
    private var volumeButton: NSPopUpButton?
    private var statusTimer: Timer?
    private var detectedKeyCount = 0
    private var armed = true
    private var volume: Float = 0.55

    private var soundsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotgunKeyboard", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "armed") != nil { armed = defaults.bool(forKey: "armed") }
        if defaults.object(forKey: "volume") != nil { volume = defaults.float(forKey: "volume") }
        multipleSoundsEnabled = defaults.bool(forKey: "multipleSoundsEnabled")
        if let data = defaults.data(forKey: "customSounds"),
           let saved = try? JSONDecoder().decode([CustomSound].self, from: data) {
            customSounds = saved.filter { FileManager.default.fileExists(atPath: soundsDirectory.appendingPathComponent($0.filename).path) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.toolTip = "ShotgunKeyboard"
        restoreSelection()
        configureDockIcon()
        configureMainMenu()
        configureStatusItem()
        createWindow()
        showWindow(nil)

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        let monitoringStarted = startEventTap()
        NSLog("ShotgunKeyboard startup: Accessibility=\(accessibilityGranted), InputMonitoring=\(CGPreflightListenEventAccess()), EventTap=\(monitoringStarted)")
        refreshMonitoringStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshMonitoringStatus()
        }
        if !monitoringStarted {
            showPermissionAlert(accessibilityGranted: accessibilityGranted)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func allSounds() -> [SoundOption] {
        let bundled = bundledSounds.compactMap { sound -> SoundOption? in
            guard let url = Bundle.main.resourceURL?.appendingPathComponent(sound.file) else { return nil }
            return SoundOption(id: sound.id, title: sound.title, url: url)
        }
        let custom = customSounds.map { sound in
            SoundOption(id: sound.id, title: sound.name, url: soundsDirectory.appendingPathComponent(sound.filename))
        }
        return bundled + custom
    }

    private func prepareSound(_ id: String) -> Bool {
        if pools[id] != nil { return true }
        guard let sound = allSounds().first(where: { $0.id == id }) else { return false }
        do {
            pools[id] = try AudioPool(url: sound.url, volume: volume)
            return true
        } catch {
            showAlert(title: "Sound could not load", message: "\(sound.title): \(error.localizedDescription)")
            return false
        }
    }

    private func restoreSelection() {
        let saved = UserDefaults.standard.stringArray(forKey: "selectedSoundIDs") ?? ["shotgun"]
        selectedSoundIDs = []
        let choices = multipleSoundsEnabled ? saved : Array(saved.reversed())
        for id in choices where !selectedSoundIDs.contains(id) {
            if prepareSound(id) { selectedSoundIDs.append(id) }
            if !multipleSoundsEnabled && !selectedSoundIDs.isEmpty { break }
        }
        if selectedSoundIDs.isEmpty, prepareSound("shotgun") {
            selectedSoundIDs = ["shotgun"]
        }
        saveSelection()
    }

    private func saveSelection() {
        UserDefaults.standard.set(selectedSoundIDs, forKey: "selectedSoundIDs")
    }

    private func saveCustomSounds() {
        if let data = try? JSONEncoder().encode(customSounds) {
            UserDefaults.standard.set(data, forKey: "customSounds")
        }
    }

    private func configureDockIcon() {
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 12, y: 12, width: 232, height: 232),
            xRadius: 52,
            yRadius: 52
        ).fill()
        let symbol = NSAttributedString(
            string: "⌨",
            attributes: [
                .font: NSFont.systemFont(ofSize: 154, weight: .medium),
                .foregroundColor: NSColor.white
            ]
        )
        let symbolSize = symbol.size()
        symbol.draw(at: NSPoint(x: (256 - symbolSize.width) / 2, y: (256 - symbolSize.height) / 2 + 5))
        image.unlockFocus()
        NSApp.applicationIconImage = image
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "ShotgunKeyboard", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let openItem = NSMenuItem(title: "Open ShotgunKeyboard", action: #selector(showWindow(_:)), keyEquivalent: "o")
        openItem.target = self
        appMenu.addItem(openItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit ShotgunKeyboard", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        guard let button = statusItem?.button else { return }
        button.title = armed ? "🔊" : "🔇"
        button.target = self
        button.action = #selector(showWindow(_:))
        button.toolTip = "Open ShotgunKeyboard"
    }

    @objc private func showWindow(_ sender: Any?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshMonitoringStatus()
    }

    private func label(
        _ text: String,
        frame: NSRect,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ShotgunKeyboard"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 640))
        window.contentView = content
        self.window = window

        content.addSubview(label("ShotgunKeyboard", frame: NSRect(x: 28, y: 584, width: 524, height: 36), size: 28, weight: .bold))
        content.addSubview(label("A sound effect for every key press", frame: NSRect(x: 28, y: 559, width: 524, height: 22), size: 13, color: .secondaryLabelColor))

        let statusBox = NSView(frame: NSRect(x: 28, y: 469, width: 524, height: 74))
        statusBox.wantsLayer = true
        statusBox.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statusBox.layer?.cornerRadius = 12
        statusBox.addSubview(label("Keyboard monitoring", frame: NSRect(x: 16, y: 46, width: 380, height: 20), size: 13, weight: .semibold))
        let monitoringLabel = label("Checking permissions…", frame: NSRect(x: 16, y: 13, width: 397, height: 33), size: 12, color: .secondaryLabelColor)
        monitoringLabel.lineBreakMode = .byWordWrapping
        monitoringLabel.maximumNumberOfLines = 2
        statusBox.addSubview(monitoringLabel)
        self.monitoringLabel = monitoringLabel
        let retryButton = NSButton(title: "Retry", target: self, action: #selector(retryMonitoring(_:)))
        retryButton.frame = NSRect(x: 429, y: 20, width: 78, height: 30)
        statusBox.addSubview(retryButton)
        content.addSubview(statusBox)

        let armedButton = NSButton(checkboxWithTitle: "Armed", target: self, action: #selector(toggleArmed(_:)))
        armedButton.frame = NSRect(x: 28, y: 427, width: 150, height: 27)
        armedButton.state = armed ? .on : .off
        content.addSubview(armedButton)
        self.armedButton = armedButton

        let multipleButton = NSButton(checkboxWithTitle: "Multiple sounds", target: self, action: #selector(toggleMultipleSounds(_:)))
        multipleButton.frame = NSRect(x: 205, y: 427, width: 200, height: 27)
        multipleButton.state = multipleSoundsEnabled ? .on : .off
        content.addSubview(multipleButton)
        self.multipleButton = multipleButton

        content.addSubview(label("Sounds", frame: NSRect(x: 28, y: 395, width: 110, height: 26), size: 17, weight: .semibold))
        let modeHintLabel = label("", frame: NSRect(x: 139, y: 396, width: 413, height: 24), size: 12, color: .secondaryLabelColor)
        content.addSubview(modeHintLabel)
        self.modeHintLabel = modeHintLabel

        let scroll = NSScrollView(frame: NSRect(x: 28, y: 145, width: 524, height: 240))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        content.addSubview(scroll)
        soundsScrollView = scroll

        let addButton = NSButton(title: "Add Sounds…", target: self, action: #selector(addSounds(_:)))
        addButton.frame = NSRect(x: 28, y: 101, width: 130, height: 32)
        content.addSubview(addButton)
        let selectAllButton = NSButton(title: "Select All", target: self, action: #selector(selectAllSounds(_:)))
        selectAllButton.frame = NSRect(x: 165, y: 101, width: 108, height: 32)
        selectAllButton.isEnabled = multipleSoundsEnabled
        content.addSubview(selectAllButton)
        self.selectAllButton = selectAllButton

        content.addSubview(label("Volume", frame: NSRect(x: 28, y: 59, width: 75, height: 24), size: 13))
        let volumeButton = NSPopUpButton(frame: NSRect(x: 105, y: 54, width: 150, height: 32))
        volumeButton.addItems(withTitles: ["Loud", "Medium", "Quiet"])
        volumeButton.selectItem(at: volume > 0.75 ? 0 : (volume > 0.35 ? 1 : 2))
        volumeButton.target = self
        volumeButton.action = #selector(setVolume(_:))
        content.addSubview(volumeButton)
        self.volumeButton = volumeButton

        let testButton = NSButton(title: "Test Selected Sound", target: self, action: #selector(testSelectedSound(_:)))
        testButton.frame = NSRect(x: 363, y: 54, width: 189, height: 32)
        content.addSubview(testButton)
        content.addSubview(label(
            "Close this window to keep sounds active. Click 🔊 to reopen it.",
            frame: NSRect(x: 28, y: 19, width: 524, height: 20),
            size: 11,
            color: .secondaryLabelColor
        ))
        rebuildSoundRows()
    }

    private func rebuildSoundRows() {
        guard let scroll = soundsScrollView else { return }
        let sounds = allSounds()
        let rowHeight: CGFloat = 34
        let height = max(CGFloat(240), CGFloat(sounds.count) * rowHeight + 12)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: height))
        for (index, sound) in sounds.enumerated() {
            let button = multipleSoundsEnabled
                ? NSButton(checkboxWithTitle: sound.title, target: self, action: #selector(toggleSound(_:)))
                : NSButton(radioButtonWithTitle: sound.title, target: self, action: #selector(toggleSound(_:)))
            let y = height - CGFloat(index + 1) * rowHeight - 2
            let isCustom = customSounds.contains { $0.id == sound.id }
            button.frame = NSRect(x: 12, y: y, width: isCustom ? 396 : 474, height: 30)
            button.identifier = NSUserInterfaceItemIdentifier(sound.id)
            button.state = selectedSoundIDs.contains(sound.id) ? .on : .off
            document.addSubview(button)
            if isCustom {
                let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeCustomSound(_:)))
                removeButton.frame = NSRect(x: 416, y: y + 1, width: 72, height: 28)
                removeButton.identifier = NSUserInterfaceItemIdentifier(sound.id)
                document.addSubview(removeButton)
            }
        }
        scroll.documentView = document
        modeHintLabel?.stringValue = multipleSoundsEnabled
            ? "Checked sounds play at random"
            : "Choose one sound"
        selectAllButton?.isEnabled = multipleSoundsEnabled
        multipleButton?.state = multipleSoundsEnabled ? .on : .off
        armedButton?.state = armed ? .on : .off
    }

    private func refreshMonitoringStatus() {
        if !CGPreflightListenEventAccess() && !AXIsProcessTrusted() {
            monitoringLabel?.stringValue = "Enable Input Monitoring and Accessibility in System Settings → Privacy & Security."
        } else if !CGPreflightListenEventAccess() {
            monitoringLabel?.stringValue = "Enable Input Monitoring in System Settings → Privacy & Security."
        } else if !AXIsProcessTrusted() {
            monitoringLabel?.stringValue = "Enable Accessibility in System Settings → Privacy & Security."
        } else if let tap = eventTap, CGEvent.tapIsEnabled(tap: tap) {
            monitoringLabel?.stringValue = "Listening · \(detectedKeyCount) keys detected"
        } else {
            monitoringLabel?.stringValue = "Monitoring stopped. Click Retry."
        }
    }

    private func startEventTap() -> Bool {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return true }
        }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyboardEventCallback,
            userInfo: context
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    fileprivate func handleKeyDown() {
        detectedKeyCount += 1
        if detectedKeyCount == 1 { NSLog("ShotgunKeyboard detected its first keyDown") }
        guard armed, let id = selectedSoundIDs.randomElement() else { return }
        pools[id]?.play()
    }

    fileprivate func reenableEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    @objc private func toggleArmed(_ sender: NSButton) {
        armed = sender.state == .on
        UserDefaults.standard.set(armed, forKey: "armed")
        statusItem?.button?.title = armed ? "🔊" : "🔇"
    }

    @objc private func toggleSound(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if !multipleSoundsEnabled {
            if prepareSound(id) { selectedSoundIDs = [id] }
        } else if selectedSoundIDs.contains(id) {
            if selectedSoundIDs.count > 1 { selectedSoundIDs.removeAll { $0 == id } }
        } else if prepareSound(id) {
            selectedSoundIDs.append(id)
        }
        saveSelection()
        rebuildSoundRows()
    }

    @objc private func toggleMultipleSounds(_ sender: NSButton) {
        multipleSoundsEnabled = sender.state == .on
        UserDefaults.standard.set(multipleSoundsEnabled, forKey: "multipleSoundsEnabled")
        if !multipleSoundsEnabled, let last = selectedSoundIDs.last {
            selectedSoundIDs = [last]
            saveSelection()
        }
        rebuildSoundRows()
    }

    @objc private func selectAllSounds(_ sender: NSButton) {
        guard multipleSoundsEnabled else { return }
        selectedSoundIDs = allSounds().map(\.id).filter { prepareSound($0) }
        saveSelection()
        rebuildSoundRows()
    }

    @objc private func addSounds(_ sender: NSButton) {
        DispatchQueue.main.async { self.presentAddSoundsPanel() }
    }

    private func presentAddSoundsPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add sounds to ShotgunKeyboard"
        panel.message = "Choose one or more audio files. The app keeps its own copies."
        panel.prompt = "Add"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        var addedIDs: [String] = []
        var failures: [String] = []
        for url in panel.urls {
            do {
                let id = UUID().uuidString
                let filename = id + "." + url.pathExtension.lowercased()
                try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
                let destination = soundsDirectory.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: url, to: destination)
                do {
                    pools[id] = try AudioPool(url: destination, volume: volume)
                    customSounds.append(CustomSound(id: id, name: url.deletingPathExtension().lastPathComponent, filename: filename))
                    addedIDs.append(id)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !addedIDs.isEmpty {
            selectedSoundIDs = multipleSoundsEnabled ? addedIDs : [addedIDs[addedIDs.count - 1]]
            saveCustomSounds()
            saveSelection()
            rebuildSoundRows()
        }
        if !failures.isEmpty {
            showAlert(title: "Some sounds could not be added", message: failures.joined(separator: "\n"))
        }
    }

    @objc private func removeCustomSound(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let sound = customSounds.first(where: { $0.id == id }) else { return }
        do {
            try FileManager.default.removeItem(at: soundsDirectory.appendingPathComponent(sound.filename))
        } catch {
            showAlert(title: "Sound could not be removed", message: error.localizedDescription)
            return
        }
        customSounds.removeAll { $0.id == id }
        selectedSoundIDs.removeAll { $0 == id }
        pools.removeValue(forKey: id)
        if selectedSoundIDs.isEmpty, prepareSound("shotgun") { selectedSoundIDs = ["shotgun"] }
        saveCustomSounds()
        saveSelection()
        rebuildSoundRows()
    }

    @objc private func setVolume(_ sender: NSPopUpButton) {
        let levels: [Float] = [1.0, 0.55, 0.2]
        guard levels.indices.contains(sender.indexOfSelectedItem) else { return }
        volume = levels[sender.indexOfSelectedItem]
        UserDefaults.standard.set(volume, forKey: "volume")
        for pool in pools.values { pool.setVolume(volume) }
    }

    @objc private func testSelectedSound(_ sender: NSButton) {
        guard let id = selectedSoundIDs.randomElement() else {
            showAlert(title: "No sound selected", message: "Choose a sound first.")
            return
        }
        if !prepareSound(id) || pools[id]?.play() != true {
            showAlert(title: "Sound could not play", message: "Check your Mac's output device and volume, then try another sound.")
        }
    }

    @objc private func retryMonitoring(_ sender: NSButton) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !startEventTap() { showPermissionAlert(accessibilityGranted: accessibilityGranted) }
        refreshMonitoringStatus()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func showPermissionAlert(accessibilityGranted: Bool) {
        let accessibilityInstruction = accessibilityGranted
            ? "Accessibility appears enabled."
            : "Enable ShotgunKeyboard in System Settings > Privacy & Security > Accessibility."
        let inputInstruction = CGPreflightListenEventAccess()
            ? "Input Monitoring appears enabled."
            : "Enable ShotgunKeyboard in System Settings > Privacy & Security > Input Monitoring."
        showAlert(
            title: "Keyboard monitoring is unavailable",
            message: "\(accessibilityInstruction) \(inputInstruction) Quit and reopen the app after changing either toggle."
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private func keyboardEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let app = Unmanaged<ShotgunKeyboardApp>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .keyDown:
        app.handleKeyDown()
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        app.reenableEventTap()
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

private let app = NSApplication.shared
private let delegate = ShotgunKeyboardApp()
app.delegate = delegate
app.run()
