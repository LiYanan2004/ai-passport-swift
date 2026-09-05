// Embedded adaptation of OpenSwiftUI's OpacityEffect.

/// A renderer effect that multiplies the opacity of a view and its descendants.
public struct _OpacityEffect: RendererEffect, Equatable {
    public var opacity: Double

    public init(opacity: Double) {
        self.opacity = opacity
    }

    public var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    package func effectValue(size: EmbeddedSize) -> DisplayList.Effect {
        .opacity(opacity)
    }
}

extension View {
    /// Sets the transparency of this view by multiplying its rendered opacity.
    public func opacity(_ opacity: Double) -> some View {
        modifier(_OpacityEffect(opacity: opacity))
    }
}
