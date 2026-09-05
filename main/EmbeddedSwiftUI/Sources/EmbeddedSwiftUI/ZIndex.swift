// Embedded adaptation of OpenSwiftUI's ZIndex trait.

package struct ZIndexTraitKey: _ViewTraitKey {
    package static var defaultValue: Double { 0 }
}

extension ViewTraitCollection {
    package var zIndex: Double {
        get { self[ZIndexTraitKey.self] }
        set { self[ZIndexTraitKey.self] = newValue }
    }
}

extension View {
    /// Controls the display order of overlapping sibling views.
    public func zIndex(_ value: Double) -> some View {
        _trait(ZIndexTraitKey.self, value)
    }
}
