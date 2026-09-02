func pixelBlinkFrame(_ elapsedMilliseconds: UInt32) -> Bool {
    let phase = elapsedMilliseconds % 2_000
    return phase >= 1_650 && phase < 1_800
}

func pixelJumpOffset(_ frame: UInt) -> Int32 {
    switch frame {
    case 0: return 0
    case 1: return -3
    case 2: return -5
    case 3: return -3
    default: return 0
    }
}
