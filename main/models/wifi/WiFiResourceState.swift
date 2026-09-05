struct WiFiResourceState: OptionSet {
    let rawValue: UInt8

    static let nvsReady = WiFiResourceState(rawValue: 1 << 0)
    static let networkReady = WiFiResourceState(rawValue: 1 << 1)
    static let eventLoopReady = WiFiResourceState(rawValue: 1 << 2)
}
