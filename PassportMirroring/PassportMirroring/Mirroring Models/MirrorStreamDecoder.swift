import Foundation

/// Independently checked packets keep boot logs and damaged packets from being
/// interpreted as pixels. Changed rows are presented only at a validated frame
/// boundary.
nonisolated struct MirrorStreamDecoder {
    static let width = 240
    static let height = 320
    private static let maximumDecodedRowPayloadByteCount = width * 2 + 2
    private static let magic = Array("PMIRROW6".utf8)
    private static let headerSize = 16
    private static let checksumSize = 4
    private static let maximumPayloadSize = maximumDecodedRowPayloadByteCount + 4
    private var pending = [UInt8]()
    private var sequence: UInt16?
    private var receivedPacketCount = 0
    private var coveredPixels = [Bool](repeating: false, count: width * height)
    private var lastCompletedSequence: UInt16?
    private var requiresKeyFrame = true
    private var pixels = [UInt8](repeating: 0, count: width * height * 4)
    private(set) var receivedPacketInLastAppend = false

    mutating func append(_ bytes: [UInt8]) -> Data? {
        receivedPacketInLastAppend = false
        pending.append(contentsOf: bytes)
        var offset = 0
        var latestFrame: Data?
        while pending.count - offset >= Self.magic.count {
            if pending[offset..<(offset + 8)].elementsEqual(Self.magic) {
                guard let result = decodePacket(at: offset) else { break }
                if result.consumedBytes > 1 {
                    receivedPacketInLastAppend = true
                }
                offset += result.consumedBytes
                if let frame = result.frame { latestFrame = frame }
            } else {
                offset += 1
            }
        }
        pending.removeFirst(offset)
        return latestFrame
    }

    private mutating func decodePacket(
        at offset: Int
    ) -> (consumedBytes: Int, frame: Data?)? {
        guard pending.count - offset >= Self.headerSize else { return nil }
        let type = pending[offset + 8]
        let flags = pending[offset + 9]
        let packetSequence = UInt16(littleEndianUInt16(at: offset + 10))
        let rowOrCount = littleEndianUInt16(at: offset + 12)
        let payloadSize = littleEndianUInt16(at: offset + 14)
        guard payloadSize <= Self.maximumPayloadSize else {
            return (1, nil)
        }
        let checkedSize = Self.headerSize + payloadSize
        let packetSize = checkedSize + Self.checksumSize
        guard pending.count - offset >= packetSize else { return nil }
        guard checksum(at: offset, count: checkedSize)
                == littleEndianUInt32(at: offset + checkedSize) else {
            return (1, nil)
        }
        guard flags & 0xfe == 0 else { return (packetSize, nil) }

        switch type {
        case 1:
            decodeRow(
                at: offset,
                isCompressed: flags & 1 != 0,
                sequence: packetSequence,
                row: rowOrCount,
                payloadSize: payloadSize
            )
            return (packetSize, nil)
        case 2:
            guard payloadSize == 0 else { return (packetSize, nil) }
            return (packetSize, completeFrame(
                sequence: packetSequence,
                expectedRowCount: rowOrCount,
                isKeyFrame: flags & 1 != 0
            ))
        default:
            return (packetSize, nil)
        }
    }

    private mutating func decodeRow(
        at offset: Int,
        isCompressed: Bool,
        sequence: UInt16,
        row: Int,
        payloadSize: Int
    ) {
        guard row < Self.height else { return }
        beginFrame(sequence)
        let payloadStart = offset + Self.headerSize
        let payload = pending[payloadStart..<(payloadStart + payloadSize)]
        let rowBytes: [UInt8]
        if isCompressed {
            guard let decoded = decodePackBits(payload) else { return }
            rowBytes = decoded
        } else {
            guard payload.count >= 4,
                  payload.count <= Self.maximumDecodedRowPayloadByteCount else { return }
            rowBytes = Array(payload)
        }
        guard writeRow(rowBytes, row: row) else { return }
        receivedPacketCount += 1
    }

    private mutating func beginFrame(_ nextSequence: UInt16) {
        guard sequence != nextSequence else { return }
        if sequence != nil {
            requiresKeyFrame = true
        }
        sequence = nextSequence
        receivedPacketCount = 0
        coveredPixels = [Bool](repeating: false, count: Self.width * Self.height)
    }

    private mutating func completeFrame(
        sequence completedSequence: UInt16,
        expectedRowCount: Int,
        isKeyFrame: Bool
    ) -> Data? {
        guard sequence == completedSequence,
              receivedPacketCount == expectedRowCount,
              (!isKeyFrame || coveredPixels.allSatisfy({ $0 })) else {
            discardPendingFrame()
            return nil
        }
        let sequenceIsContinuous = lastCompletedSequence.map {
            completedSequence == $0 &+ 1
        } ?? false
        guard isKeyFrame || (!requiresKeyFrame && sequenceIsContinuous) else {
            discardPendingFrame()
            return nil
        }
        lastCompletedSequence = completedSequence
        requiresKeyFrame = false
        sequence = nil
        receivedPacketCount = 0
        return Data(pixels)
    }

    private mutating func discardPendingFrame() {
        requiresKeyFrame = true
        sequence = nil
        receivedPacketCount = 0
    }

    private func decodePackBits(_ payload: ArraySlice<UInt8>) -> [UInt8]? {
        var index = payload.startIndex
        var decoded = [UInt8]()
        decoded.reserveCapacity(Self.maximumDecodedRowPayloadByteCount)
        while index < payload.endIndex {
            let control = payload[index]
            index += 1
            if control & 0x80 == 0 {
                let count = Int(control) + 1
                guard payload.endIndex - index >= count,
                      decoded.count + count <= Self.maximumDecodedRowPayloadByteCount else {
                    return nil
                }
                decoded.append(contentsOf: payload[index..<(index + count)])
                index += count
            } else {
                let count = Int(control & 0x7f) + 2
                guard index < payload.endIndex,
                      decoded.count + count <= Self.maximumDecodedRowPayloadByteCount else {
                    return nil
                }
                let byte = payload[index]
                index += 1
                decoded.append(contentsOf: repeatElement(byte, count: count))
            }
        }
        return decoded.count >= 4 ? decoded : nil
    }

    private mutating func writeRow(_ rowBytes: [UInt8], row: Int) -> Bool {
        let firstColumn = Int(rowBytes[0]) | Int(rowBytes[1]) << 8
        let pixelByteCount = rowBytes.count - 2
        guard pixelByteCount.isMultiple(of: 2) else { return false }
        let pixelCount = pixelByteCount / 2
        guard firstColumn < Self.width,
              pixelCount > 0,
              firstColumn + pixelCount <= Self.width else { return false }
        for pixelOffset in 0..<pixelCount {
            let column = firstColumn + pixelOffset
            let sourceOffset = pixelOffset * 2 + 2
            let color = UInt16(rowBytes[sourceOffset])
                | UInt16(rowBytes[sourceOffset + 1]) << 8
            writePixel(color, row: row, column: column)
            coveredPixels[row * Self.width + column] = true
        }
        return true
    }

    private mutating func writePixel(
        _ color: UInt16,
        row: Int,
        column: Int
    ) {
        let red = UInt8((Int((color >> 11) & 0x1f) * 255) / 31)
        let green = UInt8((Int((color >> 5) & 0x3f) * 255) / 63)
        let blue = UInt8((Int(color & 0x1f) * 255) / 31)
        let destination = (row * Self.width + column) * 4
        pixels[destination] = red
        pixels[destination + 1] = green
        pixels[destination + 2] = blue
        pixels[destination + 3] = 255
    }

    private func checksum(at offset: Int, count: Int) -> UInt32 {
        pending[offset..<(offset + count)].reduce(UInt32(2166136261)) {
            ($0 ^ UInt32($1)) &* 16777619
        }
    }

    private func littleEndianUInt16(at offset: Int) -> Int {
        Int(pending[offset]) | Int(pending[offset + 1]) << 8
    }

    private func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) {
            $0 | UInt32(pending[offset + $1]) << ($1 * 8)
        }
    }
}
