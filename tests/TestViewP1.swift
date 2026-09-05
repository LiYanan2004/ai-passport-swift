#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import EmbeddedSwiftUI

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

private struct Provider: RendererProvider {
    var configuration: RendererConfiguration

    init(horizontalRoot: Bool = false, maximumNodes: Int = 64) {
        configuration = RendererConfiguration(
            maximumNodes: maximumNodes, maximumDepth: 16, maximumDimension: 32767,
            defaultSpacing: 0, defaultPadding: EdgeInsets(), listSpacing: 0,
            defaultFont: .body, defaultForegroundColor: .white,
            implicitRootLayout: VStackLayout(),
            systemColor: { _ in Color.Resolved(rgb: 0xffffff) }
        )
        if horizontalRoot { configuration.implicitRootLayout = _AnyLayout(HStackLayout()) }
    }

    func measureText(_ text: String, environment: RenderEnvironment, proposal: ProposedViewSize) -> EmbeddedSize {
        EmbeddedSize(width: 10, height: 10)
    }

    func imageSize(named name: String) -> EmbeddedSize? { nil }
}

private func layout<Content: View>(_ content: Content, provider: Provider = Provider()) -> DisplayList? {
    let host = EmbeddedViewHost { content }
    let outputs = host.makeViewOutputs(configuration: provider.configuration)
    var layout = DisplayListLayout(provider: provider, transaction: Transaction(), previousAnimations: [:])
    return layout.update(
        outputs.displayList, size: EmbeddedSize(width: 100, height: 100),
        alignment: .topLeading, version: DisplayList.Version()
    )?.displayList
}

private func leafFrames(_ list: DisplayList) -> [EmbeddedRect] {
    var result: [EmbeddedRect] = []
    var pending = list.items.reversed().map { ($0, EmbeddedPoint()) }
    while let (item, parent) = pending.popLast() {
        let origin = EmbeddedPoint(x: parent.x + item.frame.x, y: parent.y + item.frame.y)
        switch item.value {
        case .shape, .text:
            result.append(EmbeddedRect(x: origin.x, y: origin.y, width: item.frame.width, height: item.frame.height))
        default: break
        }
        pending.append(contentsOf: item.children.reversed().map { ($0, origin) })
    }
    return result
}

private struct CustomPadding: ViewModifier {
    func body(content: Content) -> some View { content.padding(0) }
}

private func testImplicitRoots() {
    let rows = ForEach(0..<2) { Text("\($0)") }
    let root = leafFrames(layout(rows.padding(0))!)
    let nested = leafFrames(layout(VStack { rows.padding(0) })!)
    check(root.map(\.y) == [0, 10], "root rows use vertical implicit layout")
    check(nested.map(\.y) == [0, 10], "nested unary modifier preserves implicit root")
    let framed = leafFrames(layout(VStack { rows.frame(width: 20, height: 30, alignment: .topLeading) })!)
    check(framed.map(\.y) == [0, 10], "frame preserves multi-row implicit root")
    let custom = leafFrames(layout(VStack { rows.modifier(CustomPadding()) })!)
    check(custom.map(\.y) == [0, 10], "custom modifier Content preserves implicit root")
    let horizontal = leafFrames(layout(VStack { rows.padding(0) }, provider: Provider(horizontalRoot: true))!)
    check(horizontal.map(\.x) == [0, 10], "implicit root follows adaptor layout")
    check(layout(VStack { EmptyView().padding(0) }) != nil, "empty unary content remains valid")
}

private final class Actions {
    var increment: (() -> Void)?
    var value = -1
}

private struct CapturedState: View {
    @State private var count = 0
    let actions: Actions

    var body: some View {
        actions.value = count
        actions.increment = { count += 1 }
        return Text("\(count)")
    }
}

private final class Visibility {
    var isVisible = true
}

private struct ConditionalState: View {
    let visibility: Visibility
    let child: CapturedState
    var body: some View {
        if visibility.isVisible { child }
    }
}

private func commit<Content: View>(_ host: EmbeddedViewHost<Content>) {
    _ = host.makeViewOutputs(configuration: Provider().configuration)
    host.acknowledgeRender(startedAt: host.currentRevision)
}

private func testStateInstallations() {
    let actions = Actions()
    let root = CapturedState(actions: actions)
    let host = EmbeddedViewHost { root }
    commit(host)
    let oldAction = actions.increment!
    oldAction()
    commit(host)
    check(actions.value == 1, "current capture writes state")
    host.unmount()
    commit(host)
    let newAction = actions.increment!
    oldAction()
    check(!host.needsRender, "old capture cannot invalidate remount")
    commit(host)
    check(actions.value == 0, "old capture cannot write remounted state")
    newAction()
    commit(host)
    check(actions.value == 1, "new capture remains installed across updates")

    let visibility = Visibility()
    let childActions = Actions()
    let conditional = ConditionalState(visibility: visibility, child: CapturedState(actions: childActions))
    let conditionalHost = EmbeddedViewHost { conditional }
    commit(conditionalHost)
    let removedAction = childActions.increment!
    visibility.isVisible = false
    commit(conditionalHost)
    visibility.isVisible = true
    commit(conditionalHost)
    removedAction()
    commit(conditionalHost)
    check(childActions.value == 0, "removed child capture cannot write reinserted state")
    childActions.increment?()
    commit(conditionalHost)
    check(childActions.value == 1, "reinserted child capture writes current state")
}

private struct Flexible: Shape {
    func path(in rect: ShapeRect) -> Path { Path(rect) }
    func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize {
        EmbeddedSize(width: max(10, proposal.width ?? 10), height: max(10, proposal.height ?? 10))
    }
}

private func testPriorityGroups() {
    let horizontal = leafFrames(layout(HStack(spacing: 0) {
        Flexible().layoutPriority(1)
        Flexible()
    })!)
    check(horizontal.map(\.width) == [90, 10], "horizontal priority reserves lower minimum")
    let vertical = leafFrames(layout(VStack(spacing: 0) {
        Flexible()
        Flexible().layoutPriority(1)
    })!)
    check(vertical.map(\.height) == [10, 90], "vertical priority is independent of source order")
    let equal = leafFrames(layout(HStack(spacing: 0) { Flexible(); Flexible() })!)
    check(equal.map(\.width) == [50, 50], "equal priorities share space")
    let grouped = leafFrames(layout(HStack(spacing: 0) {
        Flexible().layoutPriority(1)
        Flexible().layoutPriority(1)
        Flexible()
    })!)
    check(grouped.map(\.width) == [45, 45, 10], "priority group shares only its own budget")
}

private final class FactoryCalls {
    var count = 0
    func row() -> Text {
        count += 1
        return Text("row")
    }
}

private func testConstructionBudget() {
    let calls = FactoryCalls()
    let nested = ForEach(0..<64) { _ in ForEach(0..<64) { _ in calls.row() } }
    check(layout(nested) == nil, "oversized nested tree is rejected")
    check(calls.count <= 64, "nested factories stop at shared budget")
    let emptyCalls = FactoryCalls()
    let emptyRows = ForEach(0..<64) { _ in
        ForEach(0..<64) { _ in
            emptyCalls.count += 1
            return EmptyView()
        }
    }
    check(layout(emptyRows) == nil, "empty rows still consume construction work")
    check(emptyCalls.count <= 64, "empty row work is bounded")
    let siblingCalls = FactoryCalls()
    let siblings = VStack {
        ForEach(0..<5) { _ in siblingCalls.row() }.foregroundColor(.red)
        ForEach(0..<5) { _ in siblingCalls.row() }.foregroundColor(.blue)
    }
    check(layout(siblings, provider: Provider(maximumNodes: 8)) == nil, "siblings share budget across input copies")
    check(siblingCalls.count <= 8, "sibling factories stop on exhaustion")
    let small = ForEach(0..<2) { _ in ForEach(0..<2) { _ in Text("small") } }
    check(leafFrames(layout(small)!).count == 4, "small nested collections remain valid")
    check(leafFrames(layout(small)!).count == 4, "next update has a fresh construction budget")
}

@main
private struct TestViewP1 {
    static func main() {
        testImplicitRoots()
        testStateInstallations()
        testPriorityGroups()
        testConstructionBudget()
        fflush(nil)
        precondition(failures == 0, "P1 View regressions")
        print("P1 View regressions: PASS")
    }
}
