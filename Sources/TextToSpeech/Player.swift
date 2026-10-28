// The reading and its window. The selection is cut into parts (Reading.split); a few are
// generated ahead of the one playing, three at a time, as many as the server takes from one
// person. The window shows the part being read with the word being spoken, the one before and
// the one after, a bar of the whole text's time and the clock. Space pauses, ← and → go back or
// forward a part, − and + change the speed, Esc stops. The rules are the Tauri build's main.js.
import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class ReadingSession: ObservableObject {
    /// One part's audio and timings, filled as they come from the server.
    final class Part {
        let text: String
        private(set) var data = Data()
        private(set) var chunks: [Int: (offset: Double, words: [(text: String, start: Double)])] = [:]
        private(set) var isComplete = false
        private(set) var error: Error?
        /// The speed it was asked at: a later speed change applies to it as a playback rate.
        private(set) var speed: Double = 1
        private(set) var times: [Reading.Word] = []
        var isStarted: Bool { task != nil }
        var hasAudio: Bool { !data.isEmpty }
        /// The part playing listens here.
        var onAudio: ((Data) -> Void)?
        var onEnd: (() -> Void)?
        var onChange: (() -> Void)?
        private var task: Task<Void, Never>?

        init(text: String) { self.text = text }

        /// MP3 at 64 kbit/s: 8000 bytes a second, which is how the server knows the length too.
        var duration: Double { Double(data.count) / 8000 }

        func start(speed: Double, server: String) {
            self.speed = speed
            task = Task { @MainActor in
                do {
                    for try await event in Voice.stream(text, speed: speed, server: server) {
                        switch event {
                        case .audio(let bytes):
                            data.append(bytes)
                            onAudio?(bytes)
                        case let .words(chunk, offset, words):
                            chunks[chunk] = (offset, words)
                        case .done:
                            break
                        }
                        retime()
                        onChange?()
                    }
                    isComplete = true
                } catch {
                    if !(error is CancellationError) { self.error = error }
                }
                retime()
                onEnd?()
                onChange?()
            }
        }

        func cancel() { task?.cancel() }

        private func retime() {
            let spoken = chunks.keys.sorted().flatMap { key in chunks[key]!.words.map { ($0.text, $0.start + chunks[key]!.offset) } }
            // Until the part is whole, its length is guessed from the text, as the clock does.
            let length = isComplete ? duration : max(duration, Double(text.count) * 0.057 / speed)
            times = Reading.wordTimes(text, spoken: spoken, duration: length)
        }
    }

    let parts: [Part]
    let server: String
    @Published var index = 0
    @Published var isPaused = false
    @Published var hint: String?
    @Published var speed: Double
    private(set) var player: StreamPlayer?
    private var finish: CheckedContinuation<Bool, Never>?
    private var resume: CheckedContinuation<Void, Never>?
    private var jumped = false
    private(set) var isLive = true
    /// When the reading began and when its voice did: the start the streaming is for.
    let startedAt = Date()
    private(set) var firstSoundAt: Date?

    private static let inFlight = 3, window = 4
    /// Before a part has audio the clock estimates from the text: seconds per character at 1×.
    private static let secondsPerChar = 0.057

    init(text: String, speed: Double, server: String) {
        parts = Reading.split(text).map(Part.init)
        self.speed = speed
        self.server = server
    }

    var current: Part? { parts.indices.contains(index) ? parts[index] : nil }

    /// Starts the parts the window needs next, three at a time: the server's share per person.
    private func ensureAhead() {
        var running = parts.filter { $0.isStarted && !$0.isComplete && $0.error == nil }.count
        for k in index..<min(parts.count, index + Self.window) {
            let part = parts[k]
            if part.isStarted { continue }
            // The part being read is always asked for, even past the limit.
            if running >= Self.inFlight && k != index { break }
            running += 1
            part.onChange = { [weak self] in
                guard let self, self.isLive else { return }
                self.objectWillChange.send()
            }
            part.start(speed: speed, server: server)
        }
    }

    /// Reads to the end; false when it stopped on an error or was stopped.
    func run() async -> Bool {
        while isLive && index < parts.count {
            let i = index
            let part = parts[i]
            ensureAhead()
            if isPaused {
                await withCheckedContinuation { resume = $0 }
                resume = nil
                guard isLive else { return false }
                if index != i { continue }
            }
            jumped = false
            let played = await play(part)
            guard isLive else { return false }
            if let error = part.error, !played || !part.hasAudio {
                hint = error.localizedDescription
                return false
            }
            if !played { hint = L("player.partFailed"); return false }
            if jumped { continue }
            index = i + 1
            ensureAhead()
        }
        return isLive
    }

    /// Plays a part from its first byte, while the rest still comes; true when it played to the end.
    private func play(_ part: Part) async -> Bool {
        let player = StreamPlayer(rate: speed / part.speed)
        self.player = player
        if isPaused { player.pause() }
        return await withCheckedContinuation { continuation in
            finish = continuation
            player.onFinish = { [weak self] in self?.endPart(played: true) }
            part.onAudio = { [weak self, weak player] bytes in
                if self?.firstSoundAt == nil { self?.firstSoundAt = Date() }
                player?.feed(bytes)
            }
            part.onEnd = { [weak self, weak player] in
                if part.error != nil && !part.hasAudio { self?.endPart(played: false) } else { player?.finishInput() }
            }
            if part.hasAudio {
                if firstSoundAt == nil { firstSoundAt = Date() }
                player.feed(part.data)
            }
            if part.isComplete || part.error != nil { part.onEnd?() }
        }
    }

    private func endPart(played: Bool) {
        current?.onAudio = nil
        current?.onEnd = nil
        player?.stop()
        player = nil
        finish?.resume(returning: played)
        finish = nil
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused { player?.pause() } else if let player { player.resume() } else { resume?.resume() }
    }

    /// Back within the first seconds of a part goes to the one before; later, to its start.
    func jump(_ delta: Int) {
        var target = index + delta
        if delta < 0, let player, player.currentTime > 1.5 { target = index }
        target = max(0, min(parts.count - 1, target))
        if target == index && delta > 0 { return }
        index = target
        jumped = true
        ensureAhead()
        endPart(played: true)
        resume?.resume()
    }

    /// Saved by the caller; applied at once to the part playing.
    func setSpeed(_ value: Double) {
        speed = value
        if let player, let part = current { player.rate = value / part.speed }
    }

    func stop() {
        isLive = false
        endPart(played: false)
        resume?.resume()
        resume = nil
        for part in parts { part.cancel() }
    }

    // MARK: - What the window shows

    func seconds(_ part: Part) -> Double {
        if part.isComplete && part.duration > 0 { return part.duration * part.speed / speed }
        return max(part.duration * part.speed / speed, Double(part.text.count) * Self.secondsPerChar / speed)
    }

    var elapsedAndTotal: (Double, Double) {
        var before = 0.0, total = 0.0
        for (i, p) in parts.enumerated() {
            let s = seconds(p)
            if i < index { before += s }
            total += s
        }
        if let player, let part = current { before += player.currentTime * part.speed / speed }
        return (before, total)
    }

    var spokenCount: Int {
        guard let player, let part = current else { return 0 }
        return Reading.wordsSpoken(part.times, at: player.currentTime)
    }

    var isSounding: Bool { current?.hasAudio ?? false }

    /// 0–1, the voice's loudness now.
    var level: Double { player?.level ?? 0 }
}

// MARK: - The window

struct PlayerView: View {
    @ObservedObject var session: ReadingSession
    let size: PlayerSize

    private var nowFont: CGFloat { min(18, max(13, size.size.width * 0.039)) }
    private var sideFont: CGFloat { min(13, max(11, size.size.width * 0.031)) }
    private var lines: Int { size == .compact ? 2 : size == .standard ? 3 : 4 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                head(context.date)
                tele
                track
                foot
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18))
            .frame(width: size.size.width, height: size.size.height, alignment: .topLeading)
            .background(Zen.gray9)
        }
    }

    private func head(_ date: Date) -> some View {
        HStack(spacing: 12) {
            if !session.parts.isEmpty { HStack(spacing: 8) {
                Text(stateWord).font(Zen.font(10, .extraBold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Zen.gray0)
                Meter(level: session.level, time: date.timeIntervalSinceReferenceDate)
            } }
            Spacer(minLength: 0)
            if session.parts.count > 1 {
                Text(L("player.partOf", session.index + 1, session.parts.count)).font(Zen.font(12, .medium)).monospacedDigit().foregroundStyle(Zen.gray4)
            }
        }
    }

    private var stateWord: String {
        session.isPaused ? L("player.paused") : session.isSounding ? L("player.reading") : L("player.preparing")
    }

    private var tele: some View {
        VStack(alignment: .leading, spacing: 5) {
            if session.index > 0 {
                Text(session.parts[session.index - 1].text).font(Zen.font(sideFont, .medium)).foregroundStyle(Zen.gray6).lineLimit(1)
            }
            if let part = session.current {
                spokenText(part.text, spoken: session.spokenCount)
                    .font(Zen.font(nowFont, .bold)).lineSpacing(nowFont * 0.35).lineLimit(lines)
            }
            if session.index + 1 < session.parts.count {
                Text(session.parts[session.index + 1].text).font(Zen.font(sideFont, .medium)).foregroundStyle(Zen.gray6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The words already spoken light up.
    private func spokenText(_ text: String, spoken: Int) -> Text {
        let words = text.split(whereSeparator: \.isWhitespace)
        var result = Text("")
        for (i, w) in words.enumerated() {
            result = result + Text(w + " ").foregroundColor(i < spoken ? Zen.gray0 : Zen.gray5)
        }
        return result
    }

    private var track: some View {
        let (elapsed, total) = session.elapsedAndTotal
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Zen.gray7)
                Rectangle().fill(Zen.gray0).frame(width: total > 0 ? proxy.size.width * min(1, elapsed / total) : 0)
            }
        }
        .frame(height: 3)
    }

    private var foot: some View {
        let (elapsed, total) = session.elapsedAndTotal
        return HStack(spacing: 12) {
            if let hint = session.hint {
                Text(hint).font(Zen.font(12, .medium)).foregroundStyle(Zen.gray4).lineLimit(1)
            } else {
                Text(L("player.clockOf", Reading.clock(elapsed), Reading.clock(total))).font(Zen.font(12, .medium)).monospacedDigit().foregroundStyle(Zen.gray4)
                Spacer(minLength: 0)
                if session.isPaused {
                    HStack(spacing: 5) {
                        Kbd(text: L("key.space")); Text(L("player.keyResume"))
                        Kbd(text: "←"); Kbd(text: "→"); Text(L("player.keyPart"))
                    }
                    .font(Zen.font(11, .medium)).foregroundStyle(Zen.gray4)
                } else {
                    Text("Rafael · " + Self.speedText(session.speed)).font(Zen.font(12, .medium)).foregroundStyle(Zen.gray3)
                }
            }
        }
    }

    static func speedText(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(2)).locale(Localization.locale)) + "×"
    }
}

private struct Kbd: View {
    let text: String
    var body: some View {
        Text(text).font(Zen.font(11, .bold)).foregroundStyle(Zen.gray3)
            .padding(.horizontal, 5).frame(minHeight: 18)
            .overlay(Rectangle().strokeBorder(Zen.gray7, lineWidth: 1))
    }
}

/// Four bars beside the state, following the voice's loudness.
private struct Meter: View {
    let level: Double
    let time: TimeInterval
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let wobble = 0.6 + 0.4 * abs(sin(time * 1000 / 90 + Double(i) * 1.7))
                Rectangle().fill(Zen.gray0).frame(width: 2, height: 10 * max(0.15, level * wobble))
            }
        }
        .frame(height: 10)
    }
}

/// The floating player: borderless, over every app and space, on the display with the cursor.
/// It takes the keyboard while a reading is on, for Space, the arrows, − and +.
final class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PlayerController {
    private var panel: PlayerPanel?
    private var keys: Any?
    var onKey: (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Bool = { _, _ in false }

    func show(_ session: ReadingSession, size: PlayerSize, position: PlayerPosition) {
        let panel = self.panel ?? {
            let p = PlayerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.hasShadow = false
            p.isOpaque = true
            p.backgroundColor = NSColor(Zen.gray9)
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.appearance = NSAppearance(named: .aqua)
            return p
        }()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: PlayerView(session: session, size: size))
        panel.setContentSize(size.size)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame { panel.setFrameOrigin(Self.origin(position, size.size, area)) }
        panel.orderFrontRegardless()
        panel.makeKey()
        if keys == nil {
            keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let code = event.keyCode, mods = event.modifierFlags
                let handled = MainActor.assumeIsolated { self?.onKey(code, mods) ?? false }
                return handled ? nil : event
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    var windowNumber: Int { panel?.windowNumber ?? 0 }

    static func origin(_ position: PlayerPosition, _ size: CGSize, _ area: CGRect) -> CGPoint {
        let margin: CGFloat = 24
        let parts = position == .center ? ["middle", "center"] : position.rawValue.split(separator: "-").map(String.init)
        let x: CGFloat = parts[1] == "left" ? area.minX + margin : parts[1] == "right" ? area.maxX - size.width - margin : area.midX - size.width / 2
        let y: CGFloat = parts[0] == "top" ? area.maxY - size.height - margin : parts[0] == "bottom" ? area.minY + margin : area.midY - size.height / 2
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
