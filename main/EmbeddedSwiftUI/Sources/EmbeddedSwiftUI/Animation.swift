// Embedded adaptation of EmbeddedSwiftUICore/Animation/Animation and Transaction.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

@_silgen_name("exp")
private func systemExponential(_ value: Double) -> Double

@_silgen_name("log")
private func systemLogarithm(_ value: Double) -> Double

/// A compact animation description suitable for a single embedded display.
public struct Animation: Equatable {
    public enum Curve: Equatable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
        case timingCurve(Double, Double, Double, Double)
        case spring(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double)
    }

    public enum Repetition: Equatable {
        case once
        case count(Int, autoreverses: Bool)
        case forever(autoreverses: Bool)
    }

    public let curve: Curve
    public let duration: Double
    public let delay: Double
    public let speed: Double
    public let repetition: Repetition
    private let operations: [Operation]

    private enum Operation: Equatable {
        case delay(Double)
        case speed(Double)
        case repetition(Repetition)
    }

    private init(
        curve: Curve,
        duration: Double,
        delay: Double = 0,
        speed: Double = 1,
        repetition: Repetition = .once,
        operations: [Operation] = []
    ) {
        self.curve = curve
        self.duration = Self.validDuration(duration)
        self.delay = Self.validDuration(delay)
        self.speed = speed.isFinite && speed > 0 ? speed : 1
        self.repetition = repetition
        self.operations = operations
    }

    public static var `default`: Animation { .spring }
    public static var linear: Animation { linear(duration: 0.35) }
    public static var easeIn: Animation { easeIn(duration: 0.35) }
    public static var easeOut: Animation { easeOut(duration: 0.35) }
    public static var easeInOut: Animation { easeInOut(duration: 0.35) }
    public static var spring: Animation { spring() }

    public static func linear(duration: Double) -> Animation {
        Animation(curve: .linear, duration: duration)
    }

    public static func easeIn(duration: Double) -> Animation {
        Animation(curve: .easeIn, duration: duration)
    }

    public static func easeOut(duration: Double) -> Animation {
        Animation(curve: .easeOut, duration: duration)
    }

    public static func easeInOut(duration: Double) -> Animation {
        Animation(curve: .easeInOut, duration: duration)
    }

    public static func timingCurve(
        _ p1x: Double,
        _ p1y: Double,
        _ p2x: Double,
        _ p2y: Double,
        duration: Double = 0.35
    ) -> Animation {
        Animation(curve: .timingCurve(p1x, p1y, p2x, p2y), duration: duration)
    }

    public static func interpolatingSpring(
        mass: Double = 1,
        stiffness: Double,
        damping: Double,
        initialVelocity: Double = 0
    ) -> Animation {
        let duration = springDuration(
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
        return Animation(
            curve: .spring(
                mass: mass,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: initialVelocity
            ),
            duration: duration
        )
    }

    public static func spring(
        response: Double = 0.55,
        dampingFraction: Double = 1,
        blendDuration: Double = 0
    ) -> Animation {
        let response = max(0.01, validDuration(response))
        let stiffness = 39.47841760435743 / (response * response)
        let damping = max(0, dampingFraction) * 2 * stiffness.squareRoot()
        _ = blendDuration
        return Animation(
            curve: .spring(mass: 1, stiffness: stiffness, damping: damping, initialVelocity: 0),
            duration: response
        )
    }

    public func delay(_ delay: Double) -> Animation {
        Animation(curve: curve, duration: duration, delay: self.delay + Self.validDuration(delay),
                  speed: speed, repetition: repetition,
                  operations: operations + [.delay(Self.validDuration(delay))])
    }

    public func speed(_ speed: Double) -> Animation {
        let validSpeed = speed.isFinite && speed > 0 ? speed : 1
        return Animation(curve: curve, duration: duration, delay: delay,
                         speed: self.speed * validSpeed, repetition: repetition,
                         operations: operations + [.speed(validSpeed)])
    }

    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        let repetition = Repetition.count(max(1, repeatCount), autoreverses: autoreverses)
        return Animation(curve: curve, duration: duration, delay: delay, speed: speed,
                         repetition: repetition, operations: operations + [.repetition(repetition)])
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        let repetition = Repetition.forever(autoreverses: autoreverses)
        return Animation(curve: curve, duration: duration, delay: delay, speed: speed,
                         repetition: repetition, operations: operations + [.repetition(repetition)])
    }

    public var autoreverses: Bool {
        switch repetition {
        case .once: return false
        case let .count(_, autoreverses), let .forever(autoreverses): return autoreverses
        }
    }

    private static func validDuration(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func springDuration(
        mass: Double,
        stiffness: Double,
        damping: Double,
        initialVelocity: Double
    ) -> Double {
        guard mass.isFinite, stiffness.isFinite, damping.isFinite,
           initialVelocity.isFinite, mass > 0, stiffness > 0, damping > 0
        else {
            return 0
        }
        let angularFrequency = (stiffness / mass).squareRoot()
        let dampingRatio = damping / (2 * (mass * stiffness).squareRoot())
        let adjustedFrequency: Double
        if dampingRatio >= 1 {
            adjustedFrequency = angularFrequency - initialVelocity
        } else {
            let decayFrequency = angularFrequency * (1 - dampingRatio * dampingRatio).squareRoot()
            adjustedFrequency = (angularFrequency * dampingRatio - initialVelocity) / decayFrequency
        }
        let epsilon = 0.001
        if dampingRatio < 1 {
            let value = epsilon / (1 + abs(adjustedFrequency))
            return max(-systemLogarithm(value) / (dampingRatio * angularFrequency), 1)
        }
        var time = 0.0
        var minimumValue = Double.infinity
        var minimumTime = -1.0
        for _ in 0..<1024 {
            let sample =
                1 - (1 + adjustedFrequency * time)
                    * systemExponential(-time * angularFrequency)
            let value = abs(1 - sample)
            guard value.isFinite else { return 0 }
            if minimumValue >= epsilon {
                if value < minimumValue {
                    minimumValue = value
                    minimumTime = time
                }
            } else if value >= epsilon {
                minimumValue = .infinity
            } else if time - minimumTime > 1 {
                break
            }
            time += 0.1
        }
        return max(0, minimumTime)
    }

    // Embedded adaptation: expose composed durations in seconds. Each adaptor
    // owns timer units, representable ranges and repeat-count encoding.
    package var resolvedTiming: (
        duration: Double,
        delay: Double,
        repeatDelay: Double
    ) {
        var resolvedDuration = duration
        var resolvedDelay = 0.0
        var resolvedRepeatDelay = 0.0
        for operation in operations {
            switch operation {
            case let .delay(value):
                resolvedDelay += value
            case let .speed(value):
                resolvedDuration /= value
                resolvedDelay /= value
                resolvedRepeatDelay /= value
            case .repetition:
                resolvedRepeatDelay = resolvedDelay
            }
        }
        return (resolvedDuration, resolvedDelay, resolvedRepeatDelay)
    }
}

/// The context of one state-processing update.
public struct Transaction: Equatable {
    private var animationValue: Animation?
    private var hasAnimation = false
    private var disablesAnimationsValue: Bool?

    public var animation: Animation? {
        get { animationValue }
        set {
            animationValue = newValue
            hasAnimation = true
        }
    }

    public var disablesAnimations: Bool {
        get { disablesAnimationsValue ?? false }
        set { disablesAnimationsValue = newValue }
    }

    public init() {}

    public init(animation: Animation?) {
        animationValue = animation
        hasAnimation = true
    }

    // Embedded adaptation: a compact typed property set replaces upstream's
    // heterogeneous PropertyList. Explicit nil must still override inherited
    // animation, while an unspecified property inherits the current scope.
    package func overriding(_ inherited: Transaction) -> Transaction {
        var result = inherited
        if hasAnimation { result.animation = animationValue }
        if let disablesAnimationsValue { result.disablesAnimations = disablesAnimationsValue }
        return result
    }

    package var current: Transaction {
        overriding(currentTransaction)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.animation == rhs.animation && lhs.disablesAnimations == rhs.disablesAnimations
    }
}

private var currentTransaction = Transaction()
private var pendingTransaction: Transaction?

package func _recordStateTransaction(_ transaction: Transaction) {
    pendingTransaction = transaction
}

/// Executes a closure with the supplied transaction.
public func withTransaction<Result>(
    _ transaction: Transaction,
    _ body: () throws -> Result
) rethrows -> Result {
    let previous = currentTransaction
    currentTransaction = transaction.overriding(previous)
    defer {
        currentTransaction = previous
    }
    return try body()
}

/// Executes a state change and applies the animation to the next explicit render.
public func withAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withTransaction(Transaction(animation: animation), body)
}

/// Consumes the animation recorded by the latest state-changing action.
public func _consumePendingAnimation() -> Animation? {
    _consumePendingTransaction()?.animation
}

public func _consumePendingTransaction() -> Transaction? {
    defer {
        pendingTransaction = nil
    }
    return pendingTransaction
}

/// A value-tracking animation modifier for the embedded retained renderer.
public struct _AnimationModifier<Value: Equatable>: PrimitiveViewModifier {
    public let animation: Animation?
    public let value: Value

    public init(animation: Animation?, value: Value) {
        self.animation = animation
        self.value = value
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginAnimation(
            modifier.animation,
            DisplayList.AnimationValue(modifier.value)
        ))
        displayList.append(outputs.displayList)
        displayList.append(.endAnimation)
        outputs.displayList = displayList
        return outputs
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginAnimation(
            modifier.animation,
            DisplayList.AnimationValue(modifier.value)
        ))
        displayList.append(outputs.displayList)
        displayList.append(.endAnimation)
        outputs.displayList = displayList
        return outputs
    }
}

extension View {
    public func animation<Value: Equatable>(
        _ animation: Animation?,
        value: Value
    ) -> some View {
        modifier(_AnimationModifier(animation: animation, value: value))
    }
}
