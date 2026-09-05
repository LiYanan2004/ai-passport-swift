//
//  EmbeddedAlignment.swift
//  EmbeddedSwiftUICore

// Embedded adaptation: type identifiers and statically specialized callbacks
// replace upstream's runtime alignment-key metadata; guide values use pixels.
public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> Int32
}

package enum AlignmentKey: Hashable {
    case horizontal(HorizontalAlignment)
    case vertical(VerticalAlignment)

    package func explicit(in dimensions: ViewDimensions) -> Int32? {
        switch self {
        case let .horizontal(guide): return dimensions[explicit: guide]
        case let .vertical(guide): return dimensions[explicit: guide]
        }
    }
}

private final class AlignmentKeyStorage: Sendable {
    let identifier: ObjectIdentifier
    let defaultValue: @Sendable (ViewDimensions) -> Int32

    init<ID: AlignmentID>(_ id: ID.Type) {
        identifier = ObjectIdentifier(ID.self)
        defaultValue = { ID.defaultValue(in: $0) }
    }
}

public struct HorizontalAlignment: Hashable, Sendable {
    private let storage: AlignmentKeyStorage
    package var identifier: ObjectIdentifier { storage.identifier }
    package func defaultValue(_ context: ViewDimensions) -> Int32 { storage.defaultValue(context) }

    public init<ID: AlignmentID>(_ id: ID.Type) {
        storage = AlignmentKeyStorage(id)
    }

    public static let leading = Self(Leading.self)
    public static let center = Self(Center.self)
    public static let trailing = Self(Trailing.self)

    private enum Leading: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { 0 }
    }
    private enum Center: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { context.width / 2 }
    }
    private enum Trailing: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { context.width }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

public struct VerticalAlignment: Hashable, Sendable {
    private let storage: AlignmentKeyStorage
    package var identifier: ObjectIdentifier { storage.identifier }
    package func defaultValue(_ context: ViewDimensions) -> Int32 { storage.defaultValue(context) }

    public init<ID: AlignmentID>(_ id: ID.Type) {
        storage = AlignmentKeyStorage(id)
    }

    public static let top = Self(Top.self)
    public static let center = Self(Center.self)
    public static let bottom = Self(Bottom.self)

    private enum Top: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { 0 }
    }
    private enum Center: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { context.height / 2 }
    }
    private enum Bottom: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> Int32 { context.height }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}
public struct Alignment: Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal; self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
    func rect(size: EmbeddedSize, in bounds: EmbeddedRect) -> EmbeddedRect {
        rect(dimensions: ViewDimensions(width: size.width, height: size.height), in: bounds)
    }

    func rect(dimensions: ViewDimensions, in bounds: EmbeddedRect) -> EmbeddedRect {
        let parent = ViewDimensions(width: bounds.width, height: bounds.height)
        return .init(
            x: bounds.x + parent[horizontal] - dimensions[horizontal],
            y: bounds.y + parent[vertical] - dimensions[vertical],
            width: dimensions.width, height: dimensions.height
        )
    }
}
