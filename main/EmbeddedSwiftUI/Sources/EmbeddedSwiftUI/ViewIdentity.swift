// Synchronous identities corresponding to ViewList.ID and DisplayList.Identity.

package struct _ViewList_ID: Hashable {
    package struct ExplicitID: Hashable {
        private let value: Any
        private let hash: Int
        private let equals: (Any) -> Bool

        package init<Value: Hashable>(_ value: Value) {
            self.value = value
            var hasher = Hasher()
            hasher.combine(ObjectIdentifier(Value.self))
            hasher.combine(value)
            hash = hasher.finalize()
            equals = { ($0 as? Value) == value }
        }

        package static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.hash == rhs.hash && lhs.equals(rhs.value)
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(hash)
        }

        package func asValue<Value>(of type: Value.Type) -> Value? { value as? Value }
    }

    package enum Component: Hashable {
        case type(ObjectIdentifier)
        case index(Int)
        case explicit(ExplicitID)
        case implicit(Int)
    }

    // Embedded adaptation: upstream identity scopes are graph-backed. A linked
    // immutable path avoids copying an array at each child on the ESP32-C3 while
    // retaining the same structural/explicit component comparison semantics.
    private final class Node {
        let parent: Node?
        let component: Component
        let hash: Int

        init(parent: Node?, component: Component) {
            self.parent = parent
            self.component = component
            var hasher = Hasher()
            hasher.combine(parent?.hash ?? 0)
            hasher.combine(component)
            hash = hasher.finalize()
        }
    }

    private var node: Node?

    package init() {}

    package init(implicitID: Int) {
        self = appending(.implicit(implicitID))
    }

    package func elementID(at index: Int) -> Self { appending(.index(index)) }

    package mutating func bind<ID: Hashable>(explicitID: ID) {
        self = appending(.explicit(ExplicitID(explicitID)))
    }

    package func containsID<ID: Hashable>(_ id: ID) -> Bool {
        var current = node
        while let value = current {
            if case let .explicit(explicit) = value.component,
               explicit == ExplicitID(id) { return true }
            current = value.parent
        }
        return false
    }

    package func explicitID<ID: Hashable>(for idType: ID.Type) -> ID? {
        var current = node
        while let value = current {
            if case let .explicit(explicit) = value.component,
               let result = explicit.asValue(of: idType) { return result }
            current = value.parent
        }
        return nil
    }

    package func appending(_ component: Component) -> Self {
        var result = self
        result.node = Node(parent: node, component: component)
        return result
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        var left = lhs.node
        var right = rhs.node
        while let leftNode = left, let rightNode = right {
            if leftNode === rightNode { return true }
            guard leftNode.hash == rightNode.hash, leftNode.component == rightNode.component else { return false }
            left = leftNode.parent
            right = rightNode.parent
        }
        return left == nil && right == nil
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(node?.hash ?? 0)
    }
}

private var lastDisplayListIdentity: UInt32 = 0

package struct _DisplayList_Identity: Hashable {
    package let value: UInt32
    package static let none = Self(value: 0)

    package init() {
        lastDisplayListIdentity &+= 1
        precondition(lastDisplayListIdentity != 0, "Display identity exhausted")
        value = lastDisplayListIdentity
    }

    private init(value: UInt32) { self.value = value }
}

// Embedded adaptation: retain the full immutable scope for collision-free
// equality instead of upstream StrongHash/Codable infrastructure. Stable keys
// are distinct from mounted instance IDs, and disappear when ownership ends.
package struct _DisplayList_StableIdentity: Hashable {
    package let scope: _ViewList_ID
    package var serial: UInt32 = 0

    package init(scope: _ViewList_ID, serial: UInt32 = 0) {
        self.scope = scope
        self.serial = serial
    }
}

package struct _DisplayList_StableIdentityMap {
    package var map: [_DisplayList_Identity: _DisplayList_StableIdentity] = [:]
}

package final class _DisplayList_StableIdentityRoot {
    private var identities: [_DisplayList_StableIdentity: _DisplayList_Identity] = [:]
    private var used: Set<_DisplayList_StableIdentity> = []
    private var uncommitted: [_DisplayList_StableIdentity] = []
    package private(set) var map = _DisplayList_StableIdentityMap()
    package init() {}

    package func beginUpdate() {
        for key in uncommitted {
            if let identity = identities.removeValue(forKey: key) { map.map.removeValue(forKey: identity) }
        }
        uncommitted.removeAll(keepingCapacity: true)
        used.removeAll(keepingCapacity: true)
    }

    package func identity(for stableID: _DisplayList_StableIdentity) -> _DisplayList_Identity {
        used.insert(stableID)
        if let identity = identities[stableID] { return identity }
        let identity = _DisplayList_Identity()
        identities[stableID] = identity
        uncommitted.append(stableID)
        map.map[identity] = stableID
        return identity
    }

    package func commit() {
        for key in identities.keys.filter({ !used.contains($0) }) {
            if let identity = identities.removeValue(forKey: key) { map.map.removeValue(forKey: identity) }
        }
        uncommitted.removeAll(keepingCapacity: true)
    }

    package func reset() {
        identities.removeAll()
        used.removeAll()
        uncommitted.removeAll()
        map.map.removeAll()
    }
}

package struct ViewPhase: Equatable {
    package var value: UInt32 = 0
    package var resetSeed: UInt32 {
        get { value >> 1 }
        set { value = (newValue << 1) | (value & 1) }
    }
    package var isBeingRemoved: Bool {
        get { value & 1 != 0 }
        set { value = (value & ~1) | (newValue ? 1 : 0) }
    }
    package var isInserted: Bool { !isBeingRemoved }
    package mutating func merge(_ other: Self) {
        resetSeed &+= other.resetSeed
        isBeingRemoved = isBeingRemoved || other.isBeingRemoved
    }
}

private struct IDPhase<ID: Hashable>: DynamicProperty {
    var id: ID
    var phase: ViewPhase
}

private struct IDPhaseBox<ID: Hashable>: DynamicPropertyBox {
    var lastID: ID?
    var delta: UInt32 = 0

    mutating func update(property: inout IDPhase<ID>, phase: ViewPhase) -> Bool {
        if lastID != property.id {
            if lastID != nil { delta &+= 1 }
            lastID = property.id
        }
        property.phase = phase
        property.phase.resetSeed &+= delta
        return true
    }

    mutating func reset() {
        lastID = nil
        delta = 0
    }
}

public struct IDView<Content: View, ID: Hashable>: PrimitiveView {
    public var content: Content
    public var id: ID

    public init(content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        Content.makeDebuggableView(
            view: view.content,
            inputs: view.childInputs(inputs)
        )
    }

    public static func _makeViewList(view: Self, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.base = view.childInputs(inputs.base)
        return Content.makeDebuggableViewList(view: view.content, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Content._viewListCount(inputs: inputs)
    }

    private func childInputs(_ inputs: _ViewInputs) -> _ViewInputs {
        var inputs = inputs
        var phase = IDPhase(id: id, phase: inputs.phase)
        // The private negative slot cannot collide with generated field offsets.
        inputs.graph?.update(
            box: IDPhaseBox<ID>(), property: &phase,
            identity: inputs.identity.appending(.index(-1)), phase: inputs.phase
        )
        inputs.phase = phase.phase
        return inputs.pushStableID(id)
    }
}

extension View {
    public func id<ID: Hashable>(_ id: ID) -> some View {
        IDView(content: self, id: id)
    }
}
