#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import EmbeddedSwiftUI
import LVGLRendererAdaptor

@_silgen_name("test_begin_allocation_recording")
private func beginAllocationRecording()

@_silgen_name("test_end_allocation_recording")
private func endAllocationRecording() -> UInt

@main
private struct TestLVGLMemoryBudget {
    static func main() {
        lv_init()
        guard let display = lv_display_create(240, 320),
              let screen = lv_obj_create(nil) else {
            preconditionFailure("Display creation failed")
        }
        lv_screen_load(screen)
        checkConstructionCommandsAreConsumed()
        checkMetadataAllocations(in: screen)
        checkCombinedApplication(on: display, fallbackScreen: screen)
        checkLiveConnectivityStatus(on: display, fallbackScreen: screen)
        checkWiFiConnectingAnimation(on: display, fallbackScreen: screen)
        lv_obj_delete(screen)
        lv_display_delete(display)
        lv_deinit()
        print("LVGL memory regression: PASS")
    }

    private static func checkConstructionCommandsAreConsumed() {
        let backend = LVGLRenderBackend()
        var displayList = DisplayList(commands: [
            .text("A", RenderEnvironment()),
            .text("B", RenderEnvironment()),
        ])
        var layout = DisplayListLayout(
            provider: backend.layoutProvider, transaction: Transaction(), previousAnimations: [:]
        )
        precondition(layout.updateConsuming(
            &displayList,
            size: EmbeddedSize(width: 12, height: 24),
            alignment: .center,
            version: DisplayList.Version()
        ) != nil)
        precondition(displayList.commands.isEmpty)
    }

    private static func checkMetadataAllocations(in screen: OpaquePointer) {
        var backend = LVGLRenderBackend()
        let transaction = Transaction(animation: .easeInOut(duration: 0.49))
        let layout = ContainerLayout.frame(width: 12, height: 12, alignment: .center)
        var displayListLayout = DisplayListLayout(
            provider: backend.layoutProvider, transaction: transaction, previousAnimations: [:]
        )
        let item = displayListLayout.update(
            DisplayList(commands: [.text("A", RenderEnvironment())]),
            size: EmbeddedSize(width: 12, height: 12), alignment: .center,
            version: DisplayList.Version()
        )!.displayList.items[0]
        let root = backend.makeContainer(
            layout, proposedSize: RenderSize(width: 12, height: 12), parent: screen
        )!
        beginAllocationRecording()
        for _ in 0..<64 {
            let node = backend.makeContainer(
                layout, proposedSize: RenderSize(width: 12, height: 12), parent: root
            )!
            backend.configure(node, item: item)
        }
        let largest = endAllocationRecording()
        print("LVGL metadata largest allocation: \(largest) bytes")
        fflush(nil)
        // Pointer/identity tables fit; one full Transaction per bucket does not.
        precondition(largest > 0 && largest <= 4096)
        backend.removeAll(from: root)
    }

    private static func checkCombinedApplication(
        on display: OpaquePointer,
        fallbackScreen: OpaquePointer
    ) {
        let initialTimerCount = timerCount()
        let controller = LVGLHostingController(display: display) {
            DouyinDoubleBallLoadingView()
            EmbeddedSwiftUIDemoView()
        }
        precondition(controller.present())
        let contentRoot = lv_obj_get_child(lv_display_get_screen_active(display)!, 0)!
        precondition(timerCount() == initialTimerCount)
        precondition(controller.needsRender)
        precondition(controller.render())
        precondition(lv_anim_count_running() > 0)

        lv_tick_inc(245)
        _ = lv_timer_handler()
        precondition(hasIntermediateScale(in: contentRoot))

        for cycle in 0..<40 {
            lv_tick_inc(50)
            _ = lv_timer_handler()
            if controller.needsRender {
                precondition(controller.render())
            }
            precondition(lv_anim_count_running() > 0)
            if cycle % 8 == 0 {
                precondition(controller.handlePhysicalButton(.down))
            }
            precondition(lv_obj_get_child_count(contentRoot) <= 2)
        }
        lv_screen_load(fallbackScreen)
        controller.unmount()
        precondition(timerCount() == initialTimerCount)
        precondition(lv_anim_count_running() == 0)
        lv_tick_inc(1000)
        _ = lv_timer_handler()
    }

    private static func checkLiveConnectivityStatus(
        on display: OpaquePointer,
        fallbackScreen: OpaquePointer
    ) {
        let initialTimerCount = timerCount()
        let controller = LVGLHostingController(display: display) {
            LiveConnectivityStatusView()
        }
        precondition(controller.present())
        precondition(timerCount() == initialTimerCount + 1)

        lv_screen_load(fallbackScreen)
        controller.unmount()
        precondition(timerCount() == initialTimerCount)
    }

    private static func checkWiFiConnectingAnimation(
        on display: OpaquePointer,
        fallbackScreen: OpaquePointer
    ) {
        let controller = LVGLHostingController(display: display) {
            LiveConnectivityStatusView.ConnectivityStatusView(
                batteryLevel: 0.5,
                bluetoothStatus: .poweredOn,
                wifiSignalStrength: 0,
                wifiConnectionState: .connecting
            )
            .frame(width: 64, height: 64)
        }
        precondition(controller.present())
        precondition(controller.needsRender)
        precondition(controller.render())
        precondition(lv_anim_count_running() == 4)

        lv_screen_load(fallbackScreen)
        controller.unmount()
        precondition(lv_anim_count_running() == 0)
    }

    private static func hasIntermediateScale(in root: OpaquePointer) -> Bool {
        var pending = [root]
        while let node = pending.popLast() {
            let scale = lv_obj_get_style_transform_scale_x(node, LV_PART_MAIN)
            if scale > 184 && scale < 302 {
                return true
            }
            for index in 0..<lv_obj_get_child_count(node) {
                if let child = lv_obj_get_child(node, Int32(index)) {
                    pending.append(child)
                }
            }
        }
        return false
    }

    private static func timerCount() -> Int {
        var count = 0
        var timer = lv_timer_get_next(nil)
        while let current = timer {
            count += 1
            timer = lv_timer_get_next(current)
        }
        return count
    }
}
