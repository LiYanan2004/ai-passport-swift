import EmbeddedSwiftUI

struct BluetoothSymbol: Shape {
    private static let lineWidthScale: Float = 7 / 180

    func path(in rect: ShapeRect) -> Path {
        let centerX = rect.x + rect.width * 0.492
        let topY = rect.y + rect.height * 0.341
        let upperBranchY = rect.y + rect.height * 0.428
        let lowerBranchY = rect.y + rect.height * 0.572
        let bottomY = rect.y + rect.height * 0.659
        let leftX = rect.x + rect.width * 0.415
        let rightX = rect.x + rect.width * 0.575
        let lineWidth = min(rect.width, rect.height) * Self.lineWidthScale

        var path = Path()
        addLine(
            from: ShapePoint(x: centerX, y: topY),
            to: ShapePoint(x: rightX, y: upperBranchY),
            width: lineWidth,
            to: &path
        )
        addLine(
            from: ShapePoint(x: rightX, y: upperBranchY),
            to: ShapePoint(x: leftX, y: lowerBranchY),
            width: lineWidth,
            to: &path
        )
        addLine(
            from: ShapePoint(x: centerX, y: bottomY),
            to: ShapePoint(x: rightX, y: lowerBranchY),
            width: lineWidth,
            to: &path
        )
        addLine(
            from: ShapePoint(x: rightX, y: lowerBranchY),
            to: ShapePoint(x: leftX, y: upperBranchY),
            width: lineWidth,
            to: &path
        )
        addLine(
            from: ShapePoint(x: centerX, y: topY),
            to: ShapePoint(x: centerX, y: bottomY),
            width: lineWidth,
            to: &path
        )
        return path
    }

    private func addLine(
        from start: ShapePoint,
        to end: ShapePoint,
        width: Float,
        to path: inout Path
    ) {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = max(0.001, (deltaX * deltaX + deltaY * deltaY).squareRoot())
        let offsetX = -deltaY / length * width / 2
        let offsetY = deltaX / length * width / 2
        path.move(to: ShapePoint(x: start.x + offsetX, y: start.y + offsetY))
        path.addLine(to: ShapePoint(x: end.x + offsetX, y: end.y + offsetY))
        path.addLine(to: ShapePoint(x: end.x - offsetX, y: end.y - offsetY))
        path.addLine(to: ShapePoint(x: start.x - offsetX, y: start.y - offsetY))
        path.closeSubpath()
    }
}
