//
//  MirrorDisplayModel.swift
//  PassportMirroring
//
//  Created by Yanan Li on 2026/9/8.
//

import Foundation
import SwiftUI

enum MirrorConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

@MainActor @Observable
final class MirrorDisplayModel {
    private(set) var image: CGImage?
    private(set) var isRecording = false
    private(set) var isFinishingRecording = false
    private(set) var completedRecordingURL: URL?
    var captureErrorMessage: String?
    private(set) var isConnected = false {
        willSet {
            guard newValue != isConnected else { return }
            if newValue {
                connectedStateTask?.cancel()
                connectedStateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled, let self, self.isConnected else { return }
                    self.connectedStateTask = nil
                    withAnimation(.smooth(duration: 0.5)) {
                        self.connectionState = .connected
                    }
                }
            } else {
                finishRecording(shouldOfferSave: true)
                connectedStateTask?.cancel()
                connectedStateTask = nil
                withAnimation(.smooth(duration: 0.75)) {
                    connectionState = .disconnected
                }
            }
        }
    }
    private(set) var connectionState = MirrorConnectionState.connecting
    @ObservationIgnored private var receiver: USBMirrorReceiver?
    @ObservationIgnored private var frameContinuation: AsyncStream<Data?>.Continuation?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var connectedStateTask: Task<Void, Never>?
    @ObservationIgnored private var latestPixels: Data?
    @ObservationIgnored private let mediaCapture = MirrorMediaCapture()
    @ObservationIgnored private var shouldOfferRecordingSave = true

    func start() {
        guard receiver == nil else { return }
        isConnected = false

        withAnimation(.smooth(duration: 0.75)) {
            connectionState = .connecting
        }

        let (frames, continuation) = AsyncStream<Data?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        frameContinuation = continuation
        frameTask = Task { @MainActor [weak self] in
            for await pixels in frames {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                guard let pixels,
                      pixels.count == MirrorStreamDecoder.width * MirrorStreamDecoder.height * 4,
                      let provider = CGDataProvider(data: pixels as CFData) else {
                    continue
                }
                latestPixels = pixels
                image = CGImage(width: MirrorStreamDecoder.width,
                    height: MirrorStreamDecoder.height, bitsPerComponent: 8,
                    bitsPerPixel: 32, bytesPerRow: MirrorStreamDecoder.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                        CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
                    ),
                    provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent)
                if isRecording {
                    do {
                        try mediaCapture.appendFrame(
                            pixels,
                            at: ProcessInfo.processInfo.systemUptime
                        )
                    } catch {
                        finishRecording(shouldOfferSave: false)
                        captureErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        let receiver = USBMirrorReceiver(
            receiveFrame: { pixels in
                continuation.yield(pixels)
            },
            receiveConnectionState: { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.receiver != nil,
                          self.connectionState != .disconnected else {
                        return
                    }
                    self.isConnected = state == .connected
                }
            }
        )
        self.receiver = receiver
        receiver.start()
    }

    func stop() {
        discardCompletedRecording()
        finishRecording(shouldOfferSave: false)
        receiver?.stop()
        receiver = nil
        frameContinuation?.finish()
        frameContinuation = nil
        frameTask?.cancel()
        frameTask = nil
        connectedStateTask?.cancel()
        connectedStateTask = nil
        latestPixels = nil
        image = nil
        isConnected = false
        connectionState = .disconnected
    }

    func toggleFlashMode() {
        guard let receiver, connectionState == .connected else { return }
        isConnected = false
        connectionState = .disconnected
        receiver.setPausedForFlashing(true) {}
    }

    func reconnect() {
        guard let receiver, connectionState == .disconnected else { return }
        isConnected = false
        connectionState = .connecting
        receiver.setPausedForFlashing(false) {
            receiver.reconnect()
        }
    }

    func stopReconnectAttempt() {
        guard connectionState == .connecting else { return }
        connectedStateTask?.cancel()
        connectedStateTask = nil
        isConnected = false
        receiver?.stopReconnectAttempt()
        withAnimation(.smooth(duration: 0.75)) {
            connectionState = .disconnected
        }
    }

    func saveScreenshot(_ image: CGImage, to url: URL) {
        do {
            try mediaCapture.saveScreenshot(image, to: url)
        } catch {
            captureErrorMessage = error.localizedDescription
        }
    }

    func startRecording() {
        guard !isRecording,
              !isFinishingRecording,
              completedRecordingURL == nil,
              let latestPixels else {
            return
        }
        do {
            try mediaCapture.startRecording(
                initialPixels: latestPixels,
                at: ProcessInfo.processInfo.systemUptime
            )
            isRecording = true
        } catch {
            captureErrorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        finishRecording(shouldOfferSave: true)
    }

    func resolveCompletedRecording(to destinationURL: URL?) {
        guard let sourceURL = completedRecordingURL else { return }
        completedRecordingURL = nil

        guard let destinationURL else {
            try? FileManager.default.removeItem(at: sourceURL)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            captureErrorMessage = error.localizedDescription
        }
    }

    private func discardCompletedRecording() {
        guard let completedRecordingURL else { return }
        self.completedRecordingURL = nil
        try? FileManager.default.removeItem(at: completedRecordingURL)
    }

    private func finishRecording(shouldOfferSave: Bool) {
        shouldOfferRecordingSave = shouldOfferSave
        guard isRecording else { return }
        isRecording = false
        isFinishingRecording = true
        mediaCapture.stopRecording(
            finalPixels: latestPixels,
            at: ProcessInfo.processInfo.systemUptime
        ) { [self] result in
            isFinishingRecording = false
            switch result {
            case let .success(url):
                if shouldOfferRecordingSave {
                    completedRecordingURL = url
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            case let .failure(error):
                captureErrorMessage = error.localizedDescription
            }
        }
    }
}
