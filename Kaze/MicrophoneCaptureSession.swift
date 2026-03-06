import Foundation
import AVFoundation
import CoreMedia

enum MicrophoneCaptureError: LocalizedError {
    case deviceUnavailable
    case inputCreationFailed
    case outputCreationFailed
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "The selected microphone is unavailable."
        case .inputCreationFailed:
            return "Kaze could not create a capture input for the selected microphone."
        case .outputCreationFailed:
            return "Kaze could not create a capture output for the selected microphone."
        case .unsupportedAudioFormat:
            return "Kaze received an unsupported audio format from the microphone."
        }
    }
}

final class MicrophoneCaptureSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    struct CapturedAudioChunk {
        let sampleBuffer: CMSampleBuffer
        let monoSamples: [Float]
        let sampleRate: Double
    }

    var onAudioChunk: ((CapturedAudioChunk) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.kaze.capture.session")
    private let sampleBufferQueue = DispatchQueue(label: "com.kaze.capture.samples")

    private var captureSession = AVCaptureSession()
    private var audioOutput = AVCaptureAudioDataOutput()
    private var deviceInput: AVCaptureDeviceInput?

    func start(deviceUID: String?) throws {
        var thrownError: Error?

        sessionQueue.sync {
            do {
                try configureSession(deviceUID: deviceUID)
                captureSession.startRunning()
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    func stop() {
        sessionQueue.sync {
            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }

            captureSession.beginConfiguration()
            if let deviceInput {
                captureSession.removeInput(deviceInput)
                self.deviceInput = nil
            }
            captureSession.removeOutput(audioOutput)
            captureSession.commitConfiguration()

            audioOutput = AVCaptureAudioDataOutput()
        }
    }

    private func configureSession(deviceUID: String?) throws {
        let device: AVCaptureDevice?
        if let deviceUID, !deviceUID.isEmpty {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices
            device = devices.first(where: { $0.uniqueID == deviceUID })
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }

        guard let device else {
            throw MicrophoneCaptureError.deviceUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw MicrophoneCaptureError.inputCreationFailed
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        captureSession.beginConfiguration()

        if let existingInput = deviceInput {
            captureSession.removeInput(existingInput)
            deviceInput = nil
        }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            throw MicrophoneCaptureError.inputCreationFailed
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(output) else {
            captureSession.removeInput(input)
            captureSession.commitConfiguration()
            throw MicrophoneCaptureError.outputCreationFailed
        }
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        deviceInput = input
        audioOutput = output
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            let (monoSamples, sampleRate) = try Self.extractMonoSamples(from: sampleBuffer)
            onAudioChunk?(CapturedAudioChunk(sampleBuffer: sampleBuffer, monoSamples: monoSamples, sampleRate: sampleRate))
        } catch {
            return
        }
    }

    private static func extractMonoSamples(from sampleBuffer: CMSampleBuffer) throws -> ([Float], Double) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }

        let asbd = asbdPointer.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }

        var blockBuffer: CMBlockBuffer?
        let audioBufferListSize = MemoryLayout<AudioBufferList>.size + (Int(asbd.mChannelsPerFrame) - 1) * MemoryLayout<AudioBuffer>.size
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: audioBufferListSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPointer.deallocate() }

        let audioBufferList = rawPointer.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }

        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        let channelCount = max(Int(asbd.mChannelsPerFrame), 1)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        var monoSamples = [Float](repeating: 0, count: frameCount)
        let bufferListPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

        if isFloat && asbd.mBitsPerChannel == 32 {
            if isNonInterleaved {
                for channel in 0..<min(channelCount, bufferListPointer.count) {
                    guard let data = bufferListPointer[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for frame in 0..<frameCount {
                        monoSamples[frame] += data[frame]
                    }
                }
            } else {
                guard let data = bufferListPointer.first?.mData?.assumingMemoryBound(to: Float.self) else {
                    throw MicrophoneCaptureError.unsupportedAudioFormat
                }
                for frame in 0..<frameCount {
                    let offset = frame * channelCount
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += data[offset + channel]
                    }
                    monoSamples[frame] = sum
                }
            }
        } else if isSignedInteger && asbd.mBitsPerChannel == 16 {
            if isNonInterleaved {
                for channel in 0..<min(channelCount, bufferListPointer.count) {
                    guard let data = bufferListPointer[channel].mData?.assumingMemoryBound(to: Int16.self) else { continue }
                    for frame in 0..<frameCount {
                        monoSamples[frame] += Float(data[frame]) / Float(Int16.max)
                    }
                }
            } else {
                guard let data = bufferListPointer.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                    throw MicrophoneCaptureError.unsupportedAudioFormat
                }
                for frame in 0..<frameCount {
                    let offset = frame * channelCount
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += Float(data[offset + channel]) / Float(Int16.max)
                    }
                    monoSamples[frame] = sum
                }
            }
        } else if isSignedInteger && asbd.mBitsPerChannel == 32 {
            if isNonInterleaved {
                for channel in 0..<min(channelCount, bufferListPointer.count) {
                    guard let data = bufferListPointer[channel].mData?.assumingMemoryBound(to: Int32.self) else { continue }
                    for frame in 0..<frameCount {
                        monoSamples[frame] += Float(data[frame]) / Float(Int32.max)
                    }
                }
            } else {
                guard let data = bufferListPointer.first?.mData?.assumingMemoryBound(to: Int32.self) else {
                    throw MicrophoneCaptureError.unsupportedAudioFormat
                }
                for frame in 0..<frameCount {
                    let offset = frame * channelCount
                    var sum: Float = 0
                    for channel in 0..<channelCount {
                        sum += Float(data[offset + channel]) / Float(Int32.max)
                    }
                    monoSamples[frame] = sum
                }
            }
        } else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }

        if channelCount > 1 {
            let divisor = Float(channelCount)
            for frame in 0..<frameCount {
                monoSamples[frame] /= divisor
            }
        }

        return (monoSamples, asbd.mSampleRate)
    }
}
