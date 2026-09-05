//
//  EmbeddedProposedViewSize.swift
//  EmbeddedSwiftUICore

/// A size proposal; nil asks for the child's ideal size on that axis.
/// The Embedded profile uses integer pixels and a finite maximum probe.
public struct ProposedViewSize: Equatable, Sendable {
    public var width: Int32?
    public var height: Int32?
    public init(width: Int32? = nil, height: Int32? = nil) {
        precondition((width ?? 0) >= 0 && (height ?? 0) >= 0)
        self.width = width
        self.height = height
    }
    public init(_ size: EmbeddedSize) {
        self.init(width: size.width, height: size.height)
    }
    public static let unspecified = ProposedViewSize()
    public static let zero = ProposedViewSize(width: 0, height: 0)
    // Embedded adaptation: integer geometry uses the representable maximum
    // for an infinite proposal. Actual probing/mount limits come from the
    // renderer configuration rather than a fixed backend coordinate range.
    public static let infinity = ProposedViewSize(width: .max, height: .max)
    public static let maximum = infinity
    public func replacingUnspecifiedDimensions(by size: EmbeddedSize = .init(width: 10, height: 10)) -> EmbeddedSize {
        .init(width: width ?? size.width, height: height ?? size.height)
    }
}
