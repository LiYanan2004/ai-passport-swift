// Embedded adaptation of OpenSwiftUICore/View/Input/ViewList.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

package protocol ViewList {
    typealias IteratorStyle = _ViewList_IteratorStyle
    typealias ID = _ViewList_ID
    typealias Traits = ViewTraitCollection
    typealias Node = _ViewList_Node
    typealias Sublist = _ViewList_Sublist
    typealias SublistTransform = _ViewList_SublistTransform
    typealias Edit = _ViewList_Edit
    typealias ApplyBody = (inout Int, IteratorStyle, Node, inout SublistTransform) -> Bool

    func count(style: IteratorStyle) -> Int
    func estimatedCount(style: IteratorStyle) -> Int
    var traits: ViewTraitCollection { get }
    var traitKeys: ViewTraitKeys? { get }
    var viewIDs: ID.Views? { get }
    func applyNodes(
        from start: inout Int, style: IteratorStyle, list: _StaticViewList?,
        transform: inout SublistTransform, to body: ApplyBody
    ) -> Bool
    func edit(forID id: ID, since transaction: TransactionID) -> Edit?
    func firstOffset<OtherID: Hashable>(forID id: OtherID, style: IteratorStyle) -> Int?
}

package struct _ViewList_IteratorStyle: Equatable {
    package var applyGranularity = false
    package var granularity: Int

    package init(granularity: Int = 1) {
        precondition(granularity > 0)
        self.granularity = granularity
    }

    package func applyGranularity(to count: Int) -> Int { granularity * count }
    package func alignToPreviousGranularityMultiple(_ value: inout Int) {
        value -= value % granularity
    }
    package func alignToNextGranularityMultiple(_ value: inout Int) {
        let remainder = value % granularity
        if remainder != 0 { value += granularity - remainder }
    }
}

package struct TransactionID: Hashable, Comparable {
    package var value: UInt64
    package init(value: UInt64) { self.value = value }
    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

package enum _ViewList_Edit { case inserted, removed }

package struct _ViewList_Sublist {
    package let start: Int
    package let count: Int
    package let id: _ViewList_ID
    package let traits: ViewTraitCollection
}

package enum _ViewList_Node {
    case sublist(_ViewList_Sublist)
}

package struct _ViewList_SublistTransform {
    private var transforms: [(_ViewList_ID) -> _ViewList_ID] = []

    package init() {}
    package mutating func append(_ transform: @escaping (_ViewList_ID) -> _ViewList_ID) {
        transforms.append(transform)
    }
    package func apply(to id: _ViewList_ID) -> _ViewList_ID {
        transforms.reduce(id) { $1($0) }
    }
}

package struct _ViewList_ID_Views: RandomAccessCollection {
    package let elements: [_ViewList_ID]
    package var startIndex: Int { elements.startIndex }
    package var endIndex: Int { elements.endIndex }
    package subscript(index: Int) -> _ViewList_ID { elements[index] }
}

extension _ViewList_ID {
    package typealias Views = _ViewList_ID_Views
}

// Embedded adaptation: the upstream ViewList can be dynamic and graph-backed.
// This eager bounded carrier keeps only the data required by synchronous layout.
package struct _StaticViewList: ViewList {
    package var displayList: DisplayList
    package var viewResponders: [ViewResponder]
    package var staticCount: Int?
    package var traits: ViewTraitCollection
    package var ids: [ID] = []
    private var edits: [ID: (TransactionID, Edit)] = [:]

    package var traitKeys: ViewTraitKeys? { traits.keys }
    package var viewIDs: ID.Views? { ID.Views(elements: ids) }

    package init(
        displayList: DisplayList = DisplayList(),
        viewResponders: [ViewResponder] = [],
        staticCount: Int? = nil,
        traits: ViewTraitCollection = ViewTraitCollection()
    ) {
        self.displayList = displayList
        self.viewResponders = viewResponders
        self.staticCount = staticCount
        self.traits = traits
    }

    package func count(style: IteratorStyle) -> Int {
        style.applyGranularity(to: staticCount ?? ids.count)
    }

    package func estimatedCount(style: IteratorStyle) -> Int {
        count(style: style)
    }

    // Embedded adaptation: eager lists visit concrete sublists synchronously.
    // No Attribute<any ViewList>, subgraph or lazy row generator is retained;
    // identities, traits, offset and stop/resume traversal stay observable.
    package func applyNodes(
        from start: inout Int, style: IteratorStyle, list: _StaticViewList?,
        transform: inout SublistTransform, to body: ApplyBody
    ) -> Bool {
        for (index, id) in ids.enumerated() {
            let amount = style.applyGranularity(to: 1)
            if start >= amount { start -= amount; continue }
            let sublist = Sublist(start: index, count: 1, id: transform.apply(to: id), traits: traits)
            if !body(&start, style, .sublist(sublist), &transform) { return false }
        }
        return true
    }

    package func firstOffset<OtherID: Hashable>(forID id: OtherID, style: IteratorStyle) -> Int? {
        guard let index = ids.firstIndex(where: {
            ($0 as? OtherID) == id || $0.containsID(id)
        }) else { return nil }
        return style.applyGranularity(to: index)
    }

    package mutating func recordEdits(from previous: Self, transaction: TransactionID) {
        // Keep one committed update of edits, matching the eager host's update
        // lifetime. Requests older than that snapshot have no retained history.
        edits.removeAll(keepingCapacity: true)
        let oldIDs = Set(previous.ids)
        let newIDs = Set(ids)
        for id in newIDs.subtracting(oldIDs) { edits[id] = (transaction, .inserted) }
        for id in oldIDs.subtracting(newIDs) { edits[id] = (transaction, .removed) }
    }

    package func edit(forID id: ID, since transaction: TransactionID) -> Edit? {
        guard let entry = edits[id], entry.0 > transaction else { return nil }
        return entry.1
    }
}

package protocol ViewVisitor {
    mutating func visit<Content: View>(_ view: Content)
}

/// Type-only visitor retained from the upstream View construction surface.
/// Embedded Swift has no runtime descriptor traversal; callers provide the
/// concrete generic type at the call site.
package protocol ViewTypeVisitor {
    mutating func visit<Content: View>(type: Content.Type)
}
