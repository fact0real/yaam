import AudioToolbox
import CoreMedia
import Foundation
import ScreenCaptureKit
import FT8808Engine

/// Captures playback audio through ScreenCaptureKit. No microphone device is opened.
final class SystemAudioFT8Source: NSObject, AudioSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var sink: AsyncStream<AudioSlot>.Continuation?
    private var accumulator = SlotAccumulator(sampleRate: 12_000, slotSeconds: 15)
    private var started = false
    private var stopping = false
    private(set) var lastError: Error?

    func slots() -> AsyncStream<AudioSlot> {
        AsyncStream(AudioSlot.self, bufferingPolicy: .bufferingNewest(4)) { continuation in
            lock.withLock { sink = continuation }
            Task {
                do { try await startCapture() }
                catch {
                    lock.withLock { lastError = error }
                    continuation.finish()
                }
            }
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    private func startCapture() async throws {
        guard !lock.withLock({ stopping }) else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard !lock.withLock({ stopping }) else { return }
        guard let display = content.displays.first else {
            throw NSError(domain: "YAAM.WebSDR", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display is available for system audio capture."])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = false
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
        try capture.addStreamOutput(self, type: .audio,
                                    sampleHandlerQueue: DispatchQueue(label: "YAAM.WebSDR.SystemAudio"))
        let shouldStart = lock.withLock { () -> Bool in
            guard !stopping else { return false }
            stream = capture
            started = true
            return true
        }
        guard shouldStart else { return }
        try await capture.startCapture()
    }

    func stop() {
        let capture = lock.withLock { () -> SCStream? in
            guard !stopping else { return nil }
            stopping = true
            let current = stream
            stream = nil
            sink?.finish()
            sink = nil
            return current
        }
        if let capture {
            Task { try? await capture.stopCapture() }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { lastError = error }
        stop()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .audio, CMSampleBufferIsValid(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mChannelsPerFrame == 1 else { return }

        var list = AudioBufferList(mNumberBuffers: 1,
                                   mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        var retained: CMBlockBuffer?
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retained)
        guard result == noErr, let bytes = list.mBuffers.mData else { return }

        let count = Int(list.mBuffers.mDataByteSize) / Int(format.mBitsPerChannel / 8)
        guard count > 0 else { return }
        let raw: [Float]
        if format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let pointer = bytes.assumingMemoryBound(to: Float.self)
            raw = Array(UnsafeBufferPointer(start: pointer, count: count))
        } else if format.mBitsPerChannel == 16, format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            let pointer = bytes.assumingMemoryBound(to: Int16.self)
            raw = (0..<count).map { Float(pointer[$0]) / 32_768 }
        } else {
            return
        }

        let rate = Int(format.mSampleRate.rounded())
        let samples: [Float]
        if rate == 12_000 {
            samples = raw
        } else if rate == 48_000 {
            samples = stride(from: 0, through: raw.count - 4, by: 4).map { i in
                (raw[i] + raw[i + 1] + raw[i + 2] + raw[i + 3]) * 0.25
            }
        } else {
            return
        }
        let now = Date()
        lock.withLock {
            guard !stopping else { return }
            if let slot = accumulator.add(samples, at: now) { sink?.yield(slot) }
        }
    }
}
