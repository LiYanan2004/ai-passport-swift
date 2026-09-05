//
//  EmbeddedImage.swift
//  EmbeddedSwiftUICore

/// A named static asset. Defaults to intrinsic size; resizable adopts proposals.
public struct Image: PrimitiveView, UnaryView {
    public let name: StaticString
    private var isResizable = false
    public init(_ name: StaticString) {
        self.name = name
    }
    public func resizable() -> Self {
        var copy = self
        copy.isResizable = true
        return copy
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs(.image(view.name.description, view.isResizable))
    }
}
