// Embedded adaptation of OpenSwiftUICore/View/Input/ViewInputs.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

// Embedded adaptation: eager rows replace upstream demand-driven ViewList
// iteration. All branches share one expansion budget, including empty rows.
package final class ViewListConstructionBudget {
    private var remaining: Int
    package private(set) var isExhausted = false

    package init(limit: Int) {
        remaining = max(0, limit)
    }

    package func consume() -> Bool {
        guard remaining > 0 else {
            isExhausted = true
            return false
        }
        remaining -= 1
        return true
    }
}

public struct _ViewInputs {
    // Embedded adaptation: upstream graph inputs are cheap attribute-backed
    // values. Copying this profile's concrete environment at every recursive
    // View call exhausted the ESP32-C3's 16 KiB UI-task stack, so inherited
    // inputs share copy-on-write storage while preserving branch value semantics.
    private final class Storage {
        var environment = EnvironmentValues()
        var transaction = Transaction()
        var phase = ViewPhase()
        var graph: ViewGraph?
        var configuration: RendererConfiguration?
        var constructionBudget: ViewListConstructionBudget?

        init() {}

        init(copying other: Storage) {
            environment = other.environment
            transaction = other.transaction
            phase = other.phase
            graph = other.graph
            configuration = other.configuration
            constructionBudget = other.constructionBudget
        }
    }

    private var storage: Storage
    package var identity = _ViewList_ID()

    public init() {
        storage = Storage()
    }

    // Recursive construction copies only references. Branch-local writes retain
    // value semantics without placing the environment and configuration on every frame.
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    package var environment: EnvironmentValues {
        get { storage.environment }
        _modify {
            makeUnique()
            yield &storage.environment
        }
    }

    package var transaction: Transaction {
        get { storage.transaction }
        _modify {
            makeUnique()
            yield &storage.transaction
        }
    }

    package var phase: ViewPhase {
        get { storage.phase }
        _modify {
            makeUnique()
            yield &storage.phase
        }
    }

    package var graph: ViewGraph? {
        get { storage.graph }
        _modify {
            makeUnique()
            yield &storage.graph
        }
    }

    package var configuration: RendererConfiguration? {
        get { storage.configuration }
        set {
            makeUnique()
            storage.configuration = newValue
            storage.constructionBudget = newValue.map {
                ViewListConstructionBudget(limit: $0.maximumNodes)
            }
        }
    }

    package var constructionBudget: ViewListConstructionBudget? { storage.constructionBudget }

    package func child(at index: Int) -> Self {
        var result = self
        result.identity = identity.appending(.index(index))
        return result
    }

    package func pushStableType<Value>(_ type: Value.Type) -> Self {
        var result = self
        result.identity = identity.appending(.type(ObjectIdentifier(type)))
        return result
    }

    package func pushStableID<ID: Hashable>(_ id: ID) -> Self {
        var result = self
        result.identity = identity.appending(.explicit(.init(id)))
        return result
    }
}

public struct _ViewListInputs {
    package var base: _ViewInputs
    package var traits: ViewTraitCollection
    package var implicitID = 0

    public init(_ base: _ViewInputs = _ViewInputs()) {
        self.base = base
        traits = ViewTraitCollection()
    }
}

public struct _ViewListCountInputs {
    package var bodyCounts: [ObjectIdentifier: (_ViewListCountInputs) -> Int?] = [:]

    public init() {

    }
}
