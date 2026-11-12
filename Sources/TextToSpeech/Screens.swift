// The window, in the Cleaner frame (15-app-mac.md): the logotype, the menu in two groups and
// the Accessibility line in the sidebar; one page per item. The panes are the Tauri build's.
import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case shortcut, voice, player, system
    var id: String { rawValue }
    var title: String { L("nav.\(rawValue)") }
    var subtitle: String { L("sub.\(rawValue)") }
    var icon: String {
        switch self {
        case .shortcut: return "keyboard"
        case .voice: return "volume"
        case .player: return "layout-navbar"
        case .system: return "settings"
        }
    }
    static let groups: [(String, [Pane])] = [("nav.reading", [.shortcut, .voice]), ("nav.settings", [.player, .system])]
}

@MainActor
final class Navigation: ObservableObject {
    @Published var pane: Pane = .shortcut
    /// Bumped every second while the window is open, so the Accessibility line follows the system.
    @Published var tick = 0
}

struct AppView: View {
    @ObservedObject var nav: Navigation
    @ObservedObject var settings: AppSettings
    var shortcutsPaused: (Bool) -> Void
    var tryPlayer: () -> Void
    var testVoice: () -> Void

    var body: some View {
        MacShellView {
            MacSidebar(app: "Text to Speech") {
                ForEach(Pane.groups, id: \.0) { group in
                    MacSidebarGroup(title: L(group.0)) {
                        ForEach(group.1) { pane in
                            MacSidebarItem(icon: pane.icon, title: pane.title, active: nav.pane == pane) { nav.pane = pane }
                        }
                    }
                }
            } status: {
                let _ = nav.tick
                MacStatusLine(on: AXIsProcessTrusted(), onText: L("status.axOn"), offText: L("status.axOff")) {
                    Accessibility.request()
                }
            }
        } content: {
            MacPage {
                MacPageHeader(crumb: "Text to Speech", title: nav.pane.title, subtitle: nav.pane.subtitle)
                switch nav.pane {
                case .shortcut: shortcut
                case .voice: voice
                case .player: player
                case .system: SystemRows()
                }
            }
        }
    }

    private var shortcut: some View {
        SettingRows {
            SettingRow(title: L("shortcut.read"), hint: L("shortcut.read.hint")) {
                KeyRecorder(shortcut: settings.speakShortcut, onPause: shortcutsPaused) { settings.speakShortcut = $0 }
            }
            SettingRow(title: L("shortcut.stop"), hint: L("shortcut.stop.hint")) { Caps(shortcut: Shortcut(keyCode: 53, modifiers: [])) }
            SettingRow(title: L("shortcut.player"), hint: L("shortcut.player.hint")) {
                HStack(spacing: 4) {
                    Caps(shortcut: Shortcut(keyCode: 49, modifiers: []))
                    Caps(shortcut: Shortcut(keyCode: 123, modifiers: []))
                    Caps(shortcut: Shortcut(keyCode: 124, modifiers: []))
                }
            }
        }
    }

    private var voice: some View { VoicePane(settings: settings, testVoice: testVoice) }

    private var player: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRows {
                SettingRow(title: L("player.position")) {
                    ZenSelect(value: settings.position.title, choices: PlayerPosition.allCases.map { ($0.rawValue, $0.title) },
                              selected: settings.position.rawValue) { settings.position = PlayerPosition(rawValue: $0) ?? .center }
                }
                .zIndex(6)
                SettingRow(title: L("player.size")) {
                    ZenSelect(value: settings.size.title, choices: PlayerSize.allCases.map { ($0.rawValue, $0.title) },
                              selected: settings.size.rawValue) { settings.size = PlayerSize(rawValue: $0) ?? .standard }
                }
                .zIndex(5)
            }
            Button(L("player.try"), action: tryPlayer).buttonStyle(ZenButtonStyle(kind: .secondary)).padding(.top, 24)
        }
    }
}

/// The voice: which one reads, the person's key for it, the steps to get that key, and a test.
private struct VoicePane: View {
    @ObservedObject var settings: AppSettings
    var testVoice: () -> Void
    /// Bumped when a key is saved or removed, so the row below reads the keychain again.
    @State private var saved = 0

    private var engine: VoiceEngine { settings.engine }

    var body: some View {
        let _ = saved
        VStack(alignment: .leading, spacing: 0) {
            SettingRows {
                SettingRow(title: L("voice.choice"), hint: L("voice.choice.hint")) {
                    ZenSelect(value: engine.title, choices: VoiceEngine.allCases.map { ($0.rawValue, $0.title) },
                              selected: engine.rawValue, width: 280) { settings.engine = VoiceEngine(rawValue: $0) ?? .fish }
                }
                .zIndex(6)
                SettingRow(title: L("\(engine.rawValue).key"),
                           hint: engine.secret.hint.map { L("key.saved") + " " + $0 } ?? L("key.none")) {
                    HStack(spacing: 8) {
                        ZenTextField(placeholder: L("\(engine.rawValue).key.placeholder"), value: "", width: 240) { value in
                            engine.secret.save(value)
                            saved += 1
                        }
                        if engine.secret.value != nil {
                            Button(L("key.remove")) { engine.secret.save(""); saved += 1 }
                                .buttonStyle(ZenButtonStyle(kind: .secondary))
                        }
                    }
                }
                SettingRow(title: L("voice.speed"), hint: L("voice.speed.hint")) {
                    ZenSelect(value: PlayerView.speedText(settings.speed),
                              choices: AppSettings.speeds.map { (String($0), PlayerView.speedText($0)) },
                              selected: String(settings.speed), width: 160) { settings.speed = Double($0) ?? 1 }
                }
                .zIndex(5)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("\(engine.rawValue).steps.title")).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    Text("\(i + 1). \(step)").font(Zen.font(13, .medium)).foregroundStyle(Zen.gray7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Button(link.0) { NSWorkspace.shared.open(link.1) }.buttonStyle(ZenButtonStyle(kind: .secondary))
                    }
                    Button(L("voice.test"), action: testVoice).buttonStyle(ZenButtonStyle(kind: .primary))
                        .disabled(engine.secret.value == nil)
                }
                .padding(.top, 6)
                Text(L("\(engine.rawValue).note")).font(Zen.font(12, .medium)).foregroundStyle(Zen.gray5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
        }
    }

    private var steps: [String] { (1...4).compactMap { n in
        let key = "\(engine.rawValue).step\(n)"
        let text = L(key)
        return text == key ? nil : text
    } }

    private var links: [(String, URL)] {
        switch engine {
        case .fish: return [(L("fish.openKeys"), Fish.keysPage)]
        case .phonon: return [(L("phonon.openModel"), Phonon.modelPage), (L("phonon.openTokens"), Phonon.tokensPage)]
        }
    }
}

private struct SystemRows: View {
    @State private var isLoginItem = SMAppService.mainApp.status == .enabled
    var body: some View {
        SettingRows {
            SettingRow(title: L("system.login"), hint: L("system.login.hint")) {
                ZenSwitch(isOn: isLoginItem) { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { NSLog("[login-item] \(error)") }
                    isLoginItem = SMAppService.mainApp.status == .enabled
                }
            }
        }
    }
}

enum Accessibility {
    /// Puts the app in the Accessibility list (the system's prompt) and opens it, so the person only turns it on.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
