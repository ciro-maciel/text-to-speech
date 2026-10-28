// The settings, in UserDefaults. On the first launch the Tauri build's config.json (same bundle
// identifier, same folder) is read once, so moving from 1.x keeps the shortcut, the speed and
// the player as they were.
import AppKit
import Carbon.HIToolbox
import Foundation

/// The nine places the player can sit, 24 points from the edge of the display with the cursor.
enum PlayerPosition: String, CaseIterable {
    case topLeft = "top-left", topCenter = "top-center", topRight = "top-right"
    case middleLeft = "middle-left", center, middleRight = "middle-right"
    case bottomLeft = "bottom-left", bottomCenter = "bottom-center", bottomRight = "bottom-right"

    var title: String { L("position.\(rawValue)") }
}

enum PlayerSize: String, CaseIterable {
    case compact, standard, spacious
    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 320, height: 200)
        case .standard: return CGSize(width: 380, height: 240)
        case .spacious: return CGSize(width: 460, height: 280)
        }
    }
    var title: String { L("size.\(rawValue)") }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var speakShortcut: Shortcut? { didSet { saveShortcut(speakShortcut); onShortcutChange() } }
    /// 0.5 to 2, in steps of 0.25.
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var position: PlayerPosition { didSet { defaults.set(position.rawValue, forKey: "playerPosition") } }
    @Published var size: PlayerSize { didSet { defaults.set(size.rawValue, forKey: "playerSize") } }

    var onShortcutChange: () -> Void = {}

    static let defaultSpeak = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    /// TEXT_TO_SPEECH_SERVER, then `serverURL` set by hand (`defaults write`), then ours.
    var server: String {
        let raw = ProcessInfo.processInfo.environment["TEXT_TO_SPEECH_SERVER"] ?? defaults.string(forKey: "serverURL") ?? Voice.defaultServer
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Voice.defaultServer : String(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    init() {
        let d = UserDefaults.standard
        if !d.bool(forKey: "importedTauriSettings") { TauriSettings.importOnce(into: d) }
        if let data = d.data(forKey: "speakShortcut") {
            speakShortcut = data == Data("none".utf8) ? nil : (try? JSONDecoder().decode(Shortcut.self, from: data)) ?? Self.defaultSpeak
        } else {
            speakShortcut = Self.defaultSpeak
        }
        speed = d.object(forKey: "speed") as? Double ?? 1
        position = PlayerPosition(rawValue: d.string(forKey: "playerPosition") ?? "") ?? .center
        size = PlayerSize(rawValue: d.string(forKey: "playerSize") ?? "") ?? .standard
    }

    private func saveShortcut(_ value: Shortcut?) {
        let data = value.flatMap { try? JSONEncoder().encode($0) } ?? Data("none".utf8)
        defaults.set(data, forKey: "speakShortcut")
    }
}

/// ~/Library/Application Support, or TTS_DATA_DIR for end-to-end runs: a test never touches
/// the person's settings.
enum DataFolder {
    static let root: URL = ProcessInfo.processInfo.environment["TTS_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

/// The Tauri build's config.json (snake_case keys), read once.
enum TauriSettings {
    static func importOnce(into d: UserDefaults) {
        defer { d.set(true, forKey: "importedTauriSettings") }
        let file = DataFolder.root.appendingPathComponent("click.ciromaciel.text-to-speech/config.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let text = json["speak_shortcut"] as? String {
            let value = parse(accelerator: text)
            d.set(value.flatMap { try? JSONEncoder().encode($0) } ?? Data("none".utf8), forKey: "speakShortcut")
        }
        if let speed = json["speed"] as? Double { d.set(min(2, max(0.5, speed)), forKey: "speed") }
        if let position = json["player_position"] as? String, PlayerPosition(rawValue: position) != nil { d.set(position, forKey: "playerPosition") }
        if let size = json["player_size"] as? String, PlayerSize(rawValue: size) != nil { d.set(size, forKey: "playerSize") }
        if let server = json["server_url"] as? String, !server.isEmpty { d.set(server, forKey: "serverURL") }
    }

    /// "CmdOrCtrl+Shift+KeyS", "Command+Alt+Digit2": the Tauri accelerator syntax with key codes.
    static func parse(accelerator: String) -> Shortcut? {
        var mods: NSEvent.ModifierFlags = []
        var key: Int?
        for raw in accelerator.split(separator: "+") {
            var part = raw.trimmingCharacters(in: .whitespaces).lowercased()
            switch part {
            case "commandorcontrol", "cmdorctrl", "command", "cmd", "meta", "super": mods.insert(.command)
            case "control", "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            case "alt", "option": mods.insert(.option)
            default:
                if part.hasPrefix("key") && part.count == 4 { part = String(part.dropFirst(3)) }
                if part.hasPrefix("digit") && part.count == 6 { part = String(part.dropFirst(5)) }
                key = keyCodes[part]
            }
        }
        guard let key else { return nil }
        return Shortcut(keyCode: UInt32(key), modifiers: mods)
    }

    private static let keyCodes: [String: Int] = [
        "space": kVK_Space, "enter": kVK_Return, "tab": kVK_Tab,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]
}
