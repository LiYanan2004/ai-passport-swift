@main
struct AgentMonitorUsageStateTests {
    static func main() {
        let unavailable = AgentMonitorUsageUpdate(
            availability: 0,
            fiveHourUsedPercent: 0,
            weeklyUsedPercent: 0,
            resetCount: 0
        )
        precondition(unavailable.fiveHourUsedPercent == nil)
        precondition(unavailable.weeklyUsedPercent == nil)
        precondition(unavailable.resetCount == nil)

        let fiveHourOnly = AgentMonitorUsageUpdate(
            availability: AgentMonitorUsageUpdate.fiveHourWindowAvailable,
            fiveHourUsedPercent: 42,
            weeklyUsedPercent: 0,
            resetCount: 0
        )
        precondition(fiveHourOnly.fiveHourUsedPercent == 42)
        precondition(fiveHourOnly.weeklyUsedPercent == nil)
        precondition(fiveHourOnly.resetCount == nil)

        let complete = AgentMonitorUsageUpdate(
            availability: AgentMonitorUsageUpdate.fiveHourWindowAvailable |
                AgentMonitorUsageUpdate.weeklyWindowAvailable |
                AgentMonitorUsageUpdate.resetCountAvailable,
            fiveHourUsedPercent: 101,
            weeklyUsedPercent: 78,
            resetCount: 3
        )
        precondition(complete.fiveHourUsedPercent == 100)
        precondition(complete.weeklyUsedPercent == 78)
        precondition(complete.resetCount == 3)
    }
}
