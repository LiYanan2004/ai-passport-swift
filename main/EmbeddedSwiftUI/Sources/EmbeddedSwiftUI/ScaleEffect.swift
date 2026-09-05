// Embedded adaptation of OpenSwiftUI's ScaleEffect.

/// A normalized point in a view's coordinate space.
public struct UnitPoint: Animatable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        precondition(x.isFinite && y.isFinite)
        self.x = x
        self.y = y
    }

    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

public struct _ScaleEffect: GeometryEffect, Equatable {
    public var x: Double
    public var y: Double
    public var anchor: UnitPoint

    public init(x: Double, y: Double, anchor: UnitPoint = .center) {
        self.x = x
        self.y = y
        self.anchor = anchor
    }

    public var animatableData:
        AnimatablePair<AnimatablePair<Double, Double>, UnitPoint.AnimatableData> {
        get {
            AnimatablePair(AnimatablePair(x, y), anchor.animatableData)
        }
        set {
            x = newValue.first.first
            y = newValue.first.second
            anchor.animatableData = newValue.second
        }
    }

    public func effectValue(size: EmbeddedSize) -> ProjectionTransform {
        .scale(x: x, y: y, anchor: anchor, size: size)
    }
}

extension View {
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> some View {
        modifier(_ScaleEffect(
            x: scale,
            y: scale,
            anchor: anchor
        ))
    }

    public func scaleEffect(
        x: Double = 1,
        y: Double = 1,
        anchor: UnitPoint = .center
    ) -> some View {
        precondition(
            x.isFinite && y.isFinite,
            "Scale must be finite"
        )
        return modifier(_ScaleEffect(
            x: x,
            y: y,
            anchor: anchor
        ))
    }
}
