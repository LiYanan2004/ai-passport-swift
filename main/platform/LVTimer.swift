final class LVTimer {
    private var opaquePointer: OpaquePointer?

    init?(period: UInt32, callback: @escaping () -> Void) {
        guard let timer = lv_timer_create(lvTimerCallback, period, nil) else { return nil }
        opaquePointer = timer
        activeTimerCallbacks.append((timer, callback))
    }

    func invalidate() {
        guard let opaquePointer else { return }
        activeTimerCallbacks.removeAll { $0.timer == opaquePointer }
        lv_timer_delete(opaquePointer)
        self.opaquePointer = nil
    }

    deinit {
        invalidate()
    }
}

private func lvTimerCallback(_ timer: OpaquePointer?) {
    guard let timer else { return }
    for activeTimerCallback in activeTimerCallbacks where activeTimerCallback.timer == timer {
        activeTimerCallback.callback()
        return
    }
}

private var activeTimerCallbacks: [(timer: OpaquePointer, callback: () -> Void)] = []
