final class Battery {
    static let shared = Battery()

    var stateOfCharge: Int32 {
        bsp_battery_soc()
    }

    var voltageMillivolts: Int32 {
        bsp_battery_mv()
    }

    private init() {}

    func initialize() -> Bool {
        bsp_battery_init() == ESP_OK
    }
}
