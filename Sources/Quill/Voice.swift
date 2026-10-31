import AVFoundation
import Speech

@MainActor
final class Listener {
    private let engine = AVAudioEngine()
    private var ready: (SpeechAnalyzer, SpeechTranscriber, AVAudioFormat)?
    private var live: (SpeechAnalyzer, AsyncStream<AnalyzerInput>.Continuation, Task<String, Never>)?
    private(set) var isListening = false
    var onPartial: (@MainActor (String) -> Void)?
    var onLevel: (@MainActor @Sendable (Float) -> Void)?

    static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func prepare() async throws {
        guard ready == nil else { return }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        ready = (analyzer, transcriber, format)
    }

    func start() async throws {
        guard !isListening else { return }
        isListening = true
        if ready == nil { try await prepare() }
        guard let (analyzer, transcriber, format) = ready else { isListening = false; return }
        ready = nil

        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let partial = onPartial
        let results = Task { @MainActor in
            var final = ""
            do {
                for try await r in transcriber.results {
                    let s = String(r.text.characters)
                    if r.isFinal { final += s; partial?(final) } else { partial?(final + s) }
                }
            } catch {}
            return final.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try await analyzer.start(inputSequence: stream)
        live = (analyzer, input, results)

        let node = engine.inputNode
        let natural = node.outputFormat(forBus: 0)
        let level = onLevel
        node.installTap(onBus: 0, bufferSize: 1024, format: natural, block: Self.tap(from: natural, to: format, into: input, level: level))
        engine.prepare()
        try engine.start()
    }

    func stop() async -> String {
        guard isListening, let (analyzer, input, results) = live else { isListening = false; return "" }
        live = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = await results.value
        isListening = false
        Task { try? await prepare() }
        return text
    }

    func cancel() {
        guard let (analyzer, input, results) = live else { return }
        live = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input.finish()
        results.cancel()
        isListening = false
        Task {
            await analyzer.cancelAndFinishNow()
            try? await prepare()
        }
    }

    func transcribe(file: URL) async throws -> String {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let collect = Task {
            var text = ""
            for try await r in transcriber.results where r.isFinal { text += String(r.text.characters) }
            return text
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let end = try await analyzer.analyzeSequence(from: AVAudioFile(forReading: file)) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func tap(
        from natural: AVAudioFormat, to format: AVAudioFormat,
        into input: AsyncStream<AnalyzerInput>.Continuation, level: (@MainActor @Sendable (Float) -> Void)?
    ) -> AVAudioNodeTapBlock {
        let converter = AVAudioConverter(from: natural, to: format)
        return { buffer, _ in
            if let data = buffer.floatChannelData?[0] {
                var sum: Float = 0
                let n = Int(buffer.frameLength)
                for i in 0..<n { sum += data[i] * data[i] }
                let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
                let db = 20 * log10(max(rms, 1e-6))
                let value = max(0, min(1, (db + 55) / 45))
                if let level { Task { @MainActor in level(value) } }
            }
            guard let converter else { input.yield(AnalyzerInput(buffer: buffer)); return }
            let ratio = format.sampleRate / natural.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
        }
    }
}
