@preconcurrency import AVFoundation
import AppKit

private final class SendableAssetWriter: @unchecked Sendable {
    let value: AVAssetWriter

    init(_ value: AVAssetWriter) {
        self.value = value
    }
}

@MainActor
final class MirrorMediaCapture {
    private static let temporaryRecordingPrefix = "PassportMirroring-"

    enum CaptureError: LocalizedError {
        case imageEncodingFailed
        case recordingConfigurationFailed
        case recordingStartFailed(Error?)
        case recordingFinishFailed(Error?)
        case pixelBufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed:
                "The screenshot could not be encoded."
            case .recordingConfigurationFailed:
                "The video recorder could not be configured."
            case let .recordingStartFailed(error):
                error?.localizedDescription ?? "The video recorder could not start."
            case let .recordingFinishFailed(error):
                error?.localizedDescription ?? "The video recording could not be finished."
            case .pixelBufferCreationFailed:
                "The current frame could not be added to the recording."
            }
        }
    }

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: TimeInterval?
    private var lastPresentationTime = CMTime.invalid
    private var recordingURL: URL?

    var isRecording: Bool {
        assetWriter != nil
    }

    init() {
        removeStaleTemporaryRecordings()
    }

    func saveScreenshot(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.imageEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    func startRecording(
        initialPixels: Data,
        at uptime: TimeInterval
    ) throws {
        guard assetWriter == nil else { return }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(Self.temporaryRecordingPrefix)\(UUID().uuidString).mov")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: MirrorStreamDecoder.width,
                    AVVideoHeightKey: MirrorStreamDecoder.height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 1_000_000,
                        AVVideoExpectedSourceFrameRateKey: 30,
                        AVVideoMaxKeyFrameIntervalKey: 60,
                    ],
                ]
            )
            input.expectsMediaDataInRealTime = true

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: MirrorStreamDecoder.width,
                    kCVPixelBufferHeightKey as String: MirrorStreamDecoder.height,
                ]
            )

            guard writer.canAdd(input) else {
                throw CaptureError.recordingConfigurationFailed
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw CaptureError.recordingStartFailed(writer.error)
            }
            writer.startSession(atSourceTime: .zero)

            assetWriter = writer
            assetWriterInput = input
            pixelBufferAdaptor = adaptor
            recordingStartTime = uptime
            lastPresentationTime = .invalid
            recordingURL = url

            do {
                try appendFrame(initialPixels, at: uptime)
            } catch {
                input.markAsFinished()
                writer.cancelWriting()
                resetRecordingState()
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func appendFrame(_ pixels: Data, at uptime: TimeInterval) throws {
        guard let input = assetWriterInput,
              let adaptor = pixelBufferAdaptor,
              let recordingStartTime,
              input.isReadyForMoreMediaData else {
            return
        }

        let presentationTime = CMTime(
            seconds: max(0, uptime - recordingStartTime),
            preferredTimescale: 600
        )
        guard !lastPresentationTime.isValid
                || CMTimeCompare(presentationTime, lastPresentationTime) > 0 else {
            return
        }

        let pixelBuffer = try makePixelBuffer(from: pixels)
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw CaptureError.recordingStartFailed(assetWriter?.error)
        }
        lastPresentationTime = presentationTime
    }

    func stopRecording(
        finalPixels: Data?,
        at uptime: TimeInterval,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        guard let writer = assetWriter,
              let input = assetWriterInput,
              let recordingStartTime,
              let recordingURL else {
            completion(.failure(CaptureError.recordingFinishFailed(nil)))
            return
        }

        var appendError: Error?
        if let finalPixels {
            do {
                try appendFrame(finalPixels, at: uptime)
            } catch {
                appendError = error
            }
        }

        let endTime = CMTime(
            seconds: max(0, uptime - recordingStartTime),
            preferredTimescale: 600
        )
        input.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        resetRecordingState()

        let sendableWriter = SendableAssetWriter(writer)
        writer.finishWriting {
            let error = appendError ?? sendableWriter.value.error
            if error != nil {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            Task { @MainActor in
                if let error {
                    completion(.failure(CaptureError.recordingFinishFailed(error)))
                } else {
                    completion(.success(recordingURL))
                }
            }
        }
    }

    private func makePixelBuffer(from pixels: Data) throws -> CVPixelBuffer {
        let expectedByteCount = MirrorStreamDecoder.width
            * MirrorStreamDecoder.height * 4
        guard pixels.count == expectedByteCount else {
            throw CaptureError.pixelBufferCreationFailed
        }

        var optionalPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            MirrorStreamDecoder.width,
            MirrorStreamDecoder.height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ] as CFDictionary,
            &optionalPixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalPixelBuffer else {
            throw CaptureError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureError.pixelBufferCreationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        pixels.withUnsafeBytes { sourceBytes in
            guard let sourceAddress = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            let destinationAddress = baseAddress.assumingMemoryBound(to: UInt8.self)
            for row in 0..<MirrorStreamDecoder.height {
                let sourceRow = sourceAddress + row * MirrorStreamDecoder.width * 4
                let destinationRow = destinationAddress + row * bytesPerRow
                for column in 0..<MirrorStreamDecoder.width {
                    let sourcePixel = sourceRow + column * 4
                    let destinationPixel = destinationRow + column * 4
                    destinationPixel[0] = sourcePixel[2]
                    destinationPixel[1] = sourcePixel[1]
                    destinationPixel[2] = sourcePixel[0]
                    destinationPixel[3] = sourcePixel[3]
                }
            }
        }
        return pixelBuffer
    }

    private func resetRecordingState() {
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        recordingStartTime = nil
        lastPresentationTime = .invalid
        recordingURL = nil
    }

    private func removeStaleTemporaryRecordings() {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let urls = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where url.lastPathComponent.hasPrefix(Self.temporaryRecordingPrefix)
                && url.pathExtension == "mov" {
            try? fileManager.removeItem(at: url)
        }
    }
}
