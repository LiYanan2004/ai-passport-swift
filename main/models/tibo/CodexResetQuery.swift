struct CodexResetQuery: Equatable {
    enum ServiceState: Equatable {
        case waiting
        case ready
        case error
    }

    struct ScheduledReset: Equatable {
        let scheduledForText: String?
    }

    struct ActiveWatch: Equatable {
        let resetChancePercent: Int?
        let forecastText: String?
    }

    enum TiboResetStatus: Equatable {
        case waitingForData
        case confirmed
        case announced
        case normal
        case unavailable

        static let confirmedDisplayDurationHours = 24.0

        static func resolve(
            serviceState: ServiceState,
            scheduledReset: ScheduledReset?,
            activeWatch: ActiveWatch?,
            hoursSinceLastReset: Double?
        ) -> TiboResetStatus {
            guard serviceState == .ready else {
                return serviceState == .error ? .unavailable : .waitingForData
            }
            if scheduledReset != nil || activeWatch != nil {
                return .announced
            }
            if let hoursSinceLastReset,
               hoursSinceLastReset >= 0,
               hoursSinceLastReset <= confirmedDisplayDurationHours {
                return .confirmed
            }
            return .normal
        }
    }

    let revision: UInt32
    let serviceState: ServiceState
    let isStale: Bool
    let scheduledReset: ScheduledReset?
    let activeWatch: ActiveWatch?
    let hoursSinceLastReset: Double?
    let totalResetCount: Int?
    let lastHTTPStatus: Int?
    let lastResetText: String?
    let latestPostText: String?
    let sourceAuthor: String?

    static let waiting = CodexResetQuery(
        revision: 0,
        serviceState: .waiting,
        isStale: false,
        scheduledReset: nil,
        activeWatch: nil,
        hoursSinceLastReset: nil,
        totalResetCount: nil,
        lastHTTPStatus: nil,
        lastResetText: nil,
        latestPostText: nil,
        sourceAuthor: nil
    )

    var status: TiboResetStatus {
        TiboResetStatus.resolve(
            serviceState: serviceState,
            scheduledReset: scheduledReset,
            activeWatch: activeWatch,
            hoursSinceLastReset: hoursSinceLastReset
        )
    }

    static func == (left: CodexResetQuery, right: CodexResetQuery) -> Bool {
        left.revision == right.revision
    }
}
