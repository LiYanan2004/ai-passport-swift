@main
struct UIPixelMathTests {
    static func main() {
        precondition(UIPixelAnimation.isBlinkFrame(elapsedMilliseconds: 1_650))
        precondition(UIPixelAnimation.isBlinkFrame(elapsedMilliseconds: 1_799))
        precondition(!UIPixelAnimation.isBlinkFrame(elapsedMilliseconds: 1_800))
        precondition(!UIPixelAnimation.isBlinkFrame(elapsedMilliseconds: 1_649))
        precondition(UIPixelAnimation.jumpOffset(frame: 0) == 0)
        precondition(UIPixelAnimation.jumpOffset(frame: 1) == -3)
        precondition(UIPixelAnimation.jumpOffset(frame: 2) == -5)
        precondition(UIPixelAnimation.jumpOffset(frame: 3) == -3)
        precondition(UIPixelAnimation.jumpOffset(frame: 4) == 0)
    }
}
