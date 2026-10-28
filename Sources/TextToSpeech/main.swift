// Text to Speech for macOS: the letter T in the menu bar, the floating player, and one window in
// the Cleaner frame. Select text in any app, press the shortcut, and Rafael reads it aloud.
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let nav = Navigation()
    private let hotKeys = HotKeys()
    private let player = PlayerController()
    private var session: ReadingSession?
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var windowTimer: Timer?
    private var glyphTimer: Timer?
    private var ringFrame = 0
    private var areShortcutsPaused = false
    private var busy = false

    private enum HotKey: UInt32 { case speak = 1, escape = 2 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let id = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            DistributedNotificationCenter.default().postNotificationName(.init("\(id).open"), object: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("\(id).open"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openWindow(nil) }
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        Zen.registerFonts()

        settings.onShortcutChange = { [weak self] in self?.registerShortcuts() }
        player.onKey = { [weak self] code, mods in self?.handleKey(code, mods) ?? false }
        setUpMenuBar()
        registerShortcuts()
        E2E.watch { [weak self] command in self?.run(command) }
        if !AXIsProcessTrusted() && !E2E.isOn { openWindow(.shortcut) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow(nil)
        return true
    }

    // MARK: - Shortcuts

    private func registerShortcuts() {
        hotKeys.unregister(id: HotKey.speak.rawValue)
        guard !areShortcutsPaused, !E2E.isOn, let s = settings.speakShortcut else { return }
        hotKeys.register(id: HotKey.speak.rawValue, shortcut: s) { [weak self] isDown in if isDown { self?.speakSelection() } }
    }

    /// Esc is held only while the player is open, so it is not taken from other apps the rest of the time.
    private func setEscape(_ on: Bool) {
        if on, !E2E.isOn {
            hotKeys.register(id: HotKey.escape.rawValue, shortcut: Shortcut(keyCode: UInt32(kVK_Escape), modifiers: [])) { [weak self] isDown in
                if isDown { self?.stop() }
            }
        } else {
            hotKeys.unregister(id: HotKey.escape.rawValue)
        }
    }

    private func handleKey(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let session, session.isLive else { return false }
        if !modifiers.intersection([.command, .control, .option]).isEmpty { return false }
        switch Int(keyCode) {
        case kVK_Escape: stop()
        case kVK_Space: session.togglePause()
        case kVK_LeftArrow: session.jump(-1)
        case kVK_RightArrow: session.jump(1)
        case kVK_ANSI_Minus: changeSpeed(-0.25)
        case kVK_ANSI_Equal: changeSpeed(0.25)
        default: return false
        }
        return true
    }

    private func changeSpeed(_ delta: Double) {
        let speed = max(0.5, min(2, ((settings.speed + delta) * 4).rounded() / 4))
        guard speed != settings.speed else { return }
        settings.speed = speed
        session?.setSpeed(speed)
    }

    // MARK: - The reading

    private func speakSelection() {
        guard !busy else { return }
        busy = true
        stop()
        Task {
            defer { busy = false }
            // The selection first, while the app the person is in still has the focus.
            switch await Selection.read() {
            case .text(let text): start(text)
            case .nothingSelected: flash(L("player.nothingSelected"))
            case .needsAccessibility:
                flash(L("player.needsAccessibility"))
                openWindow(.shortcut)
            }
        }
    }

    private func start(_ text: String) {
        stop()
        let session = ReadingSession(text: text, speed: settings.speed, server: settings.server)
        guard !session.parts.isEmpty else { flash(L("player.nothingSelected")); return }
        self.session = session
        player.show(session, size: settings.size, position: settings.position)
        setEscape(true)
        updateGlyph()
        Task {
            let finished = await session.run()
            guard self.session === session else { return }
            if finished {
                stop()
            } else if session.isLive {
                // A part failed: the message stays a few seconds, then the player goes.
                try? await Task.sleep(for: .seconds(4))
                if self.session === session { stop() }
            }
        }
    }

    /// A message alone in the player ("Nothing selected"), for 1.8 s.
    private func flash(_ message: String) {
        let session = ReadingSession(text: "", speed: settings.speed, server: settings.server)
        session.hint = message
        self.session = session
        player.show(session, size: settings.size, position: settings.position)
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if self.session === session { stop() }
        }
    }

    private func stop() {
        session?.stop()
        session = nil
        player.hide()
        setEscape(false)
        updateGlyph()
    }

    // MARK: - Menu bar

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Text to Speech"
        updateGlyph()
    }

    /// The T never leaves (13-favicon.md): a turning ring while a part is being prepared, a dot
    /// while reading, the T in outline when Accessibility is off.
    private func updateGlyph() {
        glyphTimer?.invalidate()
        glyphTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawGlyph() }
        }
        drawGlyph()
    }

    private var drawn = ""
    private func drawGlyph() {
        let name: String
        if let session, session.isLive, !session.parts.isEmpty {
            if !session.isSounding { ringFrame += 1; name = "menubar-processing-\(ringFrame % 8)" } else { name = "menubar-listening" }
        } else {
            name = AXIsProcessTrusted() ? "menubar" : "menubar-attention"
            if session == nil { glyphTimer?.invalidate(); glyphTimer = nil }
        }
        guard name != drawn, let image = Icon.image(name)?.copy() as? NSImage else { return }
        drawn = name
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let speak = item(L("menu.speak"), #selector(speakFromMenu))
        if let s = settings.speakShortcut { speak.keyEquivalent = s.menuKey; speak.keyEquivalentModifierMask = s.modifiers }
        menu.addItem(speak)
        let stopItem = item(L("menu.stop"), #selector(stopFromMenu))
        stopItem.isEnabled = session != nil
        menu.addItem(stopItem)
        if !AXIsProcessTrusted() { menu.addItem(item(L("menu.allow"), #selector(allowFromMenu))) }
        menu.addItem(.separator())
        menu.addItem(item(L("menu.settings"), #selector(openFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("menu.quit"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        menuItem.isEnabled = true
        return menuItem
    }

    @objc private func speakFromMenu() { speakSelection() }
    @objc private func stopFromMenu() { stop() }
    @objc private func allowFromMenu() { Accessibility.request(); openWindow(.shortcut) }
    @objc private func openFromMenu() { openWindow(nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Window

    private func openWindow(_ pane: Pane?) {
        if let pane { nav.pane = pane }
        if window == nil {
            let root = AppView(nav: nav, settings: settings, shortcutsPaused: { [weak self] paused in
                self?.areShortcutsPaused = paused
                self?.registerShortcuts()
            }, tryPlayer: { [weak self] in self?.start(L("player.sample")) })
            window = MacShell.window(title: "Text to Speech", size: CGSize(width: 1040, height: 720),
                                     minSize: CGSize(width: 960, height: 640), autosave: "TextToSpeechWindow", root: root)
            window?.appearance = NSAppearance(named: .aqua)
        }
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.window?.isVisible == true { self.nav.tick += 1; self.updateGlyph() } else { self.windowTimer?.invalidate() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - End-to-end commands

    private func run(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "speak": start(arg.replacingOccurrences(of: "\\n", with: "\n"))
        case "space": session?.togglePause()
        case "left": session?.jump(-1)
        case "right": session?.jump(1)
        case "faster": changeSpeed(0.25)
        case "slower": changeSpeed(-0.25)
        case "escape": stop()
        case "open":
            openWindow(Pane(rawValue: arg))
            NSLog("[e2e] window %d", window?.windowNumber ?? 0)
        case "state":
            let s = session
            NSLog("[e2e] state live=%@ index=%d parts=%d paused=%@ ready=%@ spoken=%d speed=%.2f hint=%@ player=%d firstSoundMs=%d",
                  (s?.isLive ?? false) ? "yes" : "no", s?.index ?? -1, s?.parts.count ?? 0, (s?.isPaused ?? false) ? "yes" : "no",
                  (s?.isSounding ?? false) ? "yes" : "no", s?.spokenCount ?? 0, s?.speed ?? 0, s?.hint ?? "-", player.windowNumber,
                  Int((s?.firstSoundAt?.timeIntervalSince(s!.startedAt) ?? -0.001) * 1000))
        default: NSLog("[e2e] unknown command: \(command)")
        }
    }
}

/// End-to-end runs drive the app through TTS_E2E_TRIGGER, a file whose lines run its commands
/// ("speak <text>", "space", "left", "right", "faster", "slower", "escape", "state"). Off unless set.
@MainActor
enum E2E {
    static let isOn = ProcessInfo.processInfo.environment["TTS_E2E_TRIGGER"] != nil

    static func watch(_ run: @escaping @MainActor (String) -> Void) {
        guard let path = ProcessInfo.processInfo.environment["TTS_E2E_TRIGGER"] else { return }
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
            MainActor.assumeIsolated { run(command) }
        }
    }
}

// `--reading <file.json>`: the reading logic alone, for scripts/check.sh to compare with the 1.x
// reading.js. In: [{text, spoken: [{text, start}], duration}]; out: [{parts, times}].
if let i = CommandLine.arguments.firstIndex(of: "--reading"), i + 1 < CommandLine.arguments.count,
   let data = FileManager.default.contents(atPath: CommandLine.arguments[i + 1]),
   let cases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
    let out: [[String: Any]] = cases.map { c in
        let text = c["text"] as? String ?? ""
        let spoken = (c["spoken"] as? [[String: Any]] ?? []).map { ($0["text"] as? String ?? "", ($0["start"] as? NSNumber)?.doubleValue ?? 0) }
        let times = Reading.wordTimes(text, spoken: spoken, duration: (c["duration"] as? NSNumber)?.doubleValue ?? 0)
        return ["parts": Reading.split(text), "times": times.map { ["text": $0.text, "start": $0.start] },
                "clock": Reading.clock((c["duration"] as? NSNumber)?.doubleValue ?? 0)]
    }
    FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]))
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
