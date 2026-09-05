// Embedded adaptation of OpenSwiftUI geometry effects.

@_silgen_name("cos")
private func geometryCosine(_ value: Double) -> Double
@_silgen_name("sin")
private func geometrySine(_ value: Double) -> Double

/// A geometric angle stored in radians.
public struct Angle: Animatable, Equatable, Comparable, Sendable {
    public var radians: Double

    public var degrees: Double {
        get { radians * (180 / .pi) }
        set { radians = newValue * (.pi / 180) }
    }

    public init() {
        radians = 0
    }

    public init(radians: Double) {
        self.radians = radians
    }

    public init(degrees: Double) {
        radians = degrees * (.pi / 180)
    }

    public static func radians(_ radians: Double) -> Angle {
        Angle(radians: radians)
    }

    public static func degrees(_ degrees: Double) -> Angle {
        Angle(degrees: degrees)
    }

    public static let zero = Angle()

    public static func < (lhs: Angle, rhs: Angle) -> Bool {
        lhs.radians < rhs.radians
    }

    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}

public struct ProjectionTransform: Equatable {
    public var m11: Double = 1 { didSet { primitive = .identity } }
    public var m12: Double = 0 { didSet { primitive = .identity } }
    public var m13: Double = 0 { didSet { primitive = .identity } }
    public var m21: Double = 0 { didSet { primitive = .identity } }
    public var m22: Double = 1 { didSet { primitive = .identity } }
    public var m23: Double = 0 { didSet { primitive = .identity } }
    public var m31: Double = 0 { didSet { primitive = .identity } }
    public var m32: Double = 0 { didSet { primitive = .identity } }
    public var m33: Double = 1 { didSet { primitive = .identity } }

    package enum Storage: Equatable {
        case identity
        case translation(x: Double, y: Double)
        case scale(x: Double, y: Double, anchor: UnitPoint)
        case rotation(angle: Angle, anchor: UnitPoint)
        case projection
    }

    private var primitive: Storage = .identity
    package var storage: Storage {
        if primitive != .identity { return primitive }
        if isIdentity { return .identity }
        if isAffine, m11 == 1, m12 == 0, m21 == 0, m22 == 1 {
            return .translation(x: m31, y: m32)
        }
        return .projection
    }

    public init() {}

    public var isIdentity: Bool {
        m11 == 1 && m12 == 0 && m13 == 0 && m21 == 0 && m22 == 1 && m23 == 0
            && m31 == 0 && m32 == 0 && m33 == 1
    }

    public var isAffine: Bool { m13 == 0 && m23 == 0 && m33 == 1 }

    public func concatenating(_ other: Self) -> Self {
        var result = Self()
        result.m11 = m11 * other.m11 + m12 * other.m21 + m13 * other.m31
        result.m12 = m11 * other.m12 + m12 * other.m22 + m13 * other.m32
        result.m13 = m11 * other.m13 + m12 * other.m23 + m13 * other.m33
        result.m21 = m21 * other.m11 + m22 * other.m21 + m23 * other.m31
        result.m22 = m21 * other.m12 + m22 * other.m22 + m23 * other.m32
        result.m23 = m21 * other.m13 + m22 * other.m23 + m23 * other.m33
        result.m31 = m31 * other.m11 + m32 * other.m21 + m33 * other.m31
        result.m32 = m31 * other.m12 + m32 * other.m22 + m33 * other.m32
        result.m33 = m31 * other.m13 + m32 * other.m23 + m33 * other.m33
        return result
    }

    @discardableResult
    public mutating func invert() -> Bool {
        let determinant = m11 * (m22 * m33 - m23 * m32)
            - m12 * (m21 * m33 - m23 * m31) + m13 * (m21 * m32 - m22 * m31)
        guard determinant.isFinite, determinant != 0 else { return false }
        var result = Self()
        result.m11 = (m22 * m33 - m23 * m32) / determinant
        result.m12 = (m13 * m32 - m12 * m33) / determinant
        result.m13 = (m12 * m23 - m13 * m22) / determinant
        result.m21 = (m23 * m31 - m21 * m33) / determinant
        result.m22 = (m11 * m33 - m13 * m31) / determinant
        result.m23 = (m13 * m21 - m11 * m23) / determinant
        result.m31 = (m21 * m32 - m22 * m31) / determinant
        result.m32 = (m12 * m31 - m11 * m32) / determinant
        result.m33 = (m11 * m22 - m12 * m21) / determinant
        self = result
        return true
    }

    public func inverted() -> Self {
        var result = self
        _ = result.invert()
        return result
    }

    package static func translation(x: Double, y: Double) -> ProjectionTransform {
        var result = Self()
        result.m31 = x
        result.m32 = y
        result.primitive = .translation(x: x, y: y)
        return result
    }

    package static func scale(
        x: Double,
        y: Double,
        anchor: UnitPoint,
        size: EmbeddedSize
    ) -> ProjectionTransform {
        var result = Self()
        result.m11 = x
        result.m22 = y
        result.m31 = Double(size.width) * anchor.x * (1 - x)
        result.m32 = Double(size.height) * anchor.y * (1 - y)
        result.primitive = .scale(x: x, y: y, anchor: anchor)
        return result
    }

    package static func rotation(
        angle: Angle,
        anchor: UnitPoint,
        size: EmbeddedSize
    ) -> ProjectionTransform {
        var result = Self()
        let cosine = geometryCosine(angle.radians)
        let sine = geometrySine(angle.radians)
        let x = Double(size.width) * anchor.x
        let y = Double(size.height) * anchor.y
        result.m11 = cosine
        result.m12 = sine
        result.m21 = -sine
        result.m22 = cosine
        result.m31 = x * (1 - cosine) + y * sine
        result.m32 = y * (1 - cosine) - x * sine
        result.primitive = .rotation(angle: angle, anchor: anchor)
        return result
    }
}

public protocol GeometryEffect: Animatable, ViewModifier where Body == Never {
    func effectValue(size: EmbeddedSize) -> ProjectionTransform

    static var _affectsLayout: Bool { get }
}

extension GeometryEffect {
    public static var _affectsLayout: Bool {
        true
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        outputs.displayList = DisplayList(effect: modifier, content: outputs.displayList)
        return outputs
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        outputs.displayList = DisplayList(effect: modifier, content: outputs.displayList)
        return outputs
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

public struct _RotationEffect: GeometryEffect, Equatable {
    public var angle: Angle
    public var anchor: UnitPoint

    public init(angle: Angle, anchor: UnitPoint = .center) {
        self.angle = angle
        self.anchor = anchor
    }

    public var animatableData:
        AnimatablePair<Angle.AnimatableData, UnitPoint.AnimatableData> {
        get { AnimatablePair(angle.animatableData, anchor.animatableData) }
        set {
            angle.animatableData = newValue.first
            anchor.animatableData = newValue.second
        }
    }

    public func effectValue(size: EmbeddedSize) -> ProjectionTransform {
        .rotation(angle: angle, anchor: anchor, size: size)
    }
}

extension View {
    public func rotationEffect(
        _ angle: Angle,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(_RotationEffect(angle: angle, anchor: anchor))
    }
}
