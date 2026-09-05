struct WiFiReconnectTimer {
    private static let retryDelaysMicroseconds: [UInt64] = [
        5_000_000,
        10_000_000,
        30_000_000,
        60_000_000,
    ]

    private(set) var consecutiveFailureCount = 0

    mutating func reset() {
        consecutiveFailureCount = 0
    }

    mutating func nextFireDelayMicroseconds() -> UInt64 {
        let delayIndex = min(
            consecutiveFailureCount,
            WiFiReconnectTimer.retryDelaysMicroseconds.count - 1
        )
        consecutiveFailureCount += 1
        return WiFiReconnectTimer.retryDelaysMicroseconds[delayIndex]
    }
}
