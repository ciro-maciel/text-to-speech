// Plays an MP3 as it arrives: AudioFileStream cuts the bytes into MPEG packets, AVAudioConverter
// turns them into PCM, and AVAudioPlayerNode plays each buffer through a time-pitch unit, so the
// speed changes without changing the voice. The voice starts with Fish's first piece (about
// 0.7 s) instead of the whole sentence (1.5 to 3 s).
import AudioToolbox
import AVFoundation
import Foundation

@MainActor
final class StreamPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private var parser: AudioFileStreamID?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var pending = 0
    private var isInputDone = false
    private var isFinished = false
    private var isPaused = false
    private var lastTime: Double = 0
    private let meter = LevelMeter()
    var onFinish: () -> Void = {}

    init(rate: Double) {
        pitch.rate = Float(rate)
        engine.attach(node)
        engine.attach(pitch)
        AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), propertyListener, packetsListener, kAudioFileMP3Type, &parser)
    }

    func feed(_ data: Data) {
        guard let parser, !data.isEmpty, !isFinished else { return }
        data.withUnsafeBytes { raw in
            _ = AudioFileStreamParseBytes(parser, UInt32(raw.count), raw.baseAddress, [])
        }
    }

    /// No more bytes: what the converter still holds is played, then onFinish.
    func finishInput() {
        guard !isInputDone else { return }
        isInputDone = true
        drain()
        if converter == nil { finish() } else { checkDone() }
    }

    var rate: Double {
        get { Double(pitch.rate) }
        set { pitch.rate = Float(newValue) }
    }

    func pause() {
        isPaused = true
        node.pause()
    }

    func resume() {
        isPaused = false
        if engine.isRunning { node.play() }
    }

    func stop() {
        isFinished = true
        node.stop()
        engine.stop()
        if let parser { AudioFileStreamClose(parser) }
        parser = nil
    }

    /// Seconds of this part's audio played so far.
    var currentTime: Double {
        if let nodeTime = node.lastRenderTime, let time = node.playerTime(forNodeTime: nodeTime), time.sampleRate > 0, node.isPlaying {
            lastTime = max(lastTime, Double(time.sampleTime) / time.sampleRate)
        }
        return lastTime
    }

    var isPlaying: Bool { node.isPlaying && !isPaused }
    var level: Double { isPlaying ? meter.value : 0 }

    // MARK: - Parsing and decoding

    fileprivate func formatReady() {
        guard let parser, inputFormat == nil else { return }
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr,
              let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(standardFormatWithSampleRate: input.sampleRate, channels: input.channelCount) else { return }
        inputFormat = input
        outputFormat = output
        converter = AVAudioConverter(from: input, to: output)
        engine.connect(node, to: pitch, format: output)
        engine.connect(pitch, to: engine.mainMixerNode, format: output)
        let meter = self.meter
        node.installTap(onBus: 0, bufferSize: 1024, format: output) { buffer, _ in meter.measure(buffer) }
    }

    fileprivate func packets(_ count: UInt32, _ bytes: UInt32, _ data: UnsafeRawPointer, _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let input = inputFormat, let converter, let descriptions, count > 0 else { return }
        var maxPacket = 0
        for i in 0..<Int(count) { maxPacket = max(maxPacket, Int(descriptions[i].mDataByteSize)) }
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: AVAudioPacketCount(count), maximumPacketSize: maxPacket)
        memcpy(compressed.data, data, Int(bytes))
        compressed.byteLength = bytes
        compressed.packetCount = AVAudioPacketCount(count)
        if let target = compressed.packetDescriptions {
            for i in 0..<Int(count) { target[i] = descriptions[i] }
        }
        var fed = false
        convert(converter) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return compressed
        }
        _ = input
    }

    private func drain() {
        guard let converter else { return }
        convert(converter) { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    /// Converts whatever the input block gives, scheduling every PCM buffer that comes out.
    private func convert(_ converter: AVAudioConverter, _ input: @escaping AVAudioConverterInputBlock) {
        guard let output = outputFormat else { return }
        while true {
            guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 1152 * 8) else { return }
            var error: NSError?
            let status = converter.convert(to: pcm, error: &error, withInputFrom: input)
            if pcm.frameLength > 0 { schedule(pcm) }
            if status != .haveData || error != nil { return }
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        pending += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pending -= 1
                self.checkDone()
            }
        }
        if !engine.isRunning {
            do { try engine.start() } catch { NSLog("[player] engine: \(error)"); return }
            if !isPaused { node.play() }
        }
    }

    private func checkDone() {
        if isInputDone && pending == 0 { finish() }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish()
    }
}

/// The loudness of what is playing, written on the audio thread.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0.0
    var value: Double { lock.lock(); defer { lock.unlock() }; return current }

    func measure(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        lock.lock(); current = Double(max(0, min(1, (db + 40) / 40))); lock.unlock()
    }
}

// AudioFileStream calls back on the thread that parses, which is the main one (feed runs there).
private func propertyListener(_ client: UnsafeMutableRawPointer, _ stream: AudioFileStreamID, _ property: AudioFileStreamPropertyID,
                              _ flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
    guard property == kAudioFileStreamProperty_ReadyToProducePackets else { return }
    let player = Unmanaged<StreamPlayer>.fromOpaque(client).takeUnretainedValue()
    MainActor.assumeIsolated { player.formatReady() }
}

private func packetsListener(_ client: UnsafeMutableRawPointer, _ bytes: UInt32, _ count: UInt32, _ data: UnsafeRawPointer,
                             _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
    let player = Unmanaged<StreamPlayer>.fromOpaque(client).takeUnretainedValue()
    MainActor.assumeIsolated { player.packets(count, bytes, data, descriptions) }
}
