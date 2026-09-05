// Embedded adaptation of OpenSwiftUICore/Layout/Layout.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

// Embedded adaptation: upstream layout proxies read graph attributes through
// generic storage. Closure-backed, non-generic proxies keep proposal-sensitive
// measurement and placement semantics while avoiding graph/runtime metadata in
// the firmware.
package final class _LayoutSubviewStorage {
    let sizeThatFits: (ProposedViewSize) -> EmbeddedSize
    let place: (EmbeddedRect) -> Void
    let dimensions: ((ProposedViewSize) -> ViewDimensions)?
    let spacing: () -> ViewSpacing
    let didPlace: ((ProposedViewSize) -> Void)?

    package init(
        sizeThatFits: @escaping (ProposedViewSize) -> EmbeddedSize,
        place: @escaping (EmbeddedRect) -> Void,
        dimensions: ((ProposedViewSize) -> ViewDimensions)? = nil,
        spacing: @escaping () -> ViewSpacing = { ViewSpacing() },
        didPlace: ((ProposedViewSize) -> Void)? = nil
    ) {
        self.sizeThatFits = sizeThatFits
        self.place = place
        self.dimensions = dimensions
        self.spacing = spacing
        self.didPlace = didPlace
    }
}

public struct LayoutSubview: Equatable {
    private let storage: _LayoutSubviewStorage
    private let traits: ViewTraitCollection

    package init(
        storage: _LayoutSubviewStorage,
        traits: ViewTraitCollection = ViewTraitCollection()
    ) {
        self.storage = storage
        self.traits = traits
    }

    public func _trait<Key: _ViewTraitKey>(key: Key.Type) -> Key.Value {
        traits[key]
    }

    public subscript<Key: LayoutValueKey>(key: Key.Type) -> Key.Value {
        traits[_LayoutTrait<Key>.self]
    }

    public var priority: Double {
        traits[LayoutPriorityTraitKey.self]
    }

    public var spacing: ViewSpacing {
        storage.spacing()
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize {
        storage.sizeThatFits(proposal)
    }

    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        if let dimensions = storage.dimensions { return dimensions(proposal) }
        let size = sizeThatFits(proposal)
        return ViewDimensions(width: size.width, height: size.height)
    }

    public func place(
        at position: EmbeddedPoint,
        anchor: UnitPoint = .topLeading,
        proposal: ProposedViewSize
    ) {
        let size = sizeThatFits(proposal)
        let x = position.x - Int32((Double(size.width) * anchor.x).rounded())
        let y = position.y - Int32((Double(size.height) * anchor.y).rounded())
        storage.place(EmbeddedRect(x: x, y: y, width: size.width, height: size.height))
        storage.didPlace?(proposal)
    }

    public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
        lhs.storage === rhs.storage
    }
}

public struct LayoutSubviews: Equatable, RandomAccessCollection {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias SubSequence = LayoutSubviews

    private let storage: [LayoutSubview]
    package var defaultSpacing: Int32 = 0
    package var maximumDimension: Int32 = .max

    package init(_ storage: [LayoutSubview], defaultSpacing: Int32 = 0, maximumDimension: Int32 = .max) {
        self.storage = storage
        self.defaultSpacing = defaultSpacing
        self.maximumDimension = maximumDimension
    }

    public var startIndex: Int {
        storage.startIndex
    }

    public var endIndex: Int {
        storage.endIndex
    }

    public subscript(index: Int) -> LayoutSubview {
        storage[index]
    }

    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        LayoutSubviews(Array(storage[bounds]), defaultSpacing: defaultSpacing, maximumDimension: maximumDimension)
    }
}
