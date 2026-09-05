// Embedded adaptation of OpenSwiftUICore/Data/Environment.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    public var font: Font?
    public var foregroundColor: Color?
    package var foregroundResolver: ((Color) -> Color)?
    package var systemColorDefinition: ((SystemColorType) -> Color.Resolved)?
    private var values: [ObjectIdentifier: Any] = [:]

    public init() {
        font = nil
        foregroundColor = nil
    }

    public subscript<Key: EnvironmentKey>(_ key: Key.Type) -> Key.Value {
        get {
            guard let value = values[ObjectIdentifier(key)] else { return Key.defaultValue }
            return value as! Key.Value
        }
        set { values[ObjectIdentifier(key)] = newValue }
    }

    package func resolveForeground(_ defaultColor: Color) -> Color {
        foregroundColor ?? foregroundResolver?(defaultColor) ?? defaultColor
    }
}

@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    private let keyPath: KeyPath<EnvironmentValues, Value>
    private var value: Value?

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        value ?? EnvironmentValues()[keyPath: keyPath]
    }

    public static func _makeProperty(
        in buffer: inout _DynamicPropertyBuffer,
        property: inout Self,
        fieldOffset: Int,
        inputs: inout _ViewInputs
    ) {
        property.value = inputs.environment[keyPath: property.keyPath]
    }
}

// Embedded adaptation: inherited values are concrete _ViewInputs instead of
// graph attributes. One inputs modifier services both construction paths.
public struct _EnvironmentKeyWritingModifier<Value>: PrimitiveViewModifier, ViewInputsModifier {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value

    public init(
        keyPath: WritableKeyPath<EnvironmentValues, Value>,
        value: Value
    ) {
        self.keyPath = keyPath
        self.value = value
    }

    package static func _makeViewInputs(
        modifier: Self,
        inputs: inout _ViewInputs
    ) {
        inputs.environment[keyPath: modifier.keyPath] = modifier.value
    }
}

extension View {
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> some View {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }
}
