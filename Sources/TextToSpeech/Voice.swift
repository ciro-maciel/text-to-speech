// The voice is Rafael, from Fish Audio, through the Text to Speech server: the same call the
// page at ciromaciel.click/tools/text-to-speech makes. The app never holds a Fish Audio key; the
// server does. What goes over the network is the text of the part being read and the speed.
// `speak-stream` passes the MP3 and when each word is spoken on as Fish sends them, so the voice
// starts with the first piece (about 0.7 s) instead of the whole sentence.
import AppKit
import ApplicationServices
import Foundation

enum Voice {
    static let defaultServer = "https://manager.ciromaciel.click/text-to-speech"

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

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        return URLSession(configuration: config)
    }()

    /// `speak-stream`: one NDJSON line per piece, as Fish sends it.
    static func stream(_ text: String, speed: Double, server: String) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var request = URLRequest(url: URL(string: "\(server)/speak-stream")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "speed": speed])
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                        // The server writes its errors for people, in Brazilian Portuguese.
                        throw Failure(message: json?["error"] as? String ?? L("voice.noAnswer"))
                    }
                    for try await line in bytes.lines {
                        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        if let b64 = json["audio"] as? String, let data = Data(base64Encoded: b64) {
                            continuation.yield(.audio(data))
                        } else if let words = json["words"] as? [[String: Any]] {
                            let list = words.compactMap { w -> (String, Double)? in
                                guard let t = w["text"] as? String, let s = (w["start"] as? NSNumber)?.doubleValue else { return nil }
                                return (t, s)
                            }
                            continuation.yield(.words(chunk: json["chunk"] as? Int ?? 0, offset: (json["offset"] as? NSNumber)?.doubleValue ?? 0, words: list))
                        } else if json["done"] != nil {
                            continuation.yield(.done)
                        } else if json["error"] != nil {
                            throw Failure(message: L("voice.noAnswer"))
                        }
                    }
                    continuation.finish()
                } catch let failure as Failure {
                    continuation.finish(throwing: failure)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : Failure(message: L("voice.noConnection")))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
