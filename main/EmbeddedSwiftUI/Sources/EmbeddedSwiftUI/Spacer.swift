//
//  EmbeddedSpacer.swift
//  EmbeddedSwiftUICore

/// Flexible empty space that consumes the proposed size.
///
/// Stack layouts probe this view at zero and maximum proposed sizes, allowing
/// it to receive the remaining space after fixed-size siblings are measured.
public struct Spacer: PrimitiveView, UnaryView, Sendable {
    /// The least size the spacer accepts on its stack's main axis.
    ///
    /// A nil value uses spacing supplied by the renderer configuration.
    public let minLength: Int32?

    public init(minLength: Int32? = nil) {
        precondition((minLength ?? 0) >= 0)
        self.minLength = minLength
    }

    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs(displayList: DisplayList(commands: [
            .beginContainer(.spacer(minLength: view.minLength)),
            .endContainer,
        ]))
    }
}
