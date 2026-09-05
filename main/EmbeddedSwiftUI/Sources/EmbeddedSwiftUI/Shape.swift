// Embedded, floating-point Shape and Path subset.
// Copyright (c) EmbeddedSwiftUIProject contributors. See ../../LICENSE.

public struct ShapePoint: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        precondition(x.isFinite && y.isFinite)
        self.x = x
        self.y = y
    }
}

public struct ShapeSize: Equatable, Sendable {
    public var width: Float
    public var height: Float

    public init(width: Float, height: Float) {
        precondition(width.isFinite && height.isFinite && width >= 0 && height >= 0)
        self.width = width
        self.height = height
    }
}

public struct ShapeRect: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float = 0, y: Float = 0, width: Float, height: Float) {
        precondition(
            x.isFinite && y.isFinite && width.isFinite && height.isFinite
                && width >= 0 && height >= 0
        )
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: EmbeddedRect) {
        self.init(
            x: Float(rect.x), y: Float(rect.y),
            width: Float(rect.width), height: Float(rect.height)
        )
    }

    public func insetBy(dx: Float, dy: Float) -> ShapeRect {
        let insetWidth = max(0, width - dx * 2)
        let insetHeight = max(0, height - dy * 2)
        return ShapeRect(
            x: x + min(dx, width / 2),
            y: y + min(dy, height / 2),
            width: insetWidth,
            height: insetHeight
        )
    }
}

public struct Path: Equatable, Sendable {
    public enum Element: Equatable, Sendable {
        case move(to: ShapePoint)
        case line(to: ShapePoint)
        case quadCurve(to: ShapePoint, control: ShapePoint)
        case curve(to: ShapePoint, control1: ShapePoint, control2: ShapePoint)
        case closeSubpath
    }

    public private(set) var elements: [Element] = []

    public init() {

    }

    public init(_ rect: ShapeRect) {
        addRect(rect)
    }

    public init(
        roundedRect rect: ShapeRect,
        cornerSize: ShapeSize,
        style: RoundedCornerStyle = .continuous
    ) {
        _ = style
        addRoundedRect(rect, cornerRadius: min(cornerSize.width, cornerSize.height))
    }

    public init(
        roundedRect rect: ShapeRect,
        cornerRadius: Float,
        style: RoundedCornerStyle = .continuous
    ) {
        _ = style
        addRoundedRect(rect, cornerRadius: cornerRadius)
    }

    public init(ellipseIn rect: ShapeRect) {
        addEllipse(in: rect)
    }

    public init(_ builder: (inout Path) -> Void) {
        builder(&self)
    }

    public var isEmpty: Bool { elements.isEmpty }

    public var currentPoint: ShapePoint? {
        var point: ShapePoint?
        var subpathStart: ShapePoint?
        for element in elements {
            switch element {
            case let .move(to):
                point = to
                subpathStart = to
            case let .line(to), let .quadCurve(to, _), let .curve(to, _, _):
                point = to
            case .closeSubpath:
                point = subpathStart
            }
        }
        return point
    }

    public var boundingRect: ShapeRect {
        var minimumX = Float.infinity
        var minimumY = Float.infinity
        var maximumX = -Float.infinity
        var maximumY = -Float.infinity
        func include(_ point: ShapePoint) {
            minimumX = min(minimumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumX = max(maximumX, point.x)
            maximumY = max(maximumY, point.y)
        }
        for element in elements {
            switch element {
            case let .move(to), let .line(to):
                include(to)
            case let .quadCurve(to, control):
                include(to)
                include(control)
            case let .curve(to, control1, control2):
                include(to)
                include(control1)
                include(control2)
            case .closeSubpath:
                break
            }
        }
        guard minimumX.isFinite, minimumY.isFinite else {
            return ShapeRect(width: 0, height: 0)
        }
        return ShapeRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    public mutating func move(to point: ShapePoint) {
        elements.append(.move(to: point))
    }

    public mutating func addLine(to point: ShapePoint) {
        elements.append(.line(to: point))
    }

    public mutating func addQuadCurve(to point: ShapePoint, control: ShapePoint) {
        elements.append(.quadCurve(to: point, control: control))
    }

    public mutating func addCurve(
        to point: ShapePoint,
        control1: ShapePoint,
        control2: ShapePoint
    ) {
        elements.append(.curve(to: point, control1: control1, control2: control2))
    }

    public mutating func closeSubpath() {
        elements.append(.closeSubpath)
    }

    public mutating func addRect(_ rect: ShapeRect) {
        move(to: ShapePoint(x: rect.x, y: rect.y))
        addLine(to: ShapePoint(x: rect.x + rect.width, y: rect.y))
        addLine(to: ShapePoint(x: rect.x + rect.width, y: rect.y + rect.height))
        addLine(to: ShapePoint(x: rect.x, y: rect.y + rect.height))
        closeSubpath()
    }

    public mutating func addRoundedRect(_ rect: ShapeRect, cornerRadius: Float) {
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        guard radius > 0 else {
            addRect(rect)
            return
        }
        let approximation: Float = 0.5522848
        let controlOffset = radius * approximation
        let minimumX = rect.x
        let maximumX = rect.x + rect.width
        let minimumY = rect.y
        let maximumY = rect.y + rect.height
        move(to: ShapePoint(x: minimumX + radius, y: minimumY))
        addLine(to: ShapePoint(x: maximumX - radius, y: minimumY))
        addCurve(
            to: ShapePoint(x: maximumX, y: minimumY + radius),
            control1: ShapePoint(x: maximumX - radius + controlOffset, y: minimumY),
            control2: ShapePoint(x: maximumX, y: minimumY + radius - controlOffset)
        )
        addLine(to: ShapePoint(x: maximumX, y: maximumY - radius))
        addCurve(
            to: ShapePoint(x: maximumX - radius, y: maximumY),
            control1: ShapePoint(x: maximumX, y: maximumY - radius + controlOffset),
            control2: ShapePoint(x: maximumX - radius + controlOffset, y: maximumY)
        )
        addLine(to: ShapePoint(x: minimumX + radius, y: maximumY))
        addCurve(
            to: ShapePoint(x: minimumX, y: maximumY - radius),
            control1: ShapePoint(x: minimumX + radius - controlOffset, y: maximumY),
            control2: ShapePoint(x: minimumX, y: maximumY - radius + controlOffset)
        )
        addLine(to: ShapePoint(x: minimumX, y: minimumY + radius))
        addCurve(
            to: ShapePoint(x: minimumX + radius, y: minimumY),
            control1: ShapePoint(x: minimumX, y: minimumY + radius - controlOffset),
            control2: ShapePoint(x: minimumX + radius - controlOffset, y: minimumY)
        )
        closeSubpath()
    }

    public mutating func addEllipse(in rect: ShapeRect) {
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        let centerX = rect.x + radiusX
        let centerY = rect.y + radiusY
        let control: Float = 0.5522847498
        move(to: ShapePoint(x: centerX + radiusX, y: centerY))
        addCurve(
            to: ShapePoint(x: centerX, y: centerY + radiusY),
            control1: ShapePoint(x: centerX + radiusX, y: centerY + radiusY * control),
            control2: ShapePoint(x: centerX + radiusX * control, y: centerY + radiusY)
        )
        addCurve(
            to: ShapePoint(x: centerX - radiusX, y: centerY),
            control1: ShapePoint(x: centerX - radiusX * control, y: centerY + radiusY),
            control2: ShapePoint(x: centerX - radiusX, y: centerY + radiusY * control)
        )
        addCurve(
            to: ShapePoint(x: centerX, y: centerY - radiusY),
            control1: ShapePoint(x: centerX - radiusX, y: centerY - radiusY * control),
            control2: ShapePoint(x: centerX - radiusX * control, y: centerY - radiusY)
        )
        addCurve(
            to: ShapePoint(x: centerX + radiusX, y: centerY),
            control1: ShapePoint(x: centerX + radiusX * control, y: centerY - radiusY),
            control2: ShapePoint(x: centerX + radiusX, y: centerY - radiusY * control)
        )
        closeSubpath()
    }

    public mutating func addPath(_ path: Path) {
        elements.append(contentsOf: path.elements)
    }

    public func forEach(_ body: (Element) -> Void) {
        for element in elements {
            body(element)
        }
    }
}

public protocol ShapeStyle {
    associatedtype Resolved: ShapeStyle = Never
    func resolve(in environment: EnvironmentValues) -> Resolved
    func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color
}

extension ShapeStyle {
    public func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color {
        resolve(in: environment)._resolve(in: environment, foreground: foreground)
    }

    public func _resolveShapeColor(foreground: Color) -> Color {
        var environment = EnvironmentValues()
        environment.foregroundColor = foreground
        return _resolve(in: environment, foreground: foreground)
    }
}

extension ShapeStyle where Resolved == Never {
    public func resolve(in environment: EnvironmentValues) -> Never {
        preconditionFailure("Primitive ShapeStyle must resolve directly")
    }
}

extension Never: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color {
        self
    }
}

extension Color: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color {
        self
    }
}

extension Color.Resolved: ShapeStyle {
    public func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color {
        Color(rgb: rgb, opacity: opacity)
    }
}

public struct ForegroundStyle: ShapeStyle, Sendable {
    public init() {

    }
    public func _resolve(in environment: EnvironmentValues, foreground: Color) -> Color {
        environment.foregroundColor ?? foreground
    }
}

extension ShapeStyle where Self == ForegroundStyle {
    public static var foreground: ForegroundStyle { .init() }
}

extension ShapeStyle where Self == Color {
    public static var clear: Color { .clear }
    public static var black: Color { .black }
    public static var white: Color { .white }
    public static var gray: Color { .gray }
    public static var red: Color { .red }
    public static var green: Color { .green }
    public static var blue: Color { .blue }
    public static var yellow: Color { .yellow }
    public static var orange: Color { .orange }
    public static var purple: Color { .purple }
}

public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

public enum CGLineCap: Int8, Equatable, Sendable {
    case butt
    case round
    case square
}

public enum CGLineJoin: Int8, Equatable, Sendable {
    case miter
    case round
    case bevel
}

public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: Float
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: Float
    public var dash: [Float]
    public var dashPhase: Float

    public init(
        lineWidth: Float = 1,
        lineCap: CGLineCap = .butt,
        lineJoin: CGLineJoin = .miter,
        miterLimit: Float = 10,
        dash: [Float] = [],
        dashPhase: Float = 0
    ) {
        precondition(
            lineWidth.isFinite && lineWidth >= 0
                && miterLimit.isFinite && miterLimit >= 0
                && dashPhase.isFinite
        )
        precondition(dash.allSatisfy { $0 >= 0 && $0.isFinite })
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

public enum ShapeRenderingStyle: Equatable, Sendable {
    case fill(FillStyle)
    case stroke(StrokeStyle)
}

public protocol Shape: Animatable, View where Body == Never {
    func path(in rect: ShapeRect) -> Path
    func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize
}

extension Shape {
    public static func _makeView(
        view: Self,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _ViewOutputs(.shape(DisplayList.ShapeContent(
            shape: view,
            style: ForegroundStyle(),
            renderingStyle: .fill(FillStyle()),
            environment: inputs.environment
        )))
    }

    public static func _makeViewList(
        view: Self,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        var displayList = DisplayList()
        displayList.append(.beginTraits(inputs.traits))
        displayList.append(Self._makeView(view: view, inputs: inputs.base).displayList)
        displayList.append(.endTraits)
        return _ViewListOutputs(
            displayList: displayList,
            staticCount: 1,
            traits: inputs.traits
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize {
        proposal.replacingUnspecifiedDimensions()
    }

    public var body: Never {
        bodyError()
    }

    public func fill<Style: ShapeStyle>(
        _ content: Style,
        style: FillStyle = FillStyle()
    ) -> _ShapeView<Self, Style> {
        _ShapeView(shape: self, shapeStyle: content, renderingStyle: .fill(style))
    }

    public func fill(style: FillStyle = FillStyle()) -> _ShapeView<Self, ForegroundStyle> {
        fill(ForegroundStyle(), style: style)
    }

    public func stroke<Style: ShapeStyle>(
        _ content: Style,
        style: StrokeStyle
    ) -> _ShapeView<Self, Style> {
        _ShapeView(shape: self, shapeStyle: content, renderingStyle: .stroke(style))
    }

    public func stroke<Style: ShapeStyle>(
        _ content: Style,
        lineWidth: Float = 1
    ) -> _ShapeView<Self, Style> {
        stroke(content, style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> _ShapeView<Self, ForegroundStyle> {
        stroke(ForegroundStyle(), style: style)
    }

    public func stroke(lineWidth: Float = 1) -> _ShapeView<Self, ForegroundStyle> {
        stroke(ForegroundStyle(), lineWidth: lineWidth)
    }
}

public struct _ShapeView<Content: Shape, Style: ShapeStyle>: PrimitiveView, UnaryView {
    public let shape: Content
    public let shapeStyle: Style
    public let renderingStyle: ShapeRenderingStyle
    public static func _makeView(view: Self, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewOutputs(.shape(DisplayList.ShapeContent(
            shape: view.shape,
            style: view.shapeStyle,
            renderingStyle: view.renderingStyle,
            environment: inputs.environment
        )))
    }
}

public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: Float) -> InsetShape
}

extension InsettableShape {
    public func strokeBorder<Style: ShapeStyle>(
        _ content: Style,
        style: StrokeStyle,
        antialiased: Bool = true
    ) -> _ShapeView<InsetShape, Style> {
        var adjustedStyle = style
        adjustedStyle.lineWidth = max(0, style.lineWidth)
        return inset(by: adjustedStyle.lineWidth / 2)
            .stroke(content, style: adjustedStyle)
    }

    public func strokeBorder<Style: ShapeStyle>(
        _ content: Style,
        lineWidth: Float = 1,
        antialiased: Bool = true
    ) -> _ShapeView<InsetShape, Style> {
        strokeBorder(
            content,
            style: StrokeStyle(lineWidth: lineWidth),
            antialiased: antialiased
        )
    }

    public func strokeBorder(
        style: StrokeStyle,
        antialiased: Bool = true
    ) -> _ShapeView<InsetShape, ForegroundStyle> {
        strokeBorder(ForegroundStyle(), style: style, antialiased: antialiased)
    }

    public func strokeBorder(
        lineWidth: Float = 1,
        antialiased: Bool = true
    ) -> _ShapeView<InsetShape, ForegroundStyle> {
        strokeBorder(ForegroundStyle(), lineWidth: lineWidth, antialiased: antialiased)
    }
}

public enum RoundedCornerStyle: Equatable, Sendable {
    case circular
    case continuous
}

public struct Rectangle: InsettableShape {
    public var insetAmount: Float = 0
    public init() {

    }
    private init(insetAmount: Float) {
        self.insetAmount = insetAmount
    }
    public func path(in rect: ShapeRect) -> Path {
        Path { $0.addRect(rect.insetBy(dx: insetAmount, dy: insetAmount)) }
    }
    public func inset(by amount: Float) -> Rectangle {
        Rectangle(insetAmount: insetAmount + amount)
    }
}

public struct RoundedRectangle: InsettableShape {
    public var cornerSize: ShapeSize
    public var style: RoundedCornerStyle
    public var insetAmount: Float = 0

    public init(
        cornerSize: ShapeSize,
        style: RoundedCornerStyle = .continuous
    ) {
        self.cornerSize = cornerSize
        self.style = style
    }

    public init(
        cornerRadius: Float,
        style: RoundedCornerStyle = .continuous
    ) {
        precondition(cornerRadius.isFinite)
        self.init(
            cornerSize: ShapeSize(width: max(0, cornerRadius), height: max(0, cornerRadius)),
            style: style
        )
    }

    private init(
        cornerSize: ShapeSize,
        style: RoundedCornerStyle,
        insetAmount: Float
    ) {
        self.cornerSize = cornerSize
        self.style = style
        self.insetAmount = insetAmount
    }

    public func path(in rect: ShapeRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(
            roundedRect: insetRect,
            cornerSize: ShapeSize(
                width: max(0, cornerSize.width - insetAmount),
                height: max(0, cornerSize.height - insetAmount)
            ),
            style: style
        )
    }

    public func inset(by amount: Float) -> RoundedRectangle {
        RoundedRectangle(
            cornerSize: cornerSize,
            style: style,
            insetAmount: insetAmount + amount
        )
    }
}

public struct Capsule: InsettableShape {
    public var style: RoundedCornerStyle
    public var insetAmount: Float = 0
    public init(style: RoundedCornerStyle = .continuous) {
        self.style = style
    }
    private init(style: RoundedCornerStyle, insetAmount: Float) {
        self.style = style
        self.insetAmount = insetAmount
    }
    public func path(in rect: ShapeRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Path(
            roundedRect: insetRect,
            cornerRadius: min(insetRect.width, insetRect.height) / 2,
            style: style
        )
    }
    public func inset(by amount: Float) -> Capsule {
        Capsule(style: style, insetAmount: insetAmount + amount)
    }
}

public struct Ellipse: InsettableShape {
    public var insetAmount: Float = 0
    public init() {

    }
    private init(insetAmount: Float) {
        self.insetAmount = insetAmount
    }
    public func path(in rect: ShapeRect) -> Path {
        Path { $0.addEllipse(in: rect.insetBy(dx: insetAmount, dy: insetAmount)) }
    }
    public func inset(by amount: Float) -> Ellipse {
        Ellipse(insetAmount: insetAmount + amount)
    }
}

public struct Circle: InsettableShape {
    public var insetAmount: Float = 0
    public init() {

    }
    private init(insetAmount: Float) {
        self.insetAmount = insetAmount
    }
    public func path(in rect: ShapeRect) -> Path {
        let diameter = max(0, min(rect.width, rect.height) - insetAmount * 2)
        let circleRect = ShapeRect(
            x: rect.x + (rect.width - diameter) / 2,
            y: rect.y + (rect.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        return Path { $0.addEllipse(in: circleRect) }
    }
    public func inset(by amount: Float) -> Circle {
        Circle(insetAmount: insetAmount + amount)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize {
        let size = proposal.replacingUnspecifiedDimensions()
        let diameter = min(size.width, size.height)
        return EmbeddedSize(width: diameter, height: diameter)
    }
}

extension Shape where Self == Rectangle {
    public static var rect: Rectangle { .init() }
}

extension Shape where Self == RoundedRectangle {
    public static func rect(
        cornerSize: ShapeSize,
        style: RoundedCornerStyle = .continuous
    ) -> RoundedRectangle {
        .init(cornerSize: cornerSize, style: style)
    }

    public static func rect(
        cornerRadius: Float,
        style: RoundedCornerStyle = .continuous
    ) -> RoundedRectangle {
        .init(cornerRadius: cornerRadius, style: style)
    }
}

extension Shape where Self == Capsule {
    public static var capsule: Capsule { .init() }
    public static func capsule(style: RoundedCornerStyle) -> Capsule {
        .init(style: style)
    }
}

extension Shape where Self == Ellipse {
    public static var ellipse: Ellipse { .init() }
}

extension Shape where Self == Circle {
    public static var circle: Circle { .init() }
}
