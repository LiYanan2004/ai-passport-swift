//
//  PassportMirroringApp.swift
//  PassportMirroring
//
//  Created by Yanan Li on 2026/9/7.
//

import AppKit
import SwiftUI

@main
struct PassportMirroringApp: App {
    var body: some Scene {
        Window("Passport Mirroring", id: "mirror") {
            NavigationStack {
                ContentView()
            }
            .frame(minHeight: 300)
            .background {
                WindowContentAspectRatio(
                    width: 3,
                    height: 5,
                    initialContentSize: NSSize(width: 315, height: 525)
                )
            }
            .containerBackground(.regularMaterial, for: .window)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .defaultSize(width: 315, height: 525)
    }
}

private struct WindowContentAspectRatio: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    let initialContentSize: NSSize

    func makeNSView(context: Context) -> WindowContentAspectRatioView {
        WindowContentAspectRatioView(
            contentAspectRatio: NSSize(width: width, height: height),
            initialContentSize: initialContentSize
        )
    }

    func updateNSView(
        _ nsView: WindowContentAspectRatioView,
        context: Context
    ) {
        let contentAspectRatio = NSSize(width: width, height: height)
        guard nsView.contentAspectRatio != contentAspectRatio else {
            return
        }

        nsView.contentAspectRatio = contentAspectRatio
        nsView.applyContentAspectRatio()
    }
}

private final class WindowContentAspectRatioView: NSView {
    var contentAspectRatio: NSSize
    let initialContentSize: NSSize
    private weak var configuredWindow: NSWindow?

    init(contentAspectRatio: NSSize, initialContentSize: NSSize) {
        self.contentAspectRatio = contentAspectRatio
        self.initialContentSize = initialContentSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyContentAspectRatio()

        guard let window, configuredWindow !== window else {
            return
        }

        configuredWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else {
                return
            }

            self.applyContentAspectRatio()
            self.normalizeContentSize(of: window)
        }
    }

    func applyContentAspectRatio() {
        guard let window, window.contentAspectRatio != contentAspectRatio else {
            return
        }

        window.contentAspectRatio = contentAspectRatio
    }

    private func normalizeContentSize(of window: NSWindow) {
        let contentSize = window.contentRect(forFrameRect: window.frame).size

        guard abs(contentSize.width - initialContentSize.width) > 0.5
                || abs(contentSize.height - initialContentSize.height) > 0.5 else {
            return
        }

        window.setContentSize(initialContentSize)
    }
}
