import Foundation

@main
struct TestMirrorStreamDecoder {
    static func rowPacket(
        row: Int,
        firstColumn: Int = 0,
        pixelCount: Int = MirrorStreamDecoder.width,
        sequence: UInt16,
        color: UInt16,
        compressed: Bool = false
    ) -> [UInt8] {
        let rawPayload = [
            UInt8(truncatingIfNeeded: firstColumn),
            UInt8(truncatingIfNeeded: firstColumn >> 8),
        ] + (0..<pixelCount).flatMap { _ in
            [UInt8(truncatingIfNeeded: color), UInt8(truncatingIfNeeded: color >> 8)]
        }
        let payload = compressed ? encodePackBits(rawPayload) : rawPayload
        var bytes = Array("PMIRROW6".utf8)
        bytes += [1, compressed ? 1 : 0,
                  UInt8(truncatingIfNeeded: sequence), UInt8(truncatingIfNeeded: sequence >> 8),
                  UInt8(truncatingIfNeeded: row), UInt8(truncatingIfNeeded: row >> 8),
                  UInt8(truncatingIfNeeded: payload.count),
                  UInt8(truncatingIfNeeded: payload.count >> 8)]
        bytes += payload
        appendChecksum(to: &bytes)
        return bytes
    }

    static func frameEndPacket(
        sequence: UInt16,
        packetCount: Int,
        isKeyFrame: Bool
    ) -> [UInt8] {
        var bytes = Array("PMIRROW6".utf8)
        bytes += [2, isKeyFrame ? 1 : 0,
                  UInt8(truncatingIfNeeded: sequence), UInt8(truncatingIfNeeded: sequence >> 8),
                  UInt8(truncatingIfNeeded: packetCount),
                  UInt8(truncatingIfNeeded: packetCount >> 8), 0, 0]
        appendChecksum(to: &bytes)
        return bytes
    }

    static func encodePackBits(_ source: [UInt8]) -> [UInt8] {
        var encoded: [UInt8] = []
        var sourceIndex = 0
        while sourceIndex < source.count {
            var runLength = 1
            while sourceIndex + runLength < source.count,
                  source[sourceIndex + runLength] == source[sourceIndex],
                  runLength < 129 {
                runLength += 1
            }
            if runLength >= 3 {
                encoded += [0x80 | UInt8(runLength - 2), source[sourceIndex]]
                sourceIndex += runLength
                continue
            }

            let literalStart = sourceIndex
            sourceIndex += runLength
            while sourceIndex < source.count, sourceIndex - literalStart < 128 {
                runLength = 1
                while sourceIndex + runLength < source.count,
                      source[sourceIndex + runLength] == source[sourceIndex],
                      runLength < 3 {
                    runLength += 1
                }
                if runLength >= 3 || sourceIndex - literalStart + runLength > 128 {
                    break
                }
                sourceIndex += runLength
            }
            let literalLength = sourceIndex - literalStart
            encoded.append(UInt8(literalLength - 1))
            encoded += source[literalStart..<sourceIndex]
        }
        return encoded
    }

    static func appendChecksum(to bytes: inout [UInt8]) {
        let checksum = bytes.reduce(UInt32(2166136261)) {
            ($0 ^ UInt32($1)) &* 16777619
        }
        bytes += (0..<4).map { UInt8(truncatingIfNeeded: checksum >> ($0 * 8)) }
    }

    static func main() {
        testFramesAndSegments()
        testRecovery()
        testIncompleteKeyFrame()
        print("Mirror stream decoder tests: PASS")
    }

    static func testFramesAndSegments() {
        var decoder = MirrorStreamDecoder()
        var keyFrame = [UInt8](repeating: 0x41, count: 31)
        for row in 0..<MirrorStreamDecoder.height {
            keyFrame += rowPacket(
                row: row,
                sequence: 10,
                color: 0x001f,
                compressed: true
            )
        }
        keyFrame += frameEndPacket(
            sequence: 10,
            packetCount: MirrorStreamDecoder.height,
            isKeyFrame: true
        )

        var image: Data?
        for byte in keyFrame {
            if let frame = decoder.append([byte]) { image = frame }
        }
        precondition(rgba(in: image!, row: 0, column: 0) == [0, 0, 255, 255])
        precondition(rgba(in: image!, row: 319, column: 239) == [0, 0, 255, 255])

        let segmentedDelta = rowPacket(
            row: 17,
            firstColumn: 0,
            pixelCount: 120,
            sequence: 11,
            color: 0x07e0
        ) + rowPacket(
            row: 17,
            firstColumn: 120,
            pixelCount: 120,
            sequence: 11,
            color: 0xf800
        ) + frameEndPacket(sequence: 11, packetCount: 2, isKeyFrame: false)
        image = decoder.append(segmentedDelta)
        precondition(rgba(in: image!, row: 17, column: 5) == [0, 255, 0, 255])
        precondition(rgba(in: image!, row: 17, column: 200) == [255, 0, 0, 255])
        precondition(rgba(in: image!, row: 16, column: 5) == [0, 0, 255, 255])

        let compressed = rowPacket(
            row: 319,
            sequence: 12,
            color: 0xffff,
            compressed: true
        ) + frameEndPacket(sequence: 12, packetCount: 1, isKeyFrame: false)
        image = decoder.append(compressed)
        precondition(rgba(in: image!, row: 319, column: 0) == [255, 255, 255, 255])
        precondition(rgba(in: image!, row: 319, column: 239) == [255, 255, 255, 255])
    }

    static func testRecovery() {
        var decoder = MirrorStreamDecoder()
        let initial = (0..<MirrorStreamDecoder.height).flatMap {
            rowPacket(row: $0, sequence: 20, color: 0xffff, compressed: true)
        } + frameEndPacket(
            sequence: 20,
            packetCount: MirrorStreamDecoder.height,
            isKeyFrame: true
        )
        precondition(decoder.append(initial) != nil)

        var damaged = rowPacket(row: 0, sequence: 21, color: 0x07e0)
        damaged[17] ^= 1
        precondition(decoder.append(
            damaged + frameEndPacket(sequence: 21, packetCount: 1, isKeyFrame: false)
        ) == nil)
        precondition(decoder.append(
            rowPacket(row: 1, sequence: 22, color: 0xf800)
                + frameEndPacket(sequence: 22, packetCount: 1, isKeyFrame: false)
        ) == nil)

        let recovered = (0..<MirrorStreamDecoder.height).flatMap {
            rowPacket(row: $0, sequence: 23, color: 0x001f, compressed: true)
        } + frameEndPacket(
            sequence: 23,
            packetCount: MirrorStreamDecoder.height,
            isKeyFrame: true
        )
        let image = decoder.append(recovered)
        precondition(rgba(in: image!, row: 319, column: 239) == [0, 0, 255, 255])
    }

    static func testIncompleteKeyFrame() {
        var decoder = MirrorStreamDecoder()
        let incompleteKeyFrame = (0..<MirrorStreamDecoder.height).flatMap { row in
            rowPacket(
                row: row,
                pixelCount: row == 42 ? 239 : MirrorStreamDecoder.width,
                sequence: 30,
                color: 0x001f,
                compressed: true
            )
        } + frameEndPacket(
            sequence: 30,
            packetCount: MirrorStreamDecoder.height,
            isKeyFrame: true
        )
        precondition(decoder.append(incompleteKeyFrame) == nil)
    }

    static func rgba(in image: Data, row: Int, column: Int) -> [UInt8] {
        let offset = (row * MirrorStreamDecoder.width + column) * 4
        return Array(image[offset..<(offset + 4)])
    }
}
