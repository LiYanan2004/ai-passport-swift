@main
struct AgentMonitorStateTests {
    static func main() {
        var store = AgentMonitorSessionStore()
        let sessionA: UInt64 = 0xA000_0000_0000_0001
        let sessionB: UInt64 = 0xB000_0000_0000_0002
        let first = AgentMonitorUpdate(
            sessionID: sessionA,
            state: .running,
            title: "CODEX",
            detail: "Bash"
        )
        precondition(store.apply(first) == .none)
        precondition(store.sessions.count == 1)
        precondition(store.focusedSession?.sessionID == sessionA)

        let second = AgentMonitorUpdate(
            sessionID: sessionB,
            state: .running,
            title: "CODEX",
            detail: "apply_patch"
        )
        precondition(store.apply(second) == .none)
        precondition(store.focusedSession?.sessionID == sessionA)

        store.selectNextSession()
        precondition(store.focusedSession?.sessionID == sessionB)
        store.selectPreviousSession()
        precondition(store.focusedSession?.sessionID == sessionA)

        let attention = AgentMonitorUpdate(
            sessionID: sessionB,
            state: .needsAttention,
            title: "ACTION NEEDED",
            detail: "Bash"
        )
        precondition(store.apply(attention) == .needsAttention)
        precondition(store.focusedSession?.sessionID == sessionB)
        precondition(store.attentionSessionCount == 1)
        precondition(store.apply(attention) == .none)

        let completed = AgentMonitorUpdate(
            sessionID: sessionA,
            state: .completed,
            title: "DONE",
            detail: "TURN COMPLETE"
        )
        precondition(store.apply(completed) == .completed)
        precondition(store.apply(completed) == .none)

        let completedFromNewSession = AgentMonitorUpdate(
            sessionID: 0xC000_0000_0000_0003,
            state: .completed,
            title: "DONE",
            detail: "TURN COMPLETE"
        )
        precondition(store.apply(completedFromNewSession) == .completed)

        for index in 0 ..< 6 {
            let update = AgentMonitorUpdate(
                sessionID: UInt64(index + 1),
                state: .running,
                title: "CODEX",
                detail: "WORKING"
            )
            precondition(store.apply(update) == .none)
        }
        precondition(store.sessions.count == AgentMonitorSessionStore.maximumSessionCount)

        let overflow = AgentMonitorUpdate(
            sessionID: 0xF000_0000_0000_0001,
            state: .running,
            title: "CODEX",
            detail: "WORKING"
        )
        precondition(store.apply(overflow) == .none)
        precondition(store.sessions.count == AgentMonitorSessionStore.maximumSessionCount)
        precondition(store.sessions.contains { $0.sessionID == 0xF000_0000_0000_0001 })
        precondition(!store.sessions.contains { $0.sessionID == sessionA })
    }
}
