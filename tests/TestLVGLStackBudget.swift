import EmbeddedSwiftUI
import LVGLRendererAdaptor

@_silgen_name("test_run_with_stack_budget")
private func runWithStackBudget(_ workload: @convention(c) () -> Void, _ bytes: UInt) -> UInt

private func exerciseHostingController() {
    lv_init()
    guard let display = lv_display_create(240, 320) else {
        preconditionFailure("Display creation failed")
    }
    let controller = LVGLHostingController(display: display) {
        EmbeddedSwiftUIDemoView()
    }
    precondition(controller.present())
    for _ in 0..<8 {
        precondition(controller.handlePhysicalButton(.ok))
        lv_tick_inc(1000)
        _ = lv_timer_handler()
        precondition(controller.handlePhysicalButton(.down))
    }
    controller.unmount()
    lv_display_delete(display)
    lv_deinit()
}

@main
private struct TestLVGLStackBudget {
    static func main() {
        let budget: UInt = 16 * 1024
        let used = runWithStackBudget(exerciseHostingController, budget)
        precondition(used < budget)
        print("LVGL stack budget: PASS (\(used) / \(budget) bytes)")
    }
}
