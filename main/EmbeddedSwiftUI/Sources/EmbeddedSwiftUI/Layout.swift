// Embedded adaptation of OpenSwiftUICore/Layout/Layout.swift.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public struct LayoutProperties: Equatable, Sendable {
    public var stackOrientation: Axis?

    public init(stackOrientation: Axis? = nil) {
        self.stackOrientation = stackOrientation
    }
}

public struct ViewSpacing: Equatable, Sendable {
    package var insets = EdgeInsets()

    public init() {}

    package init(insets: EdgeInsets) { self.insets = insets }

    public func distance(to next: ViewSpacing, along axis: Axis) -> Int32 {
        axis == .horizontal
            ? max(insets.trailing, next.insets.leading)
            : max(insets.bottom, next.insets.top)
    }

    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        if edges.contains(.top) { insets.top = max(insets.top, other.insets.top) }
        if edges.contains(.leading) { insets.leading = max(insets.leading, other.insets.leading) }
        if edges.contains(.bottom) { insets.bottom = max(insets.bottom, other.insets.bottom) }
        if edges.contains(.trailing) { insets.trailing = max(insets.trailing, other.insets.trailing) }
    }

    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var result = self
        result.formUnion(other, edges: edges)
        return result
    }
}

public struct ViewDimensions: Equatable {
    public var width: Int32
    public var height: Int32
    private var guides: Guides?

    // Lazy queries avoid allocating values for every possible AlignmentID.
    // These proxies are valid during a serialized synchronous layout pass.
    private final class Guides {
        let horizontal: (HorizontalAlignment) -> Int32?
        let vertical: (VerticalAlignment) -> Int32?

        init(horizontal: @escaping (HorizontalAlignment) -> Int32?,
             vertical: @escaping (VerticalAlignment) -> Int32?) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    public var size: EmbeddedSize {
        EmbeddedSize(width: width, height: height)
    }

    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    package init(size: EmbeddedSize,
                 horizontal: @escaping (HorizontalAlignment) -> Int32?,
                 vertical: @escaping (VerticalAlignment) -> Int32?) {
        width = size.width
        height = size.height
        guides = Guides(horizontal: horizontal, vertical: vertical)
    }

    public subscript(guide: HorizontalAlignment) -> Int32 {
        self[explicit: guide] ?? guide.defaultValue(self)
    }

    public subscript(guide: VerticalAlignment) -> Int32 {
        self[explicit: guide] ?? guide.defaultValue(self)
    }

    public subscript(explicit guide: HorizontalAlignment) -> Int32? {
        guides?.horizontal(guide)
    }

    public subscript(explicit guide: VerticalAlignment) -> Int32? {
        guides?.vertical(guide)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.guides === rhs.guides
    }
}

public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

package struct _LayoutTrait<Key: LayoutValueKey>: _ViewTraitKey {
    package static var defaultValue: Key.Value {
        Key.defaultValue
    }
}

package struct LayoutPriorityTraitKey: _ViewTraitKey {
    package static let defaultValue = 0.0
}

public protocol Layout: Animatable {
    static var layoutProperties: LayoutProperties { get }

    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews

    func makeCache(subviews: Subviews) -> Cache
    func updateCache(_ cache: inout Cache, subviews: Subviews)
    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> EmbeddedSize
    func placeSubviews(
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    )
    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> Int32?
    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> Int32?
}

extension View {
    public func layoutValue<Key: LayoutValueKey>(
        key: Key.Type,
        value: Key.Value
    ) -> some View {
        _trait(_LayoutTrait<Key>.self, value)
    }

    public func layoutPriority(_ value: Double) -> some View {
        _trait(LayoutPriorityTraitKey.self, value)
    }
}

extension Layout {
    public static var layoutProperties: LayoutProperties {
        LayoutProperties()
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        subviews.reduce(into: ViewSpacing()) { $0.formUnion($1.spacing) }
    }

    public func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> Int32? {
        nil
    }

    public func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> Int32? {
        nil
    }

    public func callAsFunction<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        _LayoutView(layout: self, content: content())
    }
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) {

    }
}

package struct _AnyLayout: Equatable {
    // Embedded adaptation: keep the callback table off recursive native frames.
    // One reference carries the upstream layout/cache/guide responsibilities.
    private final class Storage {
        let type: ObjectIdentifier
        let properties: LayoutProperties
        let measure: (ProposedViewSize, LayoutSubviews) -> EmbeddedSize
        let place: (EmbeddedRect, ProposedViewSize, LayoutSubviews) -> Void
        let horizontalAlignment: (HorizontalAlignment, EmbeddedRect, ProposedViewSize, LayoutSubviews) -> Int32?
        let verticalAlignment: (VerticalAlignment, EmbeddedRect, ProposedViewSize, LayoutSubviews) -> Int32?
        let preferredSpacing: (LayoutSubviews) -> ViewSpacing

        init<LayoutType: Layout>(_ layout: LayoutType) {
            type = ObjectIdentifier(LayoutType.self)
            properties = LayoutType.layoutProperties
            var cache: LayoutType.Cache?
            measure = { proposal, subviews in
                if cache == nil {
                    cache = layout.makeCache(subviews: subviews)
                } else {
                    layout.updateCache(&cache!, subviews: subviews)
                }
                return layout.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache!
                )
            }
            place = { bounds, proposal, subviews in
                if cache == nil { cache = layout.makeCache(subviews: subviews) }
                _ = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache!)
                layout.placeSubviews(
                    in: bounds,
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache!
                )
            }
            horizontalAlignment = { guide, bounds, proposal, subviews in
                if cache == nil { cache = layout.makeCache(subviews: subviews) }
                return layout.explicitAlignment(
                    of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache!
                )
            }
            verticalAlignment = { guide, bounds, proposal, subviews in
                if cache == nil { cache = layout.makeCache(subviews: subviews) }
                return layout.explicitAlignment(
                    of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache!
                )
            }
            preferredSpacing = { subviews in
                if cache == nil { cache = layout.makeCache(subviews: subviews) }
                return layout.spacing(subviews: subviews, cache: &cache!)
            }
        }
    }

    private let storage: Storage
    var type: ObjectIdentifier { storage.type }
    var properties: LayoutProperties { storage.properties }

    package init<LayoutType: Layout>(_ layout: LayoutType) {
        storage = Storage(layout)
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, subviews: LayoutSubviews) -> EmbeddedSize {
        storage.measure(proposal, subviews)
    }

    package func placeSubviews(
        in bounds: EmbeddedRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews
    ) -> EmbeddedSize {
        storage.place(bounds, proposal, subviews)
        return bounds.size
    }

    package func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: EmbeddedRect,
        proposal: ProposedViewSize, subviews: LayoutSubviews
    ) -> Int32? {
        storage.horizontalAlignment(guide, bounds, proposal, subviews)
    }

    package func explicitAlignment(
        of guide: VerticalAlignment, in bounds: EmbeddedRect,
        proposal: ProposedViewSize, subviews: LayoutSubviews
    ) -> Int32? {
        storage.verticalAlignment(guide, bounds, proposal, subviews)
    }

    package func spacing(subviews: LayoutSubviews) -> ViewSpacing {
        storage.preferredSpacing(subviews)
    }

    package static func == (lhs: _AnyLayout, rhs: _AnyLayout) -> Bool {
        lhs.type == rhs.type
    }
}
