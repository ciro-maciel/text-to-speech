// The two voices the person picks between, each on their own account:
// - Rafael, from Fish Audio, over the internet with the person's own Fish Audio API key. The app
//   calls Fish directly (`/v1/tts/stream/with-timestamp`), so the MP3 and when each word is spoken
//   arrive as Fish sends them and the voice starts with the first piece (about 0.7 s). Only the
//   text of the part being read goes, to Fish and nowhere else.
// - Davi, from Phonon (Gradium), on this Mac: the `ptts` command inside the app runs Phonon's
//   Brazilian Portuguese model in 4 bits (about 170 MB, only while a part is generated), downloaded
//   once with the person's Hugging Face token. Nothing leaves the Mac after that download. The
//   model's licence is CC BY-NC 4.0: the person accepts it on Hugging Face for their own use.
import AppKit
import ApplicationServices
import Foundation

enum VoiceEngine: String, CaseIterable {
    case fish, phonon

    /// The name the player shows.
    var speaker: String { self == .fish ? "Rafael" : "Davi" }
    var title: String { L("engine.\(rawValue)") }
    var secret: Secret { self == .fish ? .fishKey : .huggingFaceToken }
    /// Parts generated at once: Fish takes several, Phonon one, so its memory stays at one model.
    var partsAtOnce: Int { self == .fish ? 3 : 1 }
    var audioFormat: AudioFormat { self == .fish ? .mp3 : .wav }
}

enum AudioFormat { case mp3, wav }

enum Voice {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Event {
        case audio(Data)
        /// The latest timing snapshot of a text chunk, which replaces the one before.
        case words(chunk: Int, offset: Double, words: [(text: String, start: Double)])
        case done
    }

    static func stream(_ text: String, speed: Double, engine: VoiceEngine) -> AsyncThrowingStream<Event, Error> {
        switch engine {
        case .fish: return Fish.stream(text, speed: speed)
        case .phonon: return Phonon.stream(text)
        }
    }
}

// MARK: - Fish Audio

enum Fish {
    /// Rafael (Brasil), from the Fish Audio library.
    static let voiceId = "0ffee1af32254090b3630823baade12b"
    static let keysPage = URL(string: "https://fish.audio/app/api-keys/")!
    /// Fish's free model ends on 30/11/2026; from 01/12 in Brasília the paid one, by the date.
    static var model: String { Date() >= Date(timeIntervalSince1970: 1_796_094_000) ? "s2.1-pro" : "s2.1-pro-free" }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        return URLSession(configuration: config)
    }()

    static func stream(_ text: String, speed: Double) -> AsyncThrowingStream<Voice.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let key = Secret.fishKey.value else {
                    continuation.finish(throwing: Voice.Failure(message: L("fish.noKey")))
                    return
                }
                var request = URLRequest(url: URL(string: "https://api.fish.audio/v1/tts/stream/with-timestamp")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(model, forHTTPHeaderField: "model")
                request.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "text": text, "reference_id": voiceId, "format": "mp3", "mp3_bitrate": 64,
                    "latency": "balanced", "prosody": ["speed": speed],
                ] as [String: Any])
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw Voice.Failure(message: message(forStatus: status)) }
                    var sentAudio = false
                    // Server-Sent Events: each `data:` line holds a piece of the MP3 and the latest
                    // timing snapshot of its text chunk.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:"),
                              let json = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any] else { continue }
                        if let b64 = json["audio_base64"] as? String, let data = Data(base64Encoded: b64), !data.isEmpty {
                            continuation.yield(.audio(data))
                            sentAudio = true
                        }
                        if let alignment = json["alignment"] as? [String: Any], let segments = alignment["segments"] as? [[String: Any]] {
                            let list = segments.compactMap { w -> (String, Double)? in
                                guard let t = w["text"] as? String, let s = (w["start"] as? NSNumber)?.doubleValue else { return nil }
                                return (t, s)
                            }
                            continuation.yield(.words(chunk: json["chunk_seq"] as? Int ?? 0,
                                                      offset: (json["chunk_audio_offset_sec"] as? NSNumber)?.doubleValue ?? 0, words: list))
                        }
                    }
                    guard sentAudio else { throw Voice.Failure(message: L("voice.noAnswer")) }
                    continuation.yield(.done)
                    continuation.finish()
                } catch let failure as Voice.Failure {
                    continuation.finish(throwing: failure)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : Voice.Failure(message: L("voice.noConnection")))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func message(forStatus status: Int) -> String {
        switch status {
        case 401, 403: return L("fish.badKey")
        case 402: return L("fish.noCredit")
        case 429: return L("fish.busy")
        default: return L("voice.noAnswer")
        }
    }
}

// MARK: - Phonon

enum Phonon {
    /// Phonon 40m in Brazilian Portuguese, pinned to the 29/10/2026 revision: once downloaded it
    /// loads from the cache with no network call. Davi is a voice of Gradium's catalog (Apache-2.0).
    static let model = "hf://gradium/phonon-40m-pt@4cbfd742a1555d60eb5399c6d296e9f2e07389e9"
    static let voice = "Davi"
    static let modelPage = URL(string: "https://huggingface.co/gradium/phonon-40m-pt")!
    static let tokensPage = URL(string: "https://huggingface.co/settings/tokens/new?tokenType=read")!

    /// The `ptts` command shipped inside the app, next to the app's own executable.
    static var command: URL? { Bundle.main.url(forAuxiliaryExecutable: "ptts") }
    /// Where Hugging Face's cache goes: the app's own folder, removed with the app's data.
    static var cache: URL { DataFolder.root.appendingPathComponent("click.ciromaciel.text-to-speech/huggingface", isDirectory: true) }

    static func stream(_ text: String) -> AsyncThrowingStream<Voice.Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let wav = try await generate(text)
                    continuation.yield(.audio(wav))
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One part → its WAV (24 kHz, 16-bit, mono). The process stops if the reading is cancelled.
    static func generate(_ text: String) async throws -> Data {
        guard let command else { throw Voice.Failure(message: L("phonon.missing")) }
        guard let token = Secret.huggingFaceToken.value else { throw Voice.Failure(message: L("phonon.noToken")) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("tts-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = command
        process.arguments = ["--model", model, "--lang", "pt", "--quant", "q4k", "--voice", voice, text, "-o", output.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_TOKEN"] = token
        environment["HF_HOME"] = cache.path
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { done.resume(throwing: Voice.Failure(message: L("phonon.missing"))) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        let log = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard status == 0, let wav = try? Data(contentsOf: output), wav.count > 44 else {
            NSLog("[phonon] exit %d: %@", status, String(log.suffix(600)))
            throw Voice.Failure(message: message(forLog: log))
        }
        return wav
    }

    /// The command's log, read for the one thing the person can fix. Hugging Face answers the same
    /// "Authentication required … GatedRepo" for a missing token, a wrong one and access not asked.
    static func message(forLog log: String) -> String {
        let text = log.lowercased()
        if text.contains("gatedrepo") || text.contains("restricted") || text.contains("authentication required") || text.contains("401") || text.contains("403") {
            return L("phonon.noAccess")
        }
        if text.contains("dns") || text.contains("connect") || text.contains("network") || text.contains("timed out") {
            return L("phonon.noConnection")
        }
        return L("phonon.failed")
    }
}

/// Seconds of audio in a WAV: its `fmt ` chunk gives the byte rate, its `data` chunk the length.
enum Wave {
    static func seconds(_ data: Data) -> Double {
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : 0 }
        var at = 12, byteRate = 48000, length = max(0, bytes.count - 44)
        while at + 8 <= bytes.count {
            let id = String(bytes: bytes[at..<at + 4], encoding: .ascii) ?? ""
            let size = u32(at + 4)
            if id == "fmt " { byteRate = max(1, u32(at + 16)) }
            if id == "data" { length = min(size, bytes.count - at - 8); break }
            at += 8 + size + (size & 1)
        }
        return Double(length) / Double(byteRate)
    }
}

/// Reads the selection of the app in front: a sentinel on the clipboard, ⌘C to that app, wait
/// up to 800 ms for the clipboard to change, then the clipboard back as it was.
enum Selection {
    enum Outcome { case text(String), nothingSelected, needsAccessibility }

    static func read() async -> Outcome {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let board = NSPasteboard.general
        let saved = board.string(forType: .string)
        let sentinel = "__tts_sentinel_\(UUID().uuidString)"
        board.clearContents()
        board.setString(sentinel, forType: .string)
        let before = board.changeCount
        postCommandC()
        var text = ""
        let started = Date()
        while Date().timeIntervalSince(started) < 0.8 {
            try? await Task.sleep(for: .milliseconds(40))
            if board.changeCount != before, let copied = board.string(forType: .string), copied != sentinel {
                text = copied
                break
            }
        }
        board.clearContents()
        if let saved { board.setString(saved, forType: .string) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .nothingSelected : .text(trimmed)
    }

    private static func postCommandC() {
        // Virtual key code of "C" on ANSI and ISO layouts.
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
