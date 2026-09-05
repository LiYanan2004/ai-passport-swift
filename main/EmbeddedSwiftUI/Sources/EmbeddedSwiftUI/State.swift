//
//  EmbeddedState.swift
//  EmbeddedSwiftUICore

/// Embedded adaptation: OpenSwiftUI installs State through AttributeGraph.
/// Compile-time property registration installs the initial value in synchronous,
/// host-owned storage before evaluating body, retaining identity-scoped lifetime,
/// Binding projection, and invalidation semantics without AttributeGraph.
@propertyWrapper
public struct State<Value>: DynamicProperty {
    private final class Storage {
        let initialValue: Value
        var location: StoredLocation<Value>?
        var identity: _ViewList_ID?
        var owner: ObjectIdentifier?

        init(_ value: Value) {
            initialValue = value
        }
    }

    private var storage: Storage
    // Match upstream's value-local installation: a body capture must not follow
    // the shared retained root when a later mount installs a different location.
    private var location: StoredLocation<Value>?

    public init(wrappedValue value: Value) {
        storage = Storage(value)
    }

    public init(initialValue value: Value) {
        self.init(wrappedValue: value)
    }

    public var wrappedValue: Value {
        get { (location ?? storage.location)?.value ?? storage.initialValue }
        nonmutating set { (location ?? storage.location)?.set(newValue) }
    }

    public var projectedValue: Binding<Value> {
        guard let location = location ?? storage.location else {
            return .constant(storage.initialValue)
        }
        // A projection owns this installation, not the State wrapper's next
        // installation. Removed locations continue rejecting stale writes.
        return Binding(get: { location.value }, set: { location.set($0, transaction: $1) })
    }

    public static func _makeProperty(
        in buffer: inout _DynamicPropertyBuffer,
        property: inout Self,
        fieldOffset: Int,
        inputs: inout _ViewInputs
    ) {
        guard let graph = inputs.graph else { return }
        let identity = inputs.identity.appending(.index(fieldOffset))
        buffer.update(
            box: StatePropertyBox(host: graph.host, identity: identity),
            property: &property, fieldOffset: fieldOffset, inputs: &inputs
        )
    }

    private struct StatePropertyBox: DynamicPropertyBox {
        let host: GraphHost
        let identity: _ViewList_ID
        var location: StoredLocation<Value>?

        mutating func update(property: inout State<Value>, phase: ViewPhase) -> Bool {
            let installed = location == nil
            if installed {
                location = StoredLocation(initialValue: property.storage.initialValue, host: host)
            }
            if property.storage.location != nil,
               property.storage.identity != identity || property.storage.owner != ObjectIdentifier(host) {
                property.storage = Storage(property.storage.initialValue)
            }
            property.storage.identity = identity
            property.storage.owner = ObjectIdentifier(host)
            property.storage.location = location
            property.location = location
            return installed
        }

        mutating func reset() {
            location?.invalidate()
            location = nil
        }

        mutating func destroy() { reset() }

        func getState<StateValue>(type: StateValue.Type) -> Binding<StateValue>? {
            guard let location = location as? StoredLocation<StateValue> else { return nil }
            return Binding(get: { location.value }, set: { location.set($0, transaction: $1) })
        }
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() {
        self.init(wrappedValue: nil)
    }
}

@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value>: DynamicProperty {
    private let getValue: () -> Value
    private let setValue: (Value, Transaction) -> Void
    public var transaction = Transaction()

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getValue = get
        setValue = { value, transaction in
            withTransaction(transaction) { set(value) }
        }
    }

    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        getValue = get
        setValue = set
    }

    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue, transaction.current) }
    }

    public var projectedValue: Self { self }

    public static func constant(_ value: Value) -> Self {
        Self(get: { value }, set: { _ in })
    }

    public subscript<Member>(dynamicMember keyPath: WritableKeyPath<Value, Member>) -> Binding<Member> {
        Binding<Member>(
            get: { wrappedValue[keyPath: keyPath] },
            set: { value, transaction in
                var root = wrappedValue
                root[keyPath: keyPath] = value
                setValue(root, transaction)
            }
        ).transaction(transaction)
    }

    public func transaction(_ transaction: Transaction) -> Self {
        var binding = self
        binding.transaction = transaction
        return binding
    }

    public func animation(_ animation: Animation? = .default) -> Self {
        var binding = self
        binding.transaction.animation = animation
        return binding
    }
}

package final class StoredLocation<Value> {
    package private(set) var value: Value
    private let host: GraphHost
    private var isValid = true

    package init(initialValue: Value, host: GraphHost) {
        value = initialValue
        self.host = host
    }

    package func set(_ value: Value, transaction: Transaction = Transaction()) {
        guard isValid, !host.isUpdating else { return }
        self.value = value
        host.recordTransaction(transaction.current)
    }

    package func invalidate() {
        isValid = false
    }
}
