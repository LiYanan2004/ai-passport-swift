// Embedded adaptation of OpenSwiftUICore/Animation/Animatable.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

// Embedded adaptation: retain the upstream value protocols for API and effect
// composition, while the LVGL adaptor interpolates only its supported concrete
// properties instead of running OpenSwiftUI's generic graph interpolator.
public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) {
        self *= rhs
    }

    public var magnitudeSquared: Double {
        self * self
    }
}

extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) {
        self *= Float(rhs)
    }

    public var magnitudeSquared: Double {
        Double(self * self)
    }
}

public struct EmptyAnimatableData: VectorArithmetic {
    public init() {}

    public static let zero = EmptyAnimatableData()

    public static func + (
        lhs: EmptyAnimatableData,
        rhs: EmptyAnimatableData
    ) -> EmptyAnimatableData {
        .zero
    }

    public static func - (
        lhs: EmptyAnimatableData,
        rhs: EmptyAnimatableData
    ) -> EmptyAnimatableData {
        .zero
    }

    public mutating func scale(by rhs: Double) {}

    public var magnitudeSquared: Double {
        0
    }
}

public struct AnimatablePair<First, Second>: VectorArithmetic
    where First: VectorArithmetic, Second: VectorArithmetic {
    public var first: First
    public var second: Second

    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    public static var zero: AnimatablePair {
        AnimatablePair(.zero, .zero)
    }

    public static func + (
        lhs: AnimatablePair,
        rhs: AnimatablePair
    ) -> AnimatablePair {
        AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second)
    }

    public static func - (
        lhs: AnimatablePair,
        rhs: AnimatablePair
    ) -> AnimatablePair {
        AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second)
    }

    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }

    public var magnitudeSquared: Double {
        first.magnitudeSquared + second.magnitudeSquared
    }
}

public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic = EmptyAnimatableData
    var animatableData: AnimatableData { get set }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }
}
