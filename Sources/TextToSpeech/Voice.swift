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
    /// How the text becomes parts. Fish comes over the internet, so it starts with a short part
    /// and ramps up. Phonon makes 150 words in under 3 s on the Mac, and each call is said as a
    /// whole: short parts gave each one its own intonation and a pause at every seam, where the
    /// CCM Stack voice says the same text in one call. So Phonon reads whole paragraphs.
    func parts(_ text: String) -> [String] {
        self == .fish ? Reading.split(text) : Reading.splitIntoParagraphs(Reading.unwrapLines(text), max: Reading.wholeMax)
    }
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
        return Wave.trimmed(wav)
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
    /// Phonon ends each part with 0.6 to 0.8 s of silence and starts it with about 0.17 s
    /// (measured 12/11/2026); one part after another, that was close to a second of nothing at
    /// every seam. Keep 40 ms before the voice and 250 ms after, about a sentence's own pause;
    /// then the loudness the CCM Stack voice has (`louder`).
    /// 16-bit mono PCM only; anything else goes back as it came.
    static func trimmed(_ data: Data, lead: Double = 0.04, tail: Double = 0.25, threshold: Int16 = 600) -> Data {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : 0 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var at = 12, rate = 0, channels = 0, bits = 0, start = -1, length = 0
        while at + 8 <= bytes.count {
            let id = String(bytes: bytes[at..<at + 4], encoding: .ascii) ?? ""
            let size = u32(at + 4)
            if id == "fmt " { channels = u16(at + 10); rate = u32(at + 12); bits = u16(at + 22) }
            if id == "data" { start = at + 8; length = min(size, bytes.count - start); break }
            at += 8 + size + (size & 1)
        }
        guard start > 0, channels == 1, bits == 16, rate > 0, length >= 4 else { return data }
        let samples: [Int16] = bytes[start..<start + length - length % 2].withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        guard let first = samples.firstIndex(where: { abs(Int($0)) > Int(threshold) }),
              let last = samples.lastIndex(where: { abs(Int($0)) > Int(threshold) }) else { return data }
        let from = max(0, first - Int(lead * Double(rate)))
        let to = min(samples.count, last + 1 + Int(tail * Double(rate)))
        let kept = louder(Array(samples[from..<to]), rate: Double(rate))
        var out = Data()
        func put32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { out.append(contentsOf: $0) } }
        func put16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { out.append(contentsOf: $0) } }
        let dataBytes = kept.count * 2
        out.append(contentsOf: Array("RIFF".utf8)); put32(36 + dataBytes); out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1); put32(rate); put32(rate * 2); put16(2); put16(16)
        out.append(contentsOf: Array("data".utf8)); put32(dataBytes)
        kept.withUnsafeBytes { out.append(contentsOf: $0) }
        return out
    }

    /// The CCM Stack voice plays Phonon through ffmpeg's loudnorm at -16 LUFS; Phonon comes out
    /// near -22.6 LUFS (measured 12/11/2026), so here it played about 6.6 dB quieter. Same target:
    /// loudness measured as BS.1770 does (K filter, 400 ms blocks, -70 and -10 gates), one gain to
    /// -16 LUFS, and peaks over -1.5 dBFS bent under it by a soft limiter instead of clipped.
    static func louder(_ samples: [Int16], rate: Double, target: Double = -16, ceiling: Double = -1.5) -> [Int16] {
        guard let loudness = loudness(samples, rate: rate) else { return samples }
        let gain = pow(10, (target - loudness) / 20) / 32768
        let top = pow(10, ceiling / 20), knee = top * 0.7
        return samples.map { sample in
            var y = Double(sample) * gain
            let m = abs(y)
            if m > knee { y = (y < 0 ? -1 : 1) * (knee + (top - knee) * tanh((m - knee) / (top - knee))) }
            return Int16(max(-32768, min(32767, (y * 32768).rounded())))
        }
    }

    /// Integrated loudness in LUFS (ITU-R BS.1770-4, mono); nil for silence. One pass, sample by
    /// sample, keeping only a sum per 100 ms: a part's audio is never copied.
    static func loudness(_ samples: [Int16], rate: Double) -> Double? {
        // The K filter for any sample rate (the formulas libebur128 uses): a shelf, then a high-pass.
        var k = tan(Double.pi * 1681.974450955533 / rate), q = 0.7071752369554196
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let sb = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
        let sa = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        k = tan(Double.pi * 38.13547087602444 / rate); q = 0.5003270373238773; a0 = 1 + k / q + k * k
        let ha = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        var s1 = 0.0, s2 = 0.0, t1 = 0.0, t2 = 0.0, h1 = 0.0, h2 = 0.0, u1 = 0.0, u2 = 0.0
        let step = Int(0.1 * rate)
        var sums: [Double] = [], sum = 0.0, n = 0
        for sample in samples {
            let x = Double(sample) / 32768
            let t = sb[0] * x + sb[1] * s1 + sb[2] * s2 - sa[0] * t1 - sa[1] * t2
            s2 = s1; s1 = x; t2 = t1; t1 = t
            let u = t - 2 * h1 + h2 - ha[0] * u1 - ha[1] * u2
            h2 = h1; h1 = t; u2 = u1; u1 = u
            sum += u * u; n += 1
            if n == step { sums.append(sum); sum = 0; n = 0 }
        }
        // 400 ms blocks, 75% overlap: four 100 ms sums each.
        guard sums.count >= 4 else { return nil }
        let powers = (0...(sums.count - 4)).map { i in sums[i..<i + 4].reduce(0, +) / Double(4 * step) }
        func lufs(_ p: Double) -> Double { -0.691 + 10 * log10(p) }
        let loud = powers.filter { $0 > 0 && lufs($0) > -70 }
        guard !loud.isEmpty else { return nil }
        let gate = lufs(loud.reduce(0, +) / Double(loud.count)) - 10
        let kept = loud.filter { lufs($0) > gate }
        return lufs(kept.reduce(0, +) / Double(max(1, kept.count)))
    }

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
