struct WiFiOperationFlags: OptionSet {
    let rawValue: UInt8

    static let rescanAfterConnection = WiFiOperationFlags(rawValue: 1 << 0)
    static let scanSelectsCandidates = WiFiOperationFlags(rawValue: 1 << 1)
    static let candidatesScanned = WiFiOperationFlags(rawValue: 1 << 2)
}
