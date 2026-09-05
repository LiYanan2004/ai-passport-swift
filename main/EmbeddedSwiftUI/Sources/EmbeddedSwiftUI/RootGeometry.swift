//
//  EmbeddedRootGeometry.swift
//  EmbeddedSwiftUICore

/// Configures the physical screen and the area offered to the root view.
/// Mirrors the inset -> measure -> center flow of ViewGraph.RootGeometry,
/// without its AttributeGraph rule or layout-direction dependencies.
public struct RootGeometry: Equatable, Sendable {
    public let screenSize: EmbeddedSize
    public let safeAreaInsets: EdgeInsets
    public let centersRootView: Bool
    public init(screenSize: EmbeddedSize, safeAreaInsets: EdgeInsets = .init(), centersRootView: Bool = true) {
        precondition(Int64(safeAreaInsets.leading) + Int64(safeAreaInsets.trailing) <= Int64(screenSize.width))
        precondition(Int64(safeAreaInsets.top) + Int64(safeAreaInsets.bottom) <= Int64(screenSize.height))
        self.screenSize = screenSize
        self.safeAreaInsets = safeAreaInsets
        self.centersRootView = centersRootView
    }
    public var contentBounds: EmbeddedRect {
        .init(x: safeAreaInsets.leading, y: safeAreaInsets.top,
              width: screenSize.width - safeAreaInsets.leading - safeAreaInsets.trailing,
              height: screenSize.height - safeAreaInsets.top - safeAreaInsets.bottom)
    }
}
