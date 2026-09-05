import EmbeddedSwiftUI
import LVGLRendererAdaptor

@main
private struct TestLVGLAnimationTiming {
    static func main() {
        precondition(Animation.linear(duration: 120).effectiveDurationMilliseconds == 120_000)
        precondition(Animation.linear.delay(90).delayMilliseconds == 90_000)
        let delayed = Animation.linear(duration: 120).delay(90).repeatCount(3).speed(2)
        precondition(delayed.effectiveDurationMilliseconds == 60_000)
        precondition(delayed.delayMilliseconds == 45_000)
        precondition(delayed.repeatDelayMilliseconds == 45_000)
        precondition(delayed.repeatCountValue == 3)
        let outerDelay = Animation.linear(duration: 120).repeatForever().delay(90)
        precondition(outerDelay.delayMilliseconds == 90_000)
        precondition(outerDelay.repeatDelayMilliseconds == 0)
        precondition(outerDelay.repeatCountValue == -1)
        precondition(Animation.linear(duration: 0).effectiveDurationMilliseconds == 0)
        precondition(Animation.linear(duration: 1).speed(2).effectiveDurationMilliseconds == 500)
        print("LVGL animation timing: PASS")
    }
}
