//
//  EmbeddedOffset.swift
//  EmbeddedSwiftUICore

public struct _OffsetEffect: GeometryEffect, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }

    public func effectValue(size: EmbeddedSize) -> ProjectionTransform {
        .translation(x: x, y: y)
    }
}

extension View {
    public func offset(x: Double = 0, y: Double = 0) -> some View {
        precondition(
            x.isFinite && y.isFinite
                && x >= Double(Int32.min) && x <= Double(Int32.max)
                && y >= Double(Int32.min) && y <= Double(Int32.max)
        )
        return modifier(_OffsetEffect(x: x, y: y))
    }

    public func offset<Coordinate: BinaryInteger>(
        x: Coordinate = 0,
        y: Coordinate = 0
    ) -> some View {
        precondition(x >= Int32.min && x <= Int32.max && y >= Int32.min && y <= Int32.max)
        return modifier(_OffsetEffect(x: Double(x), y: Double(y)))
    }
}
