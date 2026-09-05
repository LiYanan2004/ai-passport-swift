@main
struct CodexResetQueryStatusTests {
    static func main() {
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .waiting,
                scheduledReset: nil,
                activeWatch: nil,
                hoursSinceLastReset: nil
            ) == .waitingForData
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .error,
                scheduledReset: nil,
                activeWatch: nil,
                hoursSinceLastReset: nil
            ) == .unavailable
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .ready,
                scheduledReset: CodexResetQuery.ScheduledReset(scheduledForText: nil),
                activeWatch: nil,
                hoursSinceLastReset: 2
            ) == .announced
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .ready,
                scheduledReset: nil,
                activeWatch: CodexResetQuery.ActiveWatch(
                    resetChancePercent: nil,
                    forecastText: nil
                ),
                hoursSinceLastReset: 48
            ) == .announced
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .ready,
                scheduledReset: nil,
                activeWatch: nil,
                hoursSinceLastReset: 24
            ) == .confirmed
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .ready,
                scheduledReset: nil,
                activeWatch: nil,
                hoursSinceLastReset: 24.01
            ) == .normal
        )
        precondition(
            CodexResetQuery.TiboResetStatus.resolve(
                serviceState: .ready,
                scheduledReset: nil,
                activeWatch: nil,
                hoursSinceLastReset: nil
            ) == .normal
        )
        precondition(
            TiboResetDate.gmt8Display(fromISO8601: "2026-09-12T08:09:17.000Z") ==
                "SEP 12  16:09 GMT+8"
        )
        precondition(
            TiboResetDate.gmt8Display(fromISO8601: "2026-12-31T20:05:00.000Z") ==
                "JAN 1  04:05 GMT+8"
        )
        precondition(TiboResetDate.gmt8Display(fromISO8601: nil) == nil)
        precondition(
            TiboResetDate.hours(
                from: "2026-09-12T08:09:17.000Z",
                to: "2026-09-13T09:45:17.000Z"
            ) == 25.6
        )
        precondition(TiboResetDate.hours(from: nil, to: nil) == nil)
    }
}
