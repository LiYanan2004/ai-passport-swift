import EmbeddedSwiftUI

struct BatteryLevelArc: Shape {
    private static let startAngle = 145.0 * Double.pi / 180
    private static let angularLength = 250.0 * Double.pi / 180
    private static let minimumSegmentLimit = 8
    private static let maximumSegmentLimit = 24
    private static let pointsPerDimension: Double = 1.0 / 6
    private static let outerRadiusScale = 0.44
    private static let lineWidthScale = 10.0 / 180

    let level: Double

    func path(in rect: ShapeRect) -> Path {
        guard level > 0 else { return Path() }

        let minimumDimension = Double(min(rect.width, rect.height))
        let segmentLimit = min(
            Self.maximumSegmentLimit,
            max(Self.minimumSegmentLimit, Int(minimumDimension * Self.pointsPerDimension))
        )
        let segmentCount = max(1, Int((Double(segmentLimit) * level).rounded(.up)))
        let centerX = Double(rect.x + rect.width / 2)
        let centerY = Double(rect.y + rect.height / 2)
        let outerRadius = minimumDimension * Self.outerRadiusScale
        let innerRadius = max(0, outerRadius - minimumDimension * Self.lineWidthScale)
        let endAngle = Self.startAngle + Self.angularLength * level

        func point(at angle: Double, radius: Double) -> ShapePoint {
            ShapePoint(
                x: Float(centerX + cos(angle) * radius),
                y: Float(centerY + sin(angle) * radius)
            )
        }

        var path = Path()
        path.move(to: point(at: Self.startAngle, radius: outerRadius))
        for segmentIndex in 1...segmentCount {
            let progress = Double(segmentIndex) / Double(segmentCount)
            path.addLine(to: point(
                at: Self.startAngle + (endAngle - Self.startAngle) * progress,
                radius: outerRadius
            ))
        }
        for segmentIndex in stride(from: segmentCount, through: 0, by: -1) {
            let progress = Double(segmentIndex) / Double(segmentCount)
            path.addLine(to: point(
                at: Self.startAngle + (endAngle - Self.startAngle) * progress,
                radius: innerRadius
            ))
        }
        path.closeSubpath()
        return path
    }
}
