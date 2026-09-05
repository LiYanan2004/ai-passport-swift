//
//  ContentView.swift
//  PassportMirroring
//
//  Created by Yanan Li on 2026/9/7.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = MirrorDisplayModel()
    @Namespace private var screen
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Group {
                if model.connectionState == .disconnected {
                    DeviceDisconnectedView(reconnect: reconnect)
                } else {
                    Image(.aiPassport)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .alignmentGuide(.passportHorizontalDisplayCenter) { $0.width * 268 / 570 }
                        .alignmentGuide(.passportVerticalDisplayCenter) { $0.height * 334 / 973 }
                        .background(alignment: .aiPassportDisplayCenter) {
                            let scale = 306.0 / 570.0
                            ZStack {
                                LinearGradient(colors: [Color(#colorLiteral(red: 0.3752459288, green: 0.855856359, blue: 1, alpha: 1)), Color(#colorLiteral(red: 0.5669380426, green: 0.9957421422, blue: 0.651568234, alpha: 1))], startPoint: .topTrailing, endPoint: .bottomLeading)

                                if colorScheme == .dark {
                                    Color.black.opacity(0.25)
                                }
                                
                                Group {
                                    if model.connectionState == .connected, let image = model.image {
                                        Image(decorative: image, scale: 2)
                                            .resizable()
                                            .interpolation(.medium)
                                            .aspectRatio(3.0 / 4.0, contentMode: .fill)
                                    } else {
                                        DeviceConnectingLabel(isConnected: model.isConnected)
                                            .visualEffect { [screen] content, proxy in
                                                content.scaleEffect(
                                                    proxy.bounds(of: .named(screen)).map({
                                                        $0.size.width * scale / proxy.size.width * /* margins */ 0.9
                                                    }) ?? 1
                                                )
                                            }
                                    }
                                }
                                .transition(.blurReplace(.downUp).combined(with: .scale(1.25)))
                            }
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .scaleEffect(scale)
                            .coordinateSpace(.named(screen))
                            .alignmentGuide(.passportHorizontalDisplayCenter) { $0[HorizontalAlignment.center] }
                            .alignmentGuide(.passportVerticalDisplayCenter) { $0[VerticalAlignment.center] }
                        }
                }
            }
            .transition(.blurReplace.combined(with: .scale(0.85)))
        }
        .padding()
        .toolbar(content: toolbarContent)
        .toolbar(removing: .title)
        .alert(
            "Capture Failed",
            isPresented: Binding(
                get: { model.captureErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.captureErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                model.captureErrorMessage = nil
            }
        } message: {
            Text(model.captureErrorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: model.completedRecordingURL) { _, url in
            guard url != nil else { return }
            chooseRecordingDestination()
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .task(id: model.connectionState) {
            guard model.connectionState == .connecting else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  model.connectionState == .connecting,
                  !model.isConnected else {
                return
            }
            model.stopReconnectAttempt()
        }
    }

    private func reconnect() {
        withAnimation(.smooth(duration: 0.75)) {
            model.reconnect()
        }
    }
    
    struct DeviceConnectingLabel: View {
        let isConnected: Bool

        @State private var progress = 0.0
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            VStack {
                Text("Connecting")
                    .font(.callout)
                    .foregroundStyle(.regularMaterial)
                    .colorScheme(colorScheme == .dark ? .light : .dark)

                Text("AI Passport")
                    .foregroundStyle(.regularMaterial)
                    .colorScheme(colorScheme == .dark ? .light : .dark)
                    .overlay {
                        Text("AI Passport")
                            .mask {
                                Rectangle()
                                    .visualEffect { [progress] content, proxy in
                                        content.offset(y: proxy.size.height * (1 - progress))
                                    }
                            }
                    }
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .task {
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.smooth(duration: 3)) {
                    progress = 0.5
                }
            }
            .onChange(of: isConnected) {
                guard isConnected else { return }

                withAnimation(.smooth(duration: 0.5)) {
                    progress = 1
                }
            }
        }
    }
    
    struct DeviceDisconnectedView: View {
        let reconnect: () -> Void
        
        var body: some View {
            VStack(spacing: 16) {
                Image(.aiPassport)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.cyan.gradient)
                            .padding(3)
                    }
                
                Text("Device Disconnected")
                    .font(.title3.bold())
                
                Text("Make sure you connect your device with USB-C cable and the port is not occupied.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Reconnect") {
                    reconnect()
                }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
    }
}

extension ContentView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarSpacer(.flexible)

        ToolbarItemGroup {
            Button("Take Screenshot", systemImage: "camera") {
                takeScreenshot()
            }
            .help("Take Screenshot")
            .disabled(model.image == nil)

            Button(
                recordingButtonTitle,
                systemImage: recordingButtonImage
            ) {
                if model.isRecording {
                    model.stopRecording()
                } else {
                    model.startRecording()
                }
            }
            .foregroundStyle(model.isRecording ? Color.red : Color.primary)
            .help(recordingButtonTitle)
            .disabled(
                model.image == nil
                    || model.isFinishingRecording
                    || model.completedRecordingURL != nil
            )
        }
        .hidden(model.connectionState != .connected)

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Stop Mirroring", systemImage: "pause.fill") {
                model.toggleFlashMode()
            }
            .disabled(model.connectionState != .connected)
        }
        .hidden(model.connectionState != .connected)
    }

    private func takeScreenshot() {
        guard let image = model.image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Passport-\(captureTimestamp()).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.saveScreenshot(image, to: url)
        }
    }

    private func chooseRecordingDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Passport-\(captureTimestamp()).mov"
        panel.begin { response in
            model.resolveCompletedRecording(
                to: response == .OK ? panel.url : nil
            )
        }
    }

    private var recordingButtonTitle: String {
        if model.isRecording {
            "Stop Recording"
        } else if model.isFinishingRecording {
            "Finishing Recording"
        } else {
            "Start Recording"
        }
    }

    private var recordingButtonImage: String {
        if model.isRecording {
            "stop.circle.fill"
        } else if model.isFinishingRecording {
            "hourglass"
        } else {
            "record.circle"
        }
    }

    private func captureTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

#Preview {
    ContentView()
}
