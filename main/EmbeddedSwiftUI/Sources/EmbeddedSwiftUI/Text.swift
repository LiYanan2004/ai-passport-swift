//
//  EmbeddedText.swift
//  EmbeddedSwiftUICore

/// Static UTF-8 text rendered with the platform's built-in font.
public struct Text: PrimitiveView, UnaryView {
    public let content: StaticString
    private var color: Color = .white
    private var dynamicContent: String?
    private var hasForegroundStyle = false

    public init(_ content: StaticString) {
        self.content = content
    }

    @_disfavoredOverload
    public init(_ content: String) {
        self.content = ""
        dynamicContent = content
    }
    public init(verbatim content: String) {
        self.content = ""
        dynamicContent = content
    }
    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        let environment = RenderEnvironment(
            font: inputs.environment.font,
            foregroundColor: view.hasForegroundStyle
                ? view.color
                : inputs.environment.foregroundColor,
            foregroundResolver: inputs.environment.foregroundResolver
        )
        return _ViewOutputs(.text(
            view.dynamicContent ?? view.content.description,
            environment
        ))
    }

    public func foregroundStyle(_ color: Color) -> Text {
        var result = self
        result.color = color
        result.hasForegroundStyle = true
        return result
    }

}
