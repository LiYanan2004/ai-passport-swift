// Platform-independent values consumed by the retained renderer.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

// Embedded adaptation: bounded Int32 pixel geometry replaces the upstream
// CoreGraphics values. Layout proposals and container responsibilities remain
// equivalent; the adaptor supplies device metrics and performs final rendering.
public enum Axis: Int8, CaseIterable, Equatable, Sendable {
    case horizontal
    case vertical

    public struct Set: OptionSet, Equatable, Sendable {
        public let rawValue: Int8

        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        public static let horizontal = Axis.Set(rawValue: 1 << Axis.horizontal.rawValue)
        public static let vertical = Axis.Set(rawValue: 1 << Axis.vertical.rawValue)
    }
}

package struct _ClipShape: Equatable {
    private let pathProvider: (ShapeRect) -> Path
    private let comparisonPath: Path

    package init<Content: Shape>(_ shape: Content) {
        pathProvider = { rect in shape.path(in: rect) }
        comparisonPath = shape.path(in: ShapeRect(width: 127, height: 131))
    }

    package func path(in rect: ShapeRect) -> Path {
        pathProvider(rect)
    }

    package static func == (lhs: _ClipShape, rhs: _ClipShape) -> Bool {
        lhs.comparisonPath == rhs.comparisonPath
    }
}

package enum ContainerLayout: Equatable {
    case stack(axis: Axis, spacing: Int32?, alignment: Alignment)
    case overlay(alignment: Alignment)
    case scroll(axes: Axis.Set, showsIndicators: Bool, isList: Bool)
    case frame(width: Int32?, height: Int32?, alignment: Alignment)
    case padding(EdgeInsets)
    case defaultPadding(Edge.Set)
    case background(Color)
    case secondaryBackground(Alignment)
    case offset(x: Int32, y: Int32)
    case opacity(Double)
    case scale(x: Double, y: Double, anchor: UnitPoint)
    case rotation(angle: Angle, anchor: UnitPoint)
    case projection(ProjectionTransform)
    case color(Color)
    case clip(shape: _ClipShape, style: FillStyle)
    case spacer(minLength: Int32?)
    case layout(_AnyLayout)
}

package struct RenderEnvironment {
    package var font: Font?
    package var foregroundColor: Color?
    package var foregroundResolver: ((Color) -> Color)?

    package init(
        font: Font? = nil,
        foregroundColor: Color? = nil,
        foregroundResolver: ((Color) -> Color)? = nil
    ) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.foregroundResolver = foregroundResolver
    }

    package func resolved(in configuration: RendererConfiguration) -> Self {
        Self(
            font: font ?? configuration.defaultFont,
            foregroundColor: foregroundColor
                ?? foregroundResolver?(configuration.defaultForegroundColor)
                ?? configuration.defaultForegroundColor
        )
    }
}
