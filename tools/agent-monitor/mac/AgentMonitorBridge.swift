import CoreBluetooth
import Darwin
import Foundation

private enum AgentMonitorProtocol {
    static let version: UInt8 = 1
    static let serviceUUID = CBUUID(string: "CB9E9B00-9B0E-4B44-9CC7-7077A7000001")
    static let eventUUID = CBUUID(string: "CB9E9B00-9B0E-4B44-9CC7-7077A7000002")
    static let usageRequestUUID = CBUUID(string: "CB9E9B00-9B0E-4B44-9CC7-7077A7000003")
    static let maximumPacketLength = 101
    static let maximumPendingPacketCount = 64
    private static let usageResponseType: UInt8 = 0x10
    private static let usageRequestType: UInt8 = 0x20
    private static let usageRequestPacketLength = 2
    private static let fiveHourWindowAvailable: UInt8 = 1 << 0
    private static let weeklyWindowAvailable: UInt8 = 1 << 1
    private static let resetCountAvailable: UInt8 = 1 << 2

    enum State: UInt8 {
        case running = 1
        case needsAttention = 2
        case completed = 3
        case interrupted = 4
    }

    struct Event {
        let sessionID: String
        let state: State
        let title: String
        let detail: String
    }

    struct Usage {
        let fiveHourUsedPercent: UInt8?
        let weeklyUsedPercent: UInt8?
        let resetCount: UInt16?
    }

    static func encode(_ event: Event) -> Data? {
        let sessionID = asciiBytes(event.sessionID, maximumLength: 24)
        let title = asciiBytes(event.title, maximumLength: 32)
        let detail = asciiBytes(event.detail, maximumLength: 48)
        guard !sessionID.isEmpty else {
            return nil
        }

        var packet: [UInt8] = [
            version,
            event.state.rawValue,
            UInt8(sessionID.count),
            UInt8(title.count),
            UInt8(detail.count),
        ]
        packet.append(contentsOf: sessionID)
        packet.append(contentsOf: title)
        packet.append(contentsOf: detail)
        return Data(packet)
    }

    static func encode(_ usage: Usage) -> Data {
        var availability: UInt8 = 0
        let fiveHourUsedPercent = normalizedPercent(usage.fiveHourUsedPercent)
        let weeklyUsedPercent = normalizedPercent(usage.weeklyUsedPercent)
        let resetCount = usage.resetCount ?? 0

        if fiveHourUsedPercent != nil {
            availability |= fiveHourWindowAvailable
        }
        if weeklyUsedPercent != nil {
            availability |= weeklyWindowAvailable
        }
        if usage.resetCount != nil {
            availability |= resetCountAvailable
        }

        return Data([
            version,
            usageResponseType,
            availability,
            fiveHourUsedPercent ?? 0,
            weeklyUsedPercent ?? 0,
            UInt8(truncatingIfNeeded: resetCount >> 8),
            UInt8(truncatingIfNeeded: resetCount),
        ])
    }

    static func isUsageRequest(_ data: Data) -> Bool {
        data.count == usageRequestPacketLength &&
            data[data.startIndex] == version &&
            data[data.startIndex + 1] == usageRequestType
    }

    private static func normalizedPercent(_ usedPercent: UInt8?) -> UInt8? {
        guard let usedPercent else {
            return nil
        }
        return min(usedPercent, 100)
    }

    private static func asciiBytes(_ value: String, maximumLength: Int) -> [UInt8] {
        Array(value.utf8.prefix(maximumLength).map { byte in
            byte >= 0x20 && byte <= 0x7e ? byte : UInt8(ascii: "?")
        })
    }
}

private enum AgentMonitorDeviceTarget {
    private static let namePrefix = "AgentMonitor-"
    private static let suffixLength = 12

    static func isValid(_ deviceName: String) -> Bool {
        guard deviceName.hasPrefix(namePrefix) else {
            return false
        }
        let suffix = deviceName.dropFirst(namePrefix.count)
        guard suffix.utf8.count == suffixLength else {
            return false
        }
        return suffix.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70)
        }
    }
}

private struct CodexHookInput: Decodable {
    let sessionID: String
    let agentID: String?
    let hookEventName: String
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
    }
}

private enum CodexHookMapper {
    static func event(from input: CodexHookInput) -> AgentMonitorProtocol.Event? {
        let sessionID = abbreviatedSessionID(input.agentID ?? input.sessionID)
        let toolName = input.toolName.map(compactToolName) ?? "CODEX"

        switch input.hookEventName {
        case "SessionStart":
            return .init(
                sessionID: sessionID,
                state: .running,
                title: "CODEX",
                detail: "SESSION START"
            )
        case "SubagentStart":
            return .init(
                sessionID: sessionID,
                state: .running,
                title: "SUBAGENT",
                detail: "AGENT START"
            )
        case "UserPromptSubmit":
            return .init(
                sessionID: sessionID,
                state: .running,
                title: "CODEX",
                detail: "NEW REQUEST"
            )
        case "PreToolUse":
            return .init(
                sessionID: sessionID,
                state: .running,
                title: "CODEX",
                detail: toolName
            )
        case "PermissionRequest":
            return .init(
                sessionID: sessionID,
                state: .needsAttention,
                title: "ACTION NEEDED",
                detail: "APPROVE \(toolName)"
            )
        case "Stop", "SessionEnd":
            return .init(
                sessionID: sessionID,
                state: .completed,
                title: "DONE",
                detail: "TURN COMPLETE"
            )
        case "SubagentStop":
            return .init(
                sessionID: sessionID,
                state: .completed,
                title: "SUBAGENT",
                detail: "AGENT DONE"
            )
        case "Interrupt":
            return .init(
                sessionID: sessionID,
                state: .interrupted,
                title: "INTERRUPTED",
                detail: "TURN STOPPED"
            )
        default:
            return nil
        }
    }

    private static func abbreviatedSessionID(_ sessionID: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in sessionID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llX", hash)
    }

    private static func compactToolName(_ toolName: String) -> String {
        let components = toolName.split(separator: "_")
        guard let finalComponent = components.last else {
            return toolName
        }
        return String(finalComponent).uppercased()
    }
}

private enum LocalSocketError: Error {
    case invalidPath
    case systemCall(String, Int32)
}

private enum LocalSocket {
    static var path: String {
        if let configuredPath = ProcessInfo.processInfo.environment["AGENT_MONITOR_SOCKET"],
           !configuredPath.isEmpty {
            return configuredPath
        }
        return "/tmp/agent-monitor-\(getuid()).sock"
    }

    static func send(_ payload: Data, to path: String) -> Bool {
        guard payload.count > 0, payload.count <= AgentMonitorProtocol.maximumPacketLength else {
            return false
        }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var suppressBrokenPipeSignal: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &suppressBrokenPipeSignal,
            socklen_t(MemoryLayout.size(ofValue: suppressBrokenPipeSignal))
        ) == 0 else {
            return false
        }

        do {
            var address = try socketAddress(path: path)
            let connectionResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socketAddressLength)
                }
            }
            guard connectionResult == 0 else {
                return false
            }

            var networkLength = UInt16(payload.count).bigEndian
            var frame = Data(bytes: &networkLength, count: MemoryLayout<UInt16>.size)
            frame.append(payload)
            return writeAll(frame, to: descriptor)
        } catch {
            return false
        }
    }

    static func receive(from descriptor: Int32) -> Data? {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        guard let lengthData = readExactly(byteCount: MemoryLayout<UInt16>.size, from: descriptor) else {
            return nil
        }
        let payloadLength = (Int(lengthData[0]) << 8) | Int(lengthData[1])
        guard payloadLength > 0, payloadLength <= AgentMonitorProtocol.maximumPacketLength else {
            return nil
        }
        return readExactly(byteCount: payloadLength, from: descriptor)
    }

    static func socketAddress(path: String) throws -> sockaddr_un {
        let encodedPath = path.utf8CString
        var address = sockaddr_un()
        let maximumPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard encodedPath.count <= maximumPathLength else {
            throw LocalSocketError.invalidPath
        }

        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + encodedPath.count)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            let destination = UnsafeMutableRawPointer(pathPointer).assumingMemoryBound(to: CChar.self)
            memset(destination, 0, maximumPathLength)
            _ = encodedPath.withUnsafeBufferPointer { source in
                memcpy(destination, source.baseAddress!, encodedPath.count)
            }
        }
        return address
    }

    static let socketAddressLength = socklen_t(MemoryLayout<sockaddr_un>.size)

    private static func readExactly(byteCount: Int, from descriptor: Int32) -> Data? {
        var result = Data(count: byteCount)
        let didRead = result.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }

            var offset = 0
            while offset < byteCount {
                let count = read(descriptor, baseAddress.advanced(by: offset), byteCount - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
        return didRead ? result : nil
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }

            var offset = 0
            while offset < data.count {
                let count = write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
                if count > 0 {
                    offset += count
                    continue
                }
                if count < 0, errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
    }
}

private final class LocalEventServer {
    var didReceiveEvent: ((Data) -> Void)?

    private let path: String
    private let descriptor: Int32
    private let acceptSource: DispatchSourceRead

    init(path: String) throws {
        self.path = path
        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw LocalSocketError.systemCall("socket", errno)
        }

        do {
            _ = unlink(path)
            var address = try LocalSocket.socketAddress(path: path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketDescriptor, $0, LocalSocket.socketAddressLength)
                }
            }
            guard bindResult == 0 else {
                throw LocalSocketError.systemCall("bind", errno)
            }
            guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
                throw LocalSocketError.systemCall("chmod", errno)
            }
            guard listen(socketDescriptor, 16) == 0 else {
                throw LocalSocketError.systemCall("listen", errno)
            }

            let flags = fcntl(socketDescriptor, F_GETFL)
            guard flags >= 0, fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw LocalSocketError.systemCall("fcntl", errno)
            }
        } catch {
            close(socketDescriptor)
            _ = unlink(path)
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: .main)
        self.descriptor = socketDescriptor
        self.acceptSource = source
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.setCancelHandler {
            close(socketDescriptor)
        }
        source.resume()
    }

    deinit {
        acceptSource.cancel()
        _ = unlink(path)
    }

    private func acceptPendingClients() {
        while true {
            let clientDescriptor = accept(descriptor, nil, nil)
            if clientDescriptor >= 0 {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let payload = LocalSocket.receive(from: clientDescriptor)
                    close(clientDescriptor)
                    guard let payload else {
                        return
                    }
                    DispatchQueue.main.async {
                        self?.didReceiveEvent?(payload)
                    }
                }
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            return
        }
    }
}

/// Reads only the compact account allowance snapshot exposed by the locally
/// authenticated Codex app-server. It never opens or copies Codex credentials.
private enum CodexUsageReader {
    private static let requestTimeoutSeconds = 15

    private struct UsageWindow {
        let usedPercent: UInt8
        let durationMinutes: Int?
    }

    static func fetch(completion: @escaping (AgentMonitorProtocol.Usage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let usage = fetchSynchronously()
            DispatchQueue.main.async {
                completion(usage)
            }
        }
    }

    private static func fetchSynchronously() -> AgentMonitorProtocol.Usage {
        guard let response = readRateLimitResponse() else {
            return .init(
                fiveHourUsedPercent: nil,
                weeklyUsedPercent: nil,
                resetCount: nil
            )
        }
        return usage(from: response)
    }

    private static func readRateLimitResponse() -> [String: Any]? {
        let process = Process()
        configureAppServer(process)

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .seconds(requestTimeoutSeconds),
            execute: timeoutWorkItem
        )

        var inputClosed = false
        func closeInput() {
            guard !inputClosed else {
                return
            }
            input.fileHandleForWriting.closeFile()
            inputClosed = true
        }
        defer {
            closeInput()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            timeoutWorkItem.cancel()
        }

        do {
            try writeRequest(
                [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "clientInfo": [
                            "name": "agent-monitor-bridge",
                            "title": "Agent Monitor Bridge",
                            "version": "1",
                        ],
                        "capabilities": [
                            "experimentalApi": true,
                            "requestAttestation": false,
                        ],
                    ],
                ],
                to: input.fileHandleForWriting
            )
        } catch {
            return nil
        }

        var bufferedOutput = Data()
        guard readResponse(
            identifier: 1,
            from: output.fileHandleForReading,
            bufferedOutput: &bufferedOutput
        ) != nil else {
            return nil
        }

        do {
            try writeRequest(
                [
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "account/rateLimits/read",
                ],
                to: input.fileHandleForWriting
            )
        } catch {
            return nil
        }

        guard let response = readResponse(
            identifier: 2,
            from: output.fileHandleForReading,
            bufferedOutput: &bufferedOutput
        ) else {
            return nil
        }

        closeInput()
        process.waitUntilExit()
        return response
    }

    private static func configureAppServer(_ process: Process) {
        let configuredPath = ProcessInfo.processInfo.environment["AGENT_MONITOR_CODEX_EXECUTABLE"]
        let installedPaths = [
            configuredPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
        ].compactMap { $0 }

        if let executablePath = installedPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["app-server", "--stdio"]
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--stdio"]
    }

    private static func writeRequest(
        _ request: [String: Any],
        to input: FileHandle
    ) throws {
        let encodedRequest = try JSONSerialization.data(withJSONObject: request)
        input.write(encodedRequest)
        input.write(Data([0x0A]))
    }

    private static func readResponse(
        identifier: Int,
        from output: FileHandle,
        bufferedOutput: inout Data
    ) -> [String: Any]? {
        while true {
            while let lineEnd = bufferedOutput.firstIndex(of: 0x0A) {
                let line = bufferedOutput[..<lineEnd]
                bufferedOutput.removeSubrange(...lineEnd)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)),
                      let response = object as? [String: Any],
                      let responseIdentifier = integer(named: "id", in: response),
                      responseIdentifier == identifier else {
                    continue
                }
                return response["result"] as? [String: Any]
            }

            let availableData = output.availableData
            guard !availableData.isEmpty else {
                return nil
            }
            bufferedOutput.append(availableData)
        }
    }

    private static func usage(from response: [String: Any]) -> AgentMonitorProtocol.Usage {
        let rateLimitSnapshot = codexRateLimitSnapshot(from: response)
        let primaryWindow = rateLimitSnapshot.flatMap { usageWindow(named: "primary", in: $0) }
        let secondaryWindow = rateLimitSnapshot.flatMap { usageWindow(named: "secondary", in: $0) }
        let windows = [primaryWindow, secondaryWindow].compactMap { $0 }

        var fiveHourWindow = closestWindow(
            to: 5 * 60,
            from: windows.filter { ($0.durationMinutes ?? Int.max) < 24 * 60 }
        )
        var weeklyWindow = closestWindow(
            to: 7 * 24 * 60,
            from: windows.filter { ($0.durationMinutes ?? 0) >= 24 * 60 }
        )

        if fiveHourWindow == nil, primaryWindow?.durationMinutes == nil {
            fiveHourWindow = primaryWindow
        }
        if weeklyWindow == nil, secondaryWindow?.durationMinutes == nil {
            weeklyWindow = secondaryWindow
        }

        return .init(
            fiveHourUsedPercent: fiveHourWindow?.usedPercent,
            weeklyUsedPercent: weeklyWindow?.usedPercent,
            resetCount: resetCount(from: response)
        )
    }

    private static func codexRateLimitSnapshot(
        from response: [String: Any]
    ) -> [String: Any]? {
        if let limitsByIdentifier = response["rateLimitsByLimitId"] as? [String: Any],
           let codexLimits = limitsByIdentifier["codex"] as? [String: Any] {
            return codexLimits
        }
        return response["rateLimits"] as? [String: Any]
    }

    private static func usageWindow(
        named name: String,
        in snapshot: [String: Any]
    ) -> UsageWindow? {
        guard let window = snapshot[name] as? [String: Any],
              let usedPercent = integer(named: "usedPercent", in: window) else {
            return nil
        }
        let normalizedPercent = UInt8(min(max(usedPercent, 0), 100))
        return UsageWindow(
            usedPercent: normalizedPercent,
            durationMinutes: integer(named: "windowDurationMins", in: window)
        )
    }

    private static func closestWindow(
        to targetDurationMinutes: Int,
        from windows: [UsageWindow]
    ) -> UsageWindow? {
        windows.min { left, right in
            abs((left.durationMinutes ?? targetDurationMinutes) - targetDurationMinutes) <
                abs((right.durationMinutes ?? targetDurationMinutes) - targetDurationMinutes)
        }
    }

    private static func resetCount(from response: [String: Any]) -> UInt16? {
        guard let resetCredits = response["rateLimitResetCredits"] as? [String: Any],
              let availableCount = integer(named: "availableCount", in: resetCredits),
              availableCount >= 0 else {
            return nil
        }
        return UInt16(min(availableCount, Int(UInt16.max)))
    }

    private static func integer(named name: String, in object: [String: Any]) -> Int? {
        guard let number = object[name] as? NSNumber else {
            return nil
        }
        return number.intValue
    }
}

private final class BluetoothBridge: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let targetDeviceName: String
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var eventCharacteristic: CBCharacteristic?
    private var usageRequestCharacteristic: CBCharacteristic?
    private var pendingEvents: [Data] = []
    private var inFlightEvent: Data?
    private var usageNotificationRequestInFlight = false
    private var usageReadInFlight = false
    private var usageRefreshQueued = false

    init(targetDeviceName: String) {
        self.targetDeviceName = targetDeviceName
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func enqueue(_ event: Data) {
        guard event.count <= AgentMonitorProtocol.maximumPacketLength else {
            writeLog("Dropped oversized event")
            return
        }
        if pendingEvents.count >= AgentMonitorProtocol.maximumPendingPacketCount {
            pendingEvents.removeFirst()
            writeLog("Dropped oldest queued event")
        }
        pendingEvents.append(event)
        writeNextEvent()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            writeLog("Bluetooth state: \(central.state.rawValue)")
            return
        }
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        _ = RSSI
        guard self.peripheral == nil else {
            return
        }
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              localName == targetDeviceName else {
            return
        }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else {
            return
        }
        eventCharacteristic = nil
        usageRequestCharacteristic = nil
        usageNotificationRequestInFlight = false
        peripheral.discoverServices([AgentMonitorProtocol.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        _ = error
        recoverFromConnectionLoss(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        _ = error
        recoverFromConnectionLoss(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == AgentMonitorProtocol.serviceUUID }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics(
            [AgentMonitorProtocol.eventUUID, AgentMonitorProtocol.usageRequestUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              service.uuid == AgentMonitorProtocol.serviceUUID,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == AgentMonitorProtocol.eventUUID && $0.properties.contains(.write)
              }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        eventCharacteristic = characteristic
        usageRequestCharacteristic = service.characteristics?.first(where: {
            $0.uuid == AgentMonitorProtocol.usageRequestUUID && $0.properties.contains(.notify)
        })
        writeLog("Connected to \(targetDeviceName)")
        requestUsageNotifications(on: peripheral)
        writeNextEvent()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == AgentMonitorProtocol.eventUUID else {
            return
        }

        if let error, let inFlightEvent {
            pendingEvents.insert(inFlightEvent, at: 0)
            self.inFlightEvent = nil
            writeLog("BLE write failed: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        inFlightEvent = nil
        requestUsageNotifications(on: peripheral)
        writeNextEvent()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == AgentMonitorProtocol.usageRequestUUID else {
            return
        }

        usageNotificationRequestInFlight = false
        guard error != nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak peripheral] in
            guard let self, let peripheral, peripheral == self.peripheral else {
                return
            }
            self.requestUsageNotifications(on: peripheral)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard peripheral == self.peripheral,
              characteristic.uuid == AgentMonitorProtocol.usageRequestUUID,
              error == nil,
              let request = characteristic.value,
              AgentMonitorProtocol.isUsageRequest(request) else {
            return
        }
        requestUsageSnapshot()
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn,
              peripheral == nil,
              !centralManager.isScanning else {
            return
        }
        centralManager.scanForPeripherals(
            withServices: [AgentMonitorProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        writeLog("Scanning for \(targetDeviceName)")
    }

    private func requestUsageNotifications(on peripheral: CBPeripheral) {
        guard peripheral == self.peripheral,
              let usageRequestCharacteristic,
              !usageRequestCharacteristic.isNotifying,
              !usageNotificationRequestInFlight else {
            return
        }
        usageNotificationRequestInFlight = true
        peripheral.setNotifyValue(true, for: usageRequestCharacteristic)
    }

    private func requestUsageSnapshot() {
        guard !usageReadInFlight else {
            usageRefreshQueued = true
            return
        }

        usageReadInFlight = true
        CodexUsageReader.fetch { [weak self] usage in
            guard let self else {
                return
            }
            self.usageReadInFlight = false
            self.enqueue(AgentMonitorProtocol.encode(usage))
            guard self.usageRefreshQueued else {
                return
            }
            self.usageRefreshQueued = false
            self.requestUsageSnapshot()
        }
    }

    private func writeNextEvent() {
        guard let peripheral,
              let eventCharacteristic,
              inFlightEvent == nil,
              !pendingEvents.isEmpty else {
            return
        }

        let event = pendingEvents.removeFirst()
        let maximumLength = peripheral.maximumWriteValueLength(for: .withResponse)
        guard event.count <= maximumLength else {
            writeLog("Dropped event larger than negotiated BLE write size")
            writeNextEvent()
            return
        }

        inFlightEvent = event
        peripheral.writeValue(event, for: eventCharacteristic, type: .withResponse)
    }

    private func recoverFromConnectionLoss(_ disconnectedPeripheral: CBPeripheral) {
        guard disconnectedPeripheral == peripheral else {
            return
        }
        if let inFlightEvent {
            pendingEvents.insert(inFlightEvent, at: 0)
            self.inFlightEvent = nil
        }
        eventCharacteristic = nil
        usageRequestCharacteristic = nil
        usageNotificationRequestInFlight = false
        peripheral = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startScanning()
        }
    }
}

private func writeLog(_ message: String) {
    FileHandle.standardError.write(Data("agent-monitor: \(message)\n".utf8))
}

private func runHookForwarder() {
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    guard let input = try? JSONDecoder().decode(CodexHookInput.self, from: inputData),
          let event = CodexHookMapper.event(from: input),
          let packet = AgentMonitorProtocol.encode(event) else {
        return
    }
    _ = LocalSocket.send(packet, to: LocalSocket.path)
}

private func runBridge(targetDeviceName: String) throws {
    let bluetoothBridge = BluetoothBridge(targetDeviceName: targetDeviceName)
    let eventServer = try LocalEventServer(path: LocalSocket.path)
    eventServer.didReceiveEvent = { event in
        bluetoothBridge.enqueue(event)
    }
    writeLog("Listening at \(LocalSocket.path)")
    withExtendedLifetime((bluetoothBridge, eventServer)) {
        RunLoop.main.run()
    }
}

private func targetDeviceName(from arguments: [String]) -> String? {
    guard arguments.count == 2,
          arguments[0] == "--device",
          AgentMonitorDeviceTarget.isValid(arguments[1]) else {
        return nil
    }
    return arguments[1]
}

private func writeUsage() {
    writeLog("Usage: agent-monitor-bridge serve --device AgentMonitor-<12UPPERHEX>")
    writeLog("       agent-monitor-bridge hook")
}

let commandArguments = Array(CommandLine.arguments.dropFirst())
switch commandArguments.first {
case "serve":
    guard let targetDeviceName = targetDeviceName(from: Array(commandArguments.dropFirst())) else {
        writeUsage()
        exit(EXIT_FAILURE)
    }
    do {
        try runBridge(targetDeviceName: targetDeviceName)
    } catch {
        writeLog("Unable to start bridge: \(error)")
        exit(EXIT_FAILURE)
    }
case "hook":
    guard commandArguments.count == 1 else {
        writeUsage()
        exit(EXIT_FAILURE)
    }
    runHookForwarder()
default:
    writeUsage()
    exit(EXIT_FAILURE)
}
