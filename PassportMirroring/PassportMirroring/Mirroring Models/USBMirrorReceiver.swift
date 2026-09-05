import Foundation
import Darwin
import IOKit
import IOKit.serial

nonisolated enum USBMirrorConnectionState: Sendable, Equatable {
    case searching
    case connecting
    case connected
}

/// All descriptor and decoder state belongs to the private serial queue.
nonisolated final class USBMirrorReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.passport.mirroring.usb", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var descriptor: Int32 = -1
    private var decoder = MirrorStreamDecoder()
    private var nextConnectionAttempt: TimeInterval = 0
    private var nextHeartbeat: TimeInterval = 0
    private var lastMirrorPacket: TimeInterval = 0
    private var isPausedForFlashing = false
    private var waitsForManualReconnect = false
    private var connectionState = USBMirrorConnectionState.searching
    private let receiveFrame: @Sendable (Data?) -> Void
    private let receiveConnectionState: @Sendable (USBMirrorConnectionState) -> Void
    private let devicePathProvider: @Sendable () -> String?

    init(
        receiveFrame: @escaping @Sendable (Data?) -> Void,
        receiveConnectionState: @escaping @Sendable (USBMirrorConnectionState) -> Void,
        devicePathProvider: @escaping @Sendable () -> String? = { USBMirrorReceiver.devicePath() }
    ) {
        self.receiveFrame = receiveFrame
        self.receiveConnectionState = receiveConnectionState
        self.devicePathProvider = devicePathProvider
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(10))
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
            setConnectionState(.searching)
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            disconnect()
        }
    }

    func setPausedForFlashing(
        _ isPaused: Bool,
        completion: @escaping @Sendable () -> Void
    ) {
        queue.async { [self] in
            isPausedForFlashing = isPaused
            if isPaused {
                disconnect(shouldClearFrame: false)
            } else {
                waitsForManualReconnect = false
                nextConnectionAttempt = 0
                setConnectionState(.searching)
            }
            completion()
        }
    }

    func reconnect() {
        queue.async { [self] in
            guard !isPausedForFlashing else { return }
            waitsForManualReconnect = false
            disconnect()
            nextConnectionAttempt = 0
        }
    }

    func stopReconnectAttempt() {
        queue.async { [self] in
            waitsForManualReconnect = true
            disconnect()
        }
    }

    private func disconnect(
        shouldClearFrame: Bool = true,
        waitForManualReconnect: Bool = false
    ) {
        if waitForManualReconnect && connectionState == .connected {
            waitsForManualReconnect = true
        }
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
        decoder = MirrorStreamDecoder()
        if !isPausedForFlashing {
            setConnectionState(.searching)
        }
        if shouldClearFrame {
            receiveFrame(nil)
        }
    }

    private func setConnectionState(_ state: USBMirrorConnectionState) {
        guard connectionState != state else { return }
        connectionState = state
        receiveConnectionState(state)
    }

    private func poll() {
        guard !isPausedForFlashing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if descriptor < 0 {
            guard !waitsForManualReconnect else { return }
            guard now >= nextConnectionAttempt else { return }
            nextConnectionAttempt = now + 1
            guard let path = devicePathProvider() else { return }
            let opened = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard opened >= 0 else { return }
            var settings = termios()
            guard ioctl(opened, TIOCEXCL) == 0, tcgetattr(opened, &settings) == 0 else {
                Darwin.close(opened)
                return
            }
            cfmakeraw(&settings)
            settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
            settings.c_cflag &= ~tcflag_t(CRTSCTS | HUPCL)
            cfsetspeed(&settings, speed_t(B115200))
            guard tcsetattr(opened, TCSANOW, &settings) == 0 else {
                Darwin.close(opened)
                return
            }
            tcflush(opened, TCIFLUSH)
            descriptor = opened
            lastMirrorPacket = now
            nextHeartbeat = 0
            setConnectionState(.connecting)
        }
        if now >= nextHeartbeat {
            var request: UInt8 = 77 // 'M': renew the firmware's two-second lease.
            let written = Darwin.write(descriptor, &request, 1)
            if written < 0 && errno != EAGAIN && errno != EINTR {
                disconnect(waitForManualReconnect: true)
                return
            }
            nextHeartbeat = now + 0.5
        }
        var buffer = [UInt8](repeating: 0, count: 8192)
        var receivedMirrorPacket = false
        // Bound each poll so stop and reconnect requests always get queue time.
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                if let frame = decoder.append(Array(buffer.prefix(count))) {
                    setConnectionState(.connected)
                    receiveFrame(frame)
                }
                receivedMirrorPacket = receivedMirrorPacket || decoder.receivedPacketInLastAppend
            } else {
                if count < 0 && errno != EAGAIN && errno != EINTR {
                    disconnect(waitForManualReconnect: true)
                }
                break
            }
        }
        if receivedMirrorPacket {
            lastMirrorPacket = now
        }
        // A full 240x320 key frame is intentionally transmitted in bounded
        // stripes and can take longer than the first-frame window. Console
        // bytes do not refresh this timer; only a validated PMIRROW6 packet
        // keeps the connection alive.
        let mirrorPacketTimeout: TimeInterval = connectionState == .connected ? 7 : 3
        if descriptor >= 0 && now - lastMirrorPacket > mirrorPacketTimeout {
            disconnect(waitForManualReconnect: true)
        }
    }

    private static func devicePath() -> String? {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            func property(_ name: String) -> AnyObject? {
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, name as CFString, nil, options)
            }
            // Espressif's native USB Serial/JTAG bridge, not an arbitrary serial device.
            guard (property("idVendor") as? NSNumber)?.intValue == 0x303a,
                  (property("idProduct") as? NSNumber)?.intValue == 0x1001 else { continue }
            if let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, nil, 0)?.takeRetainedValue() as? String {
                return path
            }
        }
        return nil
    }
}
