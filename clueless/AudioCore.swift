import AVFoundation
import ScreenCaptureKit
import CoreAudio
import SoundAnalysis

struct AudioPacket: Sendable {
    let pcm: Data
    let level: Float
    let isSpeech: Bool
    var duration: Double { Double(pcm.count) / 48000 }
}

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum VirtualDevices {
    static func list() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            func string(_ selector: AudioObjectPropertySelector) -> String {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var s = UInt32(MemoryLayout<CFString?>.size)
                var value: Unmanaged<CFString>?
                guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &value) == noErr else { return "" }
                return value?.takeRetainedValue() as String? ?? ""
            }
            let name = string(kAudioObjectPropertyName)
            guard name.lowercased().contains("blackhole") else { return nil }
            return AudioDevice(id: id, uid: string(kAudioDevicePropertyDeviceUID), name: name)
        }
    }
}

// The analyzer is fed on the capture queue; SoundAnalysis delivers results on its own queue.
final class SpeechActivityClassifier: NSObject, SNResultsObserving {
    private let analyzer: SNAudioStreamAnalyzer
    private var position: AVAudioFramePosition = 0
    private let lock = NSLock()
    private var speech = false
    private var failure: Error?

    init(format: AVAudioFormat) throws {
        analyzer = SNAudioStreamAnalyzer(format: format)
        super.init()
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 24000)
        request.overlapFactor = 0.5
        try analyzer.add(request, withObserver: self)
    }

    func classify(_ buffer: AVAudioPCMBuffer) throws -> Bool {
        analyzer.analyze(buffer, atAudioFramePosition: position)
        position += AVAudioFramePosition(buffer.frameLength)
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return speech
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let speechConfidence = result.classification(forIdentifier: "speech")?.confidence ?? 0
        let singingConfidence = result.classification(forIdentifier: "singing")?.confidence ?? 0
        lock.lock()
        speech = speechConfidence >= 0.5 && speechConfidence > singingConfidence
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    deinit { analyzer.removeAllRequests() }
}

// All buffer conversion and playback scheduling is confined to queue.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "AudioRouter.pcm", qos: .userInitiated)
    private var stream: SCStream?
    private var microphone: AVAudioEngine?
    private var playback: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var scheduled = 0
    private var converter: AVAudioConverter?
    private var speechClassifier: SpeechActivityClassifier?
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    private var continuation: AsyncThrowingStream<AudioPacket, Error>.Continuation?
    private var accepting = false
    private var configurationObserver: NSObjectProtocol?

    func start(source: AudioSource, virtualDevice: AudioDevice?) async throws -> AsyncThrowingStream<AudioPacket, Error> {
        let pair = AsyncThrowingStream<AudioPacket, Error>.makeStream(bufferingPolicy: .bufferingOldest(100))
        queue.sync { continuation = pair.continuation; accepting = true; converter = nil }
        do {
            try queue.sync { speechClassifier = virtualDevice == nil ? try SpeechActivityClassifier(format: format) : nil }
            if let virtualDevice { try queue.sync { try startPlayback(device: virtualDevice) } }
            if source == .system {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard let display = content.displays.first else { throw RouterError("No available display for system audio capture.") }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                stream = capture
                try await capture.startCapture()
            } else {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RouterError("Microphone access denied. Enable it in System Settings → Privacy & Security.") }
                try Task.checkCancellation()
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var inputID = AudioDeviceID(0)
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &inputID) == noErr,
                      !VirtualDevices.list().contains(where: { $0.id == inputID }) else {
                    throw RouterError("Select a physical microphone in macOS Sound Settings. BlackHole recapture is disabled.")
                }
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0 else { throw RouterError("No microphone is available.") }
                input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                    // Process synchronously so the tap's borrowed buffer never escapes its lifetime.
                    self?.queue.sync { self?.consume(buffer) }
                }
                microphone = engine
                try engine.start()
                observeConfiguration(of: engine)
            }
            return pair.stream
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        queue.sync { accepting = false }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        microphone?.inputNode.removeTap(onBus: 0)
        microphone?.stop()
        microphone = nil
        if let stream { try? await stream.stopCapture() }
        stream = nil
        queue.sync {
            player?.stop(); playback?.stop(); player = nil; playback = nil
            continuation?.finish(); continuation = nil; converter = nil; speechClassifier = nil; scheduled = 0
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.continuation?.finish(throwing: error); self.accepting = false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let inputFormat = AVAudioFormat(streamDescription: asbd) else { return }
        var needed = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        let memory = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr,
              let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: list) else { return }
        consume(buffer)
    }

    private func consume(_ input: AVAudioPCMBuffer) {
        guard accepting, input.frameLength > 0 else { return }
        if converter?.inputFormat != input.format { converter = AVAudioConverter(from: input.format, to: format) }
        guard let converter,
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 24000 / input.format.sampleRate) + 32) else { return }
        var provided = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true; status.pointee = .haveData; return input
        }
        if let error { continuation?.finish(throwing: error); accepting = false; return }
        guard let samples = converted.int16ChannelData?[0], converted.frameLength > 0 else { return }
        let count = Int(converted.frameLength)
        var sum: Float = 0
        for i in 0..<count { let value = Float(samples[i]) / 32768; sum += value * value }
        let isSpeech: Bool
        do { isSpeech = try speechClassifier?.classify(converted) ?? false }
        catch {
            continuation?.finish(throwing: RouterError("Speech detection failed: \(error.localizedDescription)"))
            accepting = false
            return
        }
        let packet = AudioPacket(pcm: Data(bytes: samples, count: count * 2), level: sqrt(sum / Float(count)), isSpeech: isSpeech)
        if let player, let playback {
            guard scheduled < 20 else {
                continuation?.finish(throwing: RouterError("Virtual output stalled. Restart listening.")); accepting = false; return
            }
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: converted.frameLength)!
            output.frameLength = converted.frameLength
            for i in 0..<count { output.floatChannelData![0][i] = Float(samples[i]) / 32768 }
            scheduled += 1
            player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [weak self, weak playback] _ in
                self?.queue.async { [weak self, weak playback] in
                    guard let self, playback === self.playback else { return }
                    self.scheduled = max(0, self.scheduled - 1)
                }
            }
        }
        if case .dropped = continuation?.yield(packet) {
            continuation?.finish(throwing: RouterError("Audio processing cannot keep up. Listening stopped to prevent missing speech."))
            accepting = false
        }
    }

    private func observeConfiguration(of engine: AVAudioEngine) {
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.accepting else { return }
                self.accepting = false
                self.continuation?.finish(throwing: RouterError("Audio device configuration changed. Check the selected device and start listening again."))
            }
        }
    }

    private func startPlayback(device: AudioDevice) throws {
        let engine = AVAudioEngine()
        var id = device.id
        guard let unit = engine.outputNode.audioUnit,
              AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            throw RouterError("Could not open BlackHole. Check Audio MIDI Setup.")
        }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        try engine.start()
        node.play()
        observeConfiguration(of: engine)
        playback = engine; player = node
    }
}
