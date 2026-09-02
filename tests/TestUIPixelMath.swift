@main
struct UIPixelMathTests {
    static func main() {
        precondition(pixelBlinkFrame(1_650))
        precondition(pixelBlinkFrame(1_799))
        precondition(!pixelBlinkFrame(1_800))
        precondition(!pixelBlinkFrame(1_649))
        precondition(pixelJumpOffset(0) == 0)
        precondition(pixelJumpOffset(1) == -3)
        precondition(pixelJumpOffset(2) == -5)
        precondition(pixelJumpOffset(3) == -3)
        precondition(pixelJumpOffset(4) == 0)
    }
}
