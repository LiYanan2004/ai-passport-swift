struct KnownWiFiAccessPoint {
    let ssid: String
    let rssi: Int
    let channel: Int
}

enum KnownWiFiScanFormatter {
    static let maximumResultCount = 5

    static func format(
        configuredSSIDs: [String],
        visibleAccessPoints: [KnownWiFiAccessPoint]
    ) -> String {
        guard !configuredSSIDs.isEmpty else {
            return "No Wi-Fi credentials configured"
        }

        var lines: [String] = []
        for configuredSSID in configuredSSIDs {
            guard lines.count < maximumResultCount,
                  let accessPoint = visibleAccessPoints.first(where: {
                      matchesConfiguredSSID(configuredSSID, accessPointSSID: $0.ssid)
                  }) else {
                continue
            }
            lines.append(
                "\(accessPoint.rssi)  \(configuredSSID)  ch\(accessPoint.channel)"
            )
        }

        return lines.isEmpty ? "No configured Wi-Fi found" : lines.joined(separator: "\n")
    }

    private static func matchesConfiguredSSID(
        _ configuredSSID: String,
        accessPointSSID: String
    ) -> Bool {
        let configuredBytes = Array(configuredSSID.utf8)
        let accessPointBytes = Array(accessPointSSID.utf8)
        guard configuredBytes.count == accessPointBytes.count else {
            return false
        }
        for index in configuredBytes.indices where configuredBytes[index] != accessPointBytes[index] {
            return false
        }
        return true
    }
}
