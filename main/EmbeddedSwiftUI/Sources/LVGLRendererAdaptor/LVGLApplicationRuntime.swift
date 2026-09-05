import EmbeddedSwiftUI

private var applicationTick: (() -> Void)?
private var applicationTimer: LVGLTimer?
private var applicationHealthTimer: LVGLTimer?
private var applicationLaunch: (() -> Void)?
private var applicationLaunchTimer: LVGLTimer?
private var applicationImageResolver: (String) -> UnsafeRawPointer? = { _ in nil }

public func setApplicationImageResolver(
    _ imageResolver: @escaping (String) -> UnsafeRawPointer?
) {
    applicationImageResolver = imageResolver
}

extension App {
    public static func main() {
        guard applicationTick == nil,
              applicationLaunch == nil,
              applicationLaunchTimer == nil else {
            return
        }
        guard bsp_lvgl_lock(1000) else { return }
        defer {
            bsp_lvgl_unlock()
        }
        runApp(Self.self)
    }
}

private func runApp<Application: App>(_ applicationType: Application.Type) {
    // `app_main` has ESP-IDF's small default task stack. Construct the App and
    // root View on the LVGL timer task, which owns the larger UI stack and
    // processes every subsequent input-triggered render.
    applicationLaunch = {
        guard let display = lv_display_get_default() else {
            print("EmbeddedSwiftUI display unavailable")
            return
        }
        let application = applicationType.init()
        let host = LVGLHostingController(
            display: display,
            imageResolver: applicationImageResolver
        ) {
            application.body
        }
        guard host.present() else {
            print("EmbeddedSwiftUI presentation failed")
            return
        }

        applicationTick = {
            var button: Int32 = 0
            var event: Int32 = 0
            // Embedded adaptation: drain the bounded hardware queue first and
            // coalesce all resulting State changes into one render. Scroll-only
            // actions remain immediate and do not rebuild the View tree.
            for _ in 0..<16 {
                guard passport_ui_poll_input(&button, &event) else { break }
                guard let physicalButton = PhysicalButton(bspValue: button),
                      event == 0 || (event == 3 && physicalButton != .ok) else {
                    continue
                }
                _ = host.processPhysicalButton(physicalButton)
            }
            if host.needsRender {
                _ = host.render()
            }
        }
        applicationTimer = LVGLTimer(period: 20) {
            applicationTick?()
        }
        applicationHealthTimer = LVGLTimer(period: 10000) {
            passport_ui_report_runtime()
        }
        if applicationTimer == nil {
            print("Input timer allocation failed")
        }
        passport_ui_report_runtime()
        print("EmbeddedSwiftUI application ready")
    }

    applicationLaunchTimer = LVGLTimer(period: 1) {
        let launch = applicationLaunch
        applicationLaunch = nil
        applicationLaunchTimer?.invalidate()
        applicationLaunchTimer = nil
        launch?()
    }
    if applicationLaunchTimer == nil {
        applicationLaunch = nil
        print("EmbeddedSwiftUI launch timer allocation failed")
    }
}
