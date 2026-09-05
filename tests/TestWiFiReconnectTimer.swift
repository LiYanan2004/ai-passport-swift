@main
struct WiFiReconnectTimerTests {
    static func main() {
        var reconnectTimer = WiFiReconnectTimer()
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 5_000_000)
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 10_000_000)
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 30_000_000)
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 60_000_000)
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 60_000_000)

        reconnectTimer.reset()
        precondition(reconnectTimer.consecutiveFailureCount == 0)
        precondition(reconnectTimer.nextFireDelayMicroseconds() == 5_000_000)
    }
}
