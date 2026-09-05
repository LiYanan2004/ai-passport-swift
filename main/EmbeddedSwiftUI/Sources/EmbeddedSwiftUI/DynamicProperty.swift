// Embedded adaptation: OpenSwiftUI discovers DynamicProperty fields through
// AttributeGraph metadata. Embedded Swift has no equivalent runtime traversal,
// so a host-side SwiftSyntax pass emits _makeProperties calls in source order.
// The synchronous buffer retains property installation and update semantics
// without linking reflection or SwiftSyntax into the firmware.

public protocol DynamicProperty {
    static var _propertyBehaviors: UInt32 { get }
    mutating func update()
    static func _makeProperty(
        in buffer: inout _DynamicPropertyBuffer,
        property: inout Self,
        fieldOffset: Int,
        inputs: inout _ViewInputs
    )
    static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    )
}

extension DynamicProperty {
    // All embedded updates are serialized on the renderer task. The upstream
    // scheduling flags remain available without introducing async execution.
    public static var _propertyBehaviors: UInt32 { 0 }
    public mutating func update() {}

    public static func _makeProperties(
        in buffer: inout _DynamicPropertyBuffer,
        container: inout Self,
        inputs: inout _ViewInputs
    ) {}

    public static func _makeProperty(
        in buffer: inout _DynamicPropertyBuffer,
        property: inout Self,
        fieldOffset: Int,
        inputs: inout _ViewInputs
    ) {
        var childInputs = inputs.child(at: fieldOffset)
        Self._makeProperties(in: &buffer, container: &property, inputs: &childInputs)
        buffer.update(
            box: EmbeddedDynamicPropertyBox<Self>(), property: &property,
            fieldOffset: fieldOffset, inputs: &inputs
        )
    }
}

package protocol DynamicPropertyBox<Property> {
    associatedtype Property: DynamicProperty
    mutating func destroy()
    mutating func reset()
    mutating func update(property: inout Property, phase: ViewPhase) -> Bool
    func getState<Value>(type: Value.Type) -> Binding<Value>?
}

extension DynamicPropertyBox {
    package mutating func destroy() {}
    package mutating func reset() {}
    package func getState<Value>(type: Value.Type) -> Binding<Value>? { nil }
}

private struct EmbeddedDynamicPropertyBox<Property: DynamicProperty>: DynamicPropertyBox {
    mutating func update(property: inout Property, phase: ViewPhase) -> Bool {
        property.update()
        return true
    }
}

private final class DynamicPropertyBoxStorage<Box: DynamicPropertyBox> {
    var box: Box
    var resetSeed: UInt32

    init(box: Box, phase: ViewPhase) {
        self.box = box
        resetSeed = phase.resetSeed
    }

    func update(property: inout Box.Property, phase: ViewPhase) -> Bool {
        if resetSeed != phase.resetSeed {
            box.reset()
            resetSeed = phase.resetSeed
        }
        return box.update(property: &property, phase: phase)
    }
}

public struct _DynamicPropertyBuffer {
    public init() {}

    public mutating func append<Property: DynamicProperty>(
        _ property: inout Property,
        fieldOffset: Int,
        inputs: inout _ViewInputs
    ) {
        Property._makeProperty(
            in: &self, property: &property, fieldOffset: fieldOffset, inputs: &inputs
        )
    }

    // Embedded adaptation: the compiler-generated field reference replaces
    // unsafe field offsets. Typed boxes retain reset/update/destroy semantics
    // without invoking generic requirements through a protocol existential.
    package mutating func update<Box: DynamicPropertyBox>(
        box: Box, property: inout Box.Property, fieldOffset: Int, inputs: inout _ViewInputs
    ) {
        guard let graph = inputs.graph else {
            var box = box
            _ = box.update(property: &property, phase: inputs.phase)
            return
        }
        graph.update(
            box: box, property: &property,
            identity: inputs.identity.appending(.index(fieldOffset)), phase: inputs.phase
        )
    }
}

package final class GraphHost {
    package var revision: UInt64 = 0
    package var isUpdating = false
    private var pendingTransaction: Transaction?
    private var pendingRevision: UInt64 = 0

    // Embedded adaptation: the LVGL task coalesces synchronous mutations into
    // one root pass. Keep the transaction on its owning host so another display
    // cannot consume it; failed mounts leave it available for retry.
    package func recordTransaction(_ transaction: Transaction) {
        revision &+= 1
        pendingRevision = revision
        pendingTransaction = transaction
        _recordStateTransaction(transaction)
    }

    package func transactionForUpdate(_ transaction: Transaction) -> Transaction {
        transaction.overriding(pendingTransaction ?? Transaction())
    }

    package func acknowledgeRender(startedAt revision: UInt64) {
        if pendingRevision <= revision { pendingTransaction = nil }
    }

    package func resetTransactions() {
        pendingTransaction = nil
    }
}

// Embedded adaptation: this graph records identity-scoped property ownership
// and host revisions instead of upstream property-level dependency edges. A
// state write schedules a complete synchronous View update while preserving
// storage lifetime and removal invalidation.
package final class ViewGraph {
    package init() {}

    private struct Property {
        let value: Any
        let destroy: () -> Void
        var generation: UInt64
    }

    package let host = GraphHost()
    package var phase = ViewPhase()
    private var generation: UInt64 = 0
    private var properties: [_ViewList_ID: Property] = [:]

    package func beginUpdate() {
        precondition(!host.isUpdating, "View updates must be serialized")
        host.isUpdating = true
        generation &+= 1
    }

    package func endUpdate() {
        host.isUpdating = false
    }

    package func commit() {
        let removed = properties.keys.filter { properties[$0]?.generation != generation }
        for identity in removed {
            properties.removeValue(forKey: identity)?.destroy()
        }
    }

    package func invalidate() {
        host.revision &+= 1
    }

    package func unmount() {
        for property in properties.values {
            property.destroy()
        }
        properties.removeAll()
        host.resetTransactions()
        phase.resetSeed &+= 1
        invalidate()
    }

    package func update<Box: DynamicPropertyBox>(
        box: Box, property: inout Box.Property, identity: _ViewList_ID, phase: ViewPhase
    ) {
        if var entry = properties[identity],
           let storage = entry.value as? DynamicPropertyBoxStorage<Box> {
            entry.generation = generation
            properties[identity] = entry
            _ = storage.update(property: &property, phase: phase)
            return
        }
        properties.removeValue(forKey: identity)?.destroy()
        let storage = DynamicPropertyBoxStorage(box: box, phase: phase)
        properties[identity] = Property(
            value: storage,
            destroy: { storage.box.destroy() },
            generation: generation
        )
        _ = storage.update(property: &property, phase: phase)
    }
}
