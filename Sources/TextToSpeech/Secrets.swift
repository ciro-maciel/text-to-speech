// The person's own keys: the Fish Audio API key and the Hugging Face token Phonon downloads its
// model with. They live in the login keychain, never in UserDefaults; an end-to-end run
// (TTS_DATA_DIR) keeps them in a file of its temporary folder instead, so a test never reads or
// writes the person's keychain. TTS_FISH_KEY and TTS_HF_TOKEN override both, for checks.
import Foundation
import Security

enum Secret: String {
    case fishKey = "fish-api-key"
    case huggingFaceToken = "huggingface-token"

    private static let service = "click.ciromaciel.text-to-speech"
    private static var testFolder: URL? {
        ProcessInfo.processInfo.environment["TTS_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private var environmentKey: String { self == .fishKey ? "TTS_FISH_KEY" : "TTS_HF_TOKEN" }

    var value: String? {
        if let forced = ProcessInfo.processInfo.environment[environmentKey], !forced.isEmpty { return forced }
        if let folder = Self.testFolder {
            return (try? String(contentsOf: folder.appendingPathComponent("\(rawValue).secret"), encoding: .utf8))
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the value, or removes it when empty.
    func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = Self.testFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? trimmed.write(to: folder.appendingPathComponent("\(rawValue).secret"), atomically: true, encoding: .utf8)
            return
        }
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// "…a1b2": enough to recognize a saved key without showing it.
    var hint: String? { value.map { "…" + String($0.suffix(4)) } }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: rawValue]
    }
}
