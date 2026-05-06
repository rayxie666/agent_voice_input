import AVFoundation
import Foundation

final class AudioRecorder: NSObject {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat!
    private(set) var samples: [Float] = []

    var onLevel: ((Float) -> Void)?

    private let lock = NSLock()

    override init() {
        super.init()
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )
    }

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let input = engine.inputNode
        let inFmt = input.inputFormat(forBus: 0)
        guard inFmt.sampleRate > 0 else {
            throw NSError(
                domain: "AudioRecorder", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        converter = AVAudioConverter(from: inFmt, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) {
            [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let copy = samples
        lock.unlock()
        return copy
    }

    /// Read-only snapshot of accumulated samples without stopping recording.
    /// Used by the streaming transcription loop so it can re-run whisper on
    /// the buffer-so-far without disturbing the live capture.
    func snapshot() -> [Float] {
        lock.lock()
        let copy = samples
        lock.unlock()
        return copy
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: outFrameCapacity)
        else { return }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil,
              let chan = outBuffer.floatChannelData?[0]
        else { return }

        let n = Int(outBuffer.frameLength)
        let bp = UnsafeBufferPointer(start: chan, count: n)
        let chunk = Array(bp)

        var peak: Float = 0
        for s in chunk { peak = max(peak, abs(s)) }

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(peak)
        }
    }
}
