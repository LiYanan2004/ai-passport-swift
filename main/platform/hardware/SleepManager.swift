final class SleepManager {
    static let shared = SleepManager()

    private static let deepSleepMagic: UInt32 = 0x464F_4C4F

    var wakeupCause: esp_sleep_wakeup_cause_t {
        esp_sleep_get_wakeup_cause()
    }

    var deepSleepWakeCount: UInt32 {
        guard SleepManager.deepSleepWakeMagic == SleepManager.deepSleepMagic else {
            return 0
        }
        return SleepManager.deepSleepWakeCountStorage
    }

    @section(".rtc.data")
    @used
    private static var deepSleepWakeMagic: UInt32 = 0

    @section(".rtc.data")
    @used
    private static var deepSleepWakeCountStorage: UInt32 = 0

    private init() {}

    func performLightSleep(durationMicroseconds: UInt64) -> esp_err_t {
        var error = esp_sleep_enable_timer_wakeup(durationMicroseconds)
        if error == ESP_OK {
            error = esp_light_sleep_start()
        }
        _ = esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER)
        return error
    }

    func performDeepSleep(durationMicroseconds: UInt64) -> esp_err_t {
        let error = esp_sleep_enable_timer_wakeup(durationMicroseconds)
        guard error == ESP_OK else {
            return error
        }

        if SleepManager.deepSleepWakeMagic != SleepManager.deepSleepMagic {
            SleepManager.deepSleepWakeCountStorage = 0
        }
        SleepManager.deepSleepWakeMagic = SleepManager.deepSleepMagic
        SleepManager.deepSleepWakeCountStorage += 1
        esp_deep_sleep_start()
    }

    func disableTimerWakeup() {
        _ = esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER)
    }
}
