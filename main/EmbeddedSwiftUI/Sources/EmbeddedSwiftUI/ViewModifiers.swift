// Embedded counterparts of upstream environment and focus modifiers.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public struct _ForegroundStyleModifier<Style: ShapeStyle>: PrimitiveViewModifier {
    public var style: Style

    public init(style: Style) {
        self.style = style
    }

    public static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        let environment = inputs.environment
        inputs.environment.foregroundColor = nil
        inputs.environment.foregroundResolver = {
            modifier.style._resolve(in: environment, foreground: environment.resolveForeground($0))
        }
        return body(inputs)
    }

    public static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var inputs = inputs
        let environment = inputs.base.environment
        inputs.base.environment.foregroundColor = nil
        inputs.base.environment.foregroundResolver = {
            modifier.style._resolve(in: environment, foreground: environment.resolveForeground($0))
        }
        return body(inputs)
    }
}

package struct _FocusableModifier: PrimitiveViewModifier {
    let enabled: Bool

    package static func _makeView(
        modifier: Self,
        inputs: _ViewInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginFocusable(modifier.enabled))
        displayList.append(outputs.displayList)
        displayList.append(.endFocusable)
        outputs.displayList = displayList
        return outputs
    }

    package static func _makeViewList(
        modifier: Self,
        inputs: _ViewListInputs,
        body: @escaping (_ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(inputs)
        var displayList = DisplayList()
        displayList.append(.beginFocusable(modifier.enabled))
        displayList.append(outputs.displayList)
        displayList.append(.endFocusable)
        outputs.displayList = displayList
        return outputs
    }
}

extension View {
    public func font(_ font: Font?) -> some View {
        environment(\.font, font)
    }

    public func foregroundColor(_ color: Color?) -> some View {
        environment(\.foregroundColor, color)
    }

    public func foregroundStyle<Style: ShapeStyle>(_ style: Style) -> some View {
        modifier(_ForegroundStyleModifier(style: style))
    }
    public func padding(_ edges: Edge.Set, _ length: Int32? = nil) -> some View {
        modifier(_PaddingLayout(
            edges: edges,
            insets: length.map { EdgeInsets(top: $0, leading: $0, bottom: $0, trailing: $0) }
        ))
    }
    public func focusable(_ enabled: Bool = true) -> some View {
        modifier(_FocusableModifier(enabled: enabled))
    }
}

public struct _ClipEffect<Clip: Shape>: RendererEffect {
    public var shape: Clip
    public var style: FillStyle

    public init(shape: Clip, style: FillStyle = FillStyle()) {
        self.shape = shape
        self.style = style
    }

    public var animatableData: Clip.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    package func effectValue(size: EmbeddedSize) -> DisplayList.Effect {
        .clip(_ClipShape(shape), style)
    }
}

extension View {
    public func clipped(antialiased: Bool = false) -> some View {
        clipShape(Rectangle(), style: FillStyle(antialiased: antialiased))
    }

    public func clipShape<Clip: Shape>(
        _ shape: Clip,
        style: FillStyle = FillStyle()
    ) -> some View {
        modifier(_ClipEffect(shape: shape, style: style))
    }
}
