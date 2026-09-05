import EmbeddedSwiftUI

struct TiktokLoadingView: View {
    @State private var isSwapped = false

    private static let halfCycleDuration: Double = 0.49
    private static let indicatorSize: Double = 54
    private static let ballDiameter: Double = 12
    private static let travelDistance: Double = 8

    var body: some View {
        ZStack {
            LoadingBall(
                isSwapped: isSwapped,
                color: Color(red: 37 / 255, green: 244 / 255, blue: 238 / 255),
                direction: -1,
                initialScale: 1.18,
                finalScale: 0.72,
                initialOpacity: 1.0,
                finalOpacity: 0.88,
                initialZIndex: 1,
                finalZIndex: 0
            )

            LoadingBall(
                isSwapped: isSwapped,
                color: Color(red: 254 / 255, green: 44 / 255, blue: 85 / 255),
                direction: 1,
                initialScale: 0.72,
                finalScale: 1.18,
                initialOpacity: 0.88,
                finalOpacity: 1.0,
                initialZIndex: 0,
                finalZIndex: 1
            )
        }
        .frame(
            width: TiktokLoadingView.indicatorSize,
            height: TiktokLoadingView.indicatorSize
        )
        .onAppear {
            guard !isSwapped else { return }
            withAnimation(
                .easeInOut(duration: TiktokLoadingView.halfCycleDuration)
                    .repeatForever(autoreverses: true)
            ) {
                isSwapped = true
            }
        }
    }

    struct LoadingBall: View {
        var isSwapped: Bool

        var color: Color
        var direction: Double
        var initialScale: Double
        var finalScale: Double
        var initialOpacity: Double
        var finalOpacity: Double
        var initialZIndex: Double
        var finalZIndex: Double

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: ballDiameter, height: ballDiameter)
                .scaleEffect(isSwapped ? finalScale : initialScale)
                .opacity(isSwapped ? finalOpacity : initialOpacity)
                .offset(
                    x: direction * (isSwapped ? -travelDistance : travelDistance)
                )
                .zIndex(isSwapped ? finalZIndex : initialZIndex)
        }
    }
}
