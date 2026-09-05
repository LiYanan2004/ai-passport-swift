import Darwin
import Foundation

@main
struct TestUSBMirrorReceiver {
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [USBMirrorConnectionState] = []
        private var frames = 0

        func record(_ state: USBMirrorConnectionState) {
            lock.lock()
            defer { lock.unlock() }
            states.append(state)
        }

        func recordFrame(_ frame: Data?) {
            guard frame != nil else { return }
            lock.lock()
            defer { lock.unlock() }
            frames += 1
        }

        var snapshot: (states: [USBMirrorConnectionState], frames: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (states, frames)
        }
    }

    final class SerialPort {
        let master: Int32
        let slave: Int32
        let path: String

        init() {
            var master: Int32 = -1
            var slave: Int32 = -1
            var name = [CChar](repeating: 0, count: 256)
            precondition(openpty(&master, &slave, &name, nil, nil) == 0)
            self.master = master
            self.slave = slave
            path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            precondition(fcntl(master, F_SETFL, O_NONBLOCK) == 0)
        }

        deinit {
            Darwin.close(master)
            Darwin.close(slave)
        }

        func send(_ bytes: [UInt8]) {
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(
                        master, buffer.baseAddress!.advanced(by: offset), buffer.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else {
                        precondition(count < 0 && (errno == EAGAIN || errno == EINTR))
                        precondition(ProcessInfo.processInfo.systemUptime < deadline)
                        Thread.sleep(forTimeInterval: 0.001)
                    }
                }
            }
        }

        func receiveHeartbeats() -> Int {
            var buffer = [UInt8](repeating: 0, count: 256)
            var heartbeats = 0
            while true {
                let count = Darwin.read(master, &buffer, buffer.count)
                guard count > 0 else { return heartbeats }
                heartbeats += buffer.prefix(count).filter { $0 == 77 }.count
            }
        }
    }

    static func wait(
        timeout: TimeInterval = 2,
        until condition: () -> Bool
    ) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            precondition(ProcessInfo.processInfo.systemUptime < deadline, "Receiver event timed out")
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func stop(_ receiver: USBMirrorReceiver) {
        let completion = DispatchSemaphore(value: 0)
        receiver.stop()
        receiver.setPausedForFlashing(true) { completion.signal() }
        precondition(completion.wait(timeout: .now() + 2) == .success)
    }

    static func keyFrame(sequence: UInt16) -> [UInt8] {
        (0...MirrorStreamDecoder.height).flatMap { row -> [UInt8] in
            let isFrameEnd = row == MirrorStreamDecoder.height
            let payload: [UInt8] = isFrameEnd
                ? []
                : [0, 0] + [UInt8](repeating: 0xff, count: MirrorStreamDecoder.width * 2)
            var packet = Array("PMIRROW6".utf8)
            packet += [
                isFrameEnd ? 2 : 1, isFrameEnd ? 1 : 0,
                UInt8(truncatingIfNeeded: sequence), UInt8(truncatingIfNeeded: sequence >> 8),
                UInt8(truncatingIfNeeded: row), UInt8(truncatingIfNeeded: row >> 8),
                UInt8(truncatingIfNeeded: payload.count),
                UInt8(truncatingIfNeeded: payload.count >> 8),
            ]
            packet += payload
            let checksum = packet.reduce(UInt32(2166136261)) {
                ($0 ^ UInt32($1)) &* 16777619
            }
            packet += (0..<4).map { UInt8(truncatingIfNeeded: checksum >> ($0 * 8)) }
            return packet
        }
    }

    static func testIdleFramesAndDisconnect() {
        let port = SerialPort()
        let events = Events()
        let path = port.path
        let receiver = USBMirrorReceiver(
            receiveFrame: { events.recordFrame($0) },
            receiveConnectionState: { events.record($0) },
            devicePathProvider: { path }
        )
        defer { stop(receiver) }
        receiver.start()
        wait { events.snapshot.states.last == .connecting }
        port.send(keyFrame(sequence: 0))
        wait { events.snapshot.frames == 1 }

        for sequence: UInt16 in 1...2 {
            Thread.sleep(forTimeInterval: 5)
            precondition(
                events.snapshot.states == [.connecting, .connected],
                "A static screen must stay connected between five-second key frames"
            )
            precondition(port.receiveHeartbeats() >= 6, "Idle connections must renew the USB lease")
            port.send(keyFrame(sequence: sequence))
            wait { events.snapshot.frames == Int(sequence) + 1 }
        }

        // Console output must not keep a stalled mirror stream connected.
        let stoppedAt = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - stoppedAt < 8 {
            port.send(Array("Console output without mirror frames\n".utf8))
            Thread.sleep(forTimeInterval: 0.1)
            if events.snapshot.states.last == .searching { break }
        }
        let disconnectedAfter = ProcessInfo.processInfo.systemUptime - stoppedAt
        precondition(events.snapshot.states.last == .searching)
        // The receiver timestamps the frame before the test thread observes it.
        precondition(disconnectedAfter >= 6.8 && disconnectedAfter < 8,
                     "Unexpected stalled-stream timeout: \(disconnectedAfter)")
        Thread.sleep(forTimeInterval: 1.2)
        precondition(events.snapshot.states == [.connecting, .connected, .searching],
                     "A disconnected session must wait for manual reconnect")
        print("USB receiver idle frames, heartbeats and stalled-stream timeout: PASS")
    }

    static func testInitialFrameTimeout() {
        let port = SerialPort()
        let events = Events()
        let path = port.path
        let receiver = USBMirrorReceiver(
            receiveFrame: { events.recordFrame($0) },
            receiveConnectionState: { events.record($0) },
            devicePathProvider: { path }
        )
        defer { stop(receiver) }
        receiver.start()
        wait { events.snapshot.states.last == .connecting }
        let startedAt = ProcessInfo.processInfo.systemUptime
        wait(timeout: 4) { events.snapshot.states.contains(.searching) }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        precondition(elapsed >= 2.8 && elapsed < 4, "First-frame timeout must stay short")
        precondition(events.snapshot.frames == 0)
        print("USB receiver initial-frame timeout: PASS")
    }

    static func main() {
        testIdleFramesAndDisconnect()
        testInitialFrameTimeout()
    }
}
