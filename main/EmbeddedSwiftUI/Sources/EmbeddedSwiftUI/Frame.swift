//
//  EmbeddedFrame.swift
//  EmbeddedSwiftUICore

public struct _FrameLayout: PrimitiveViewModifier, UnaryViewModifier {
    public var width: Int32?
    public var height: Int32?
    public var alignment: Alignment

    public init(width: Int32?, height: Int32?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginContainer(.frame(
            width: modifier.width,
            height: modifier.height,
            alignment: modifier.alignment
        )))
        displayList.append(outputs.displayList)
        displayList.append(.endContainer)
        outputs.displayList = displayList
        return outputs
    }
}

extension View {
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center)
        -> some View
    {
        let pixelWidth = width.map { embeddedFrameDimension($0) }
        let pixelHeight = height.map { embeddedFrameDimension($0) }
        return modifier(_FrameLayout(
            width: pixelWidth,
            height: pixelHeight,
            alignment: alignment
        ))
    }

    public func frame<Dimension: BinaryInteger>(
        width: Dimension? = nil,
        height: Dimension? = nil,
        alignment: Alignment = .center
    ) -> some View {
        precondition(
            (width ?? 0) >= 0 && (height ?? 0) >= 0
                && (width ?? 0) <= Int32.max && (height ?? 0) <= Int32.max
        )
        let pixelWidth = width.map { Int32($0) }
        let pixelHeight = height.map { Int32($0) }
        return modifier(_FrameLayout(
            width: pixelWidth,
            height: pixelHeight,
            alignment: alignment
        ))
    }
}

private func embeddedFrameDimension(_ value: Double) -> Int32 {
    precondition(value.isFinite && value >= 0 && value <= Double(Int32.max))
    return Int32(value.rounded())
}
