// Embedded adaptation of OpenSwiftUICore/View/ViewTrait.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

/// A type of key for a trait associated with the content of a container view.
public protocol _ViewTraitKey {
    associatedtype Value

    static var defaultValue: Value { get }
}

package struct ViewTraitKeys {
    package var types: Set<ObjectIdentifier> = []

    package func contains<Key: _ViewTraitKey>(_ key: Key.Type) -> Bool {
        types.contains(ObjectIdentifier(key))
    }
}

public struct ViewTraitCollection {
    // Embedded adaptation: Embedded Swift cannot invoke generic requirements
    // on an existential. Concrete entries preserve the upstream key and
    // collection semantics without graph-backed existential storage.
    private struct Entry {
        let id: ObjectIdentifier
        var value: Any
    }

    private var storage: [Entry]
    package var keys: ViewTraitKeys { ViewTraitKeys(types: Set(storage.map(\.id))) }

    package init() {
        storage = []
    }

    package func contains<Trait: _ViewTraitKey>(_ key: Trait.Type) -> Bool {
        storage.contains { $0.id == ObjectIdentifier(key) }
    }

    package func value<Trait: _ViewTraitKey>(
        for key: Trait.Type,
        defaultValue: Trait.Value
    ) -> Trait.Value {
        guard let entry = storage.first(where: {
            $0.id == ObjectIdentifier(key)
        }) else {
            return defaultValue
        }
        return entry.value as! Trait.Value
    }

    package func value<Trait: _ViewTraitKey>(
        for key: Trait.Type
    ) -> Trait.Value {
        value(for: key, defaultValue: key.defaultValue)
    }

    package mutating func setValueIfUnset<Trait: _ViewTraitKey>(
        _ value: Trait.Value,
        for key: Trait.Type
    ) {
        guard !contains(key) else { return }
        storage.append(Entry(id: ObjectIdentifier(key), value: value))
    }

    package subscript<Trait: _ViewTraitKey>(
        key: Trait.Type
    ) -> Trait.Value {
        get {
            value(for: key)
        }
        set {
            if let index = storage.firstIndex(where: {
                $0.id == ObjectIdentifier(key)
            }) {
                storage[index].value = newValue
            } else {
                storage.append(Entry(id: ObjectIdentifier(key), value: newValue))
            }
        }
    }

    package mutating func mergeValues(_ traits: ViewTraitCollection) {
        for trait in traits.storage {
            if let index = storage.firstIndex(where: { $0.id == trait.id }) {
                storage[index] = trait
            } else {
                storage.append(trait)
            }
        }
    }
}

/// Writes a ViewList trait synchronously without AttributeGraph evaluation.
public struct _TraitWritingModifier<Trait: _ViewTraitKey>: PrimitiveViewModifier {
    public let value: Trait.Value

    public init(value: Trait.Value) {
        self.value = value
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(inputs)
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        inputs.traits[Trait.self] = modifier.value
        var outputs = body(inputs)
        var displayList = DisplayList()
        // Embedded adaptation: AttributeGraph associates traits with the
        // resulting ViewList element. Wrap the synchronous command stream so
        // renderer-effect containers receive that same trait at their root,
        // while forwarding it to the body for custom-layout trait reads.
        displayList.append(.beginTraits(inputs.traits))
        displayList.append(outputs.displayList)
        displayList.append(.endTraits)
        outputs.displayList = displayList
        outputs.views.traits = inputs.traits
        return outputs
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

extension View {
    /// Associates a trait value with the current ViewList element.
    public func _trait<Trait: _ViewTraitKey>(
        _ key: Trait.Type,
        _ value: Trait.Value
    ) -> some View {
        modifier(_TraitWritingModifier<Trait>(value: value))
    }
}
