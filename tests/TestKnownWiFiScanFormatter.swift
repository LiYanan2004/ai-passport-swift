@main
struct KnownWiFiScanFormatterTests {
    static func main() {
        let accessPoints = [
            KnownWiFiAccessPoint(ssid: "Guest", rssi: -30, channel: 1),
            KnownWiFiAccessPoint(ssid: "Studio", rssi: -48, channel: 6),
            KnownWiFiAccessPoint(ssid: "Backup", rssi: -61, channel: 11),
        ]

        precondition(
            KnownWiFiScanFormatter.format(
                configuredSSIDs: [],
                visibleAccessPoints: accessPoints
            ) == "No Wi-Fi credentials configured"
        )
        precondition(
            KnownWiFiScanFormatter.format(
                configuredSSIDs: ["Studio", "Backup"],
                visibleAccessPoints: accessPoints
            ) == "-48  Studio  ch6\n-61  Backup  ch11"
        )
        precondition(
            KnownWiFiScanFormatter.format(
                configuredSSIDs: ["Private"],
                visibleAccessPoints: accessPoints
            ) == "No configured Wi-Fi found"
        )
    }
}
