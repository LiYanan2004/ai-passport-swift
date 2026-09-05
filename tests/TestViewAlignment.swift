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

private struct StatefulRoot: View {
    @State var count = 0
    var body: some View { Text("\(count)") }
}

private struct StatefulModifier: ViewModifier {
    @State var count = 0
    func body(content: Content) -> some View {
        content
        Text("\(count)")
    }
}

@propertyWrapper
private struct Counter: DynamicProperty {
    @EmbeddedSwiftUI.State var value = 0
    var wrappedValue: Int {
        get { value }
        nonmutating set { value = newValue }
    }
}

private struct WrappedRoot: View {
    @Counter var count: Int
    var body: some View { Text("\(count)") }
}

private struct HalfWidth: Shape {
    func path(in rect: ShapeRect) -> Path { Path(rect) }
    func sizeThatFits(_ proposal: ProposedViewSize) -> EmbeddedSize {
        EmbeddedSize(width: (proposal.width ?? 100) / 2, height: 10)
    }
}

private final class AlignmentCalls {
    var count = 0
}

private struct RecordingViewTypeVisitor: ViewTypeVisitor {
    var visited = false

    mutating func visit<Content: View>(type: Content.Type) {
        visited = true
    }
}

private struct ExplicitCenterLayout: Layout {
    let calls: AlignmentCalls

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> EmbeddedSize {
        EmbeddedSize(width: 20, height: 20)
    }

    func placeSubviews(
        in bounds: EmbeddedRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Void
    ) {
        for child in subviews {
            child.place(
                at: EmbeddedPoint(x: bounds.x, y: bounds.y),
                proposal: ProposedViewSize(width: 20, height: 20)
            )
        }
    }

    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: EmbeddedRect,
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> Int32? {
        calls.count += 1
        return guide == .center ? 0 : nil
    }
}

private struct AlignmentProvider: RendererProvider {
    let configuration = RendererConfiguration(
        maximumNodes: 64, maximumDepth: 16, maximumDimension: 32767,
        defaultSpacing: 0, defaultPadding: EdgeInsets(),
        listSpacing: 0, defaultFont: .body, defaultForegroundColor: .white,
        implicitRootLayout: VStackLayout(),
        systemColor: { _ in Color.Resolved(rgb: 0xFFFFFF) }
    )

    func measureText(
        _ text: String, environment: RenderEnvironment, proposal: ProposedViewSize
    ) -> EmbeddedSize {
        EmbeddedSize(width: 10, height: 10)
    }

    func imageSize(named name: String) -> EmbeddedSize? { nil }
}

private func render<Content: View>(_ content: Content) -> DisplayList {
    let provider = AlignmentProvider()
    let host = EmbeddedViewHost { content }
    let outputs = host.makeViewOutputs(configuration: provider.configuration)
    var layout = DisplayListLayout(
        provider: provider, transaction: Transaction(), previousAnimations: [:]
    )
    return layout.update(
        outputs.displayList, size: EmbeddedSize(width: 100, height: 60),
        alignment: .topLeading, version: DisplayList.Version()
    )!.displayList
}

private func shapeFrame(
    _ items: [DisplayList.Item], offset: EmbeddedPoint = EmbeddedPoint(x: 0, y: 0)
) -> EmbeddedRect? {
    for item in items {
        let origin = EmbeddedPoint(x: offset.x + item.frame.x, y: offset.y + item.frame.y)
        if case .shape = item.value {
            return EmbeddedRect(x: origin.x, y: origin.y, width: item.frame.width, height: item.frame.height)
        }
        if let frame = shapeFrame(item.children, offset: origin) { return frame }
    }
    return nil
}

private func testBindingLifetime() {
    let root = StatefulRoot()
    let host = EmbeddedViewHost { root }
    _ = host.makeViewOutputs()
    host.acknowledgeRender(startedAt: host.currentRevision)
    let oldBinding = root.$count
    oldBinding.wrappedValue = 5
    check(root.count == 5, "installed binding writes state")
    host.unmount()
    _ = host.makeViewOutputs()
    host.acknowledgeRender(startedAt: host.currentRevision)
    oldBinding.wrappedValue = 42
    check(root.count == 0, "stale binding cannot write remounted state")
    check(!host.needsRender, "stale binding cannot invalidate remounted host")
    root.$count.wrappedValue = 7
    check(root.count == 7, "new projection writes remounted state")
}

private func testComposedModifierProperties() {
    let first = StatefulModifier()
    let second = StatefulModifier()
    let composed = ModifiedContent(content: first, modifier: second)
    let host = EmbeddedViewHost { Text("content").modifier(composed) }
    _ = host.makeViewOutputs()
    first.count = 9
    second.count = 4
    check(first.count == 9 && second.count == 4, "composed modifiers install separate states")

    let listHost = EmbeddedViewHost { VStack { Text("content").modifier(composed) } }
    _ = listHost.makeViewOutputs()
    check(first.count == 9 && second.count == 4, "separate host does not replace first host state")
}

private func testLayoutProposals() {
    let plain = shapeFrame(render(HalfWidth()).items)!
    let padded = shapeFrame(render(HalfWidth().padding(0)).items)!
    check(plain.width == 50, "plain shape receives parent proposal")
    check(padded.width == plain.width, "zero padding preserves proposal-sensitive size")
}

private func testExplicitAlignment() {
    let calls = AlignmentCalls()
    let view = ExplicitCenterLayout(calls: calls) { Rectangle() }
        .frame(width: 100, height: 20, alignment: .center)
    let frame = shapeFrame(render(view).items)!
    check(calls.count > 0, "explicit alignment callback is evaluated")
    check(frame.x == 50, "parent consumes explicit center guide")
}

private func testTransactionsAndCustomProperties() {
    let root = WrappedRoot()
    let host = EmbeddedViewHost { root }
    _ = host.makeViewOutputs()
    host.acknowledgeRender(startedAt: host.currentRevision)
    withAnimation(.linear(duration: 2)) { root.count = 7 }
    withTransaction(Transaction()) {}
    check(root.count == 7, "custom dynamic property installs nested state")
    check(host.transactionForUpdate(Transaction()).animation?.duration == 2, "empty scope preserves pending transaction")

    let other = StatefulRoot()
    let otherHost = EmbeddedViewHost { other }
    _ = otherHost.makeViewOutputs()
    other.$count.animation(.linear(duration: 4)).wrappedValue = 5
    check(otherHost.transactionForUpdate(Transaction()).animation?.duration == 4, "binding carries animation")
    check(host.transactionForUpdate(Transaction()).animation?.duration == 2, "hosts keep separate transactions")
    other.$count.animation(nil).wrappedValue = 6
    check(otherHost.transactionForUpdate(Transaction()).animation == nil, "explicit nil clears binding animation")
}

private func testStableIdentityOwnership() {
    let identities = DisplayList.StableIdentityRoot()
    let stable = DisplayList.StableIdentity(scope: _ViewList_ID().appending(.explicit(.init(7))))
    identities.beginUpdate()
    let first = identities.identity(for: stable)
    identities.commit()
    identities.beginUpdate()
    check(identities.identity(for: stable) == first, "live stable identity retains display instance")
    identities.commit()
    identities.beginUpdate()
    identities.commit()
    identities.beginUpdate()
    check(identities.identity(for: stable) != first, "removed stable identity receives new display instance")
    identities.commit()
}

private func testViewListTraversal() {
    func list(_ rows: [Int]) -> _StaticViewList {
        let view = ForEach(rows, id: \.self) { Text("\($0)") }
        return type(of: view).makeDebuggableViewList(view: view, inputs: _ViewListInputs()).views
    }
    let first = list([1, 2])
    var second = list([2, 3])
    check(first.ids.count == 2, "view list retains element IDs")
    let style = _ViewList_IteratorStyle(granularity: 2)
    check(first.count(style: style) == 4, "iterator granularity affects count")
    check(first.firstOffset(forID: 2, style: style) == 2, "explicit ID resolves offset")
    var start = 2
    var transform = _ViewList_SublistTransform()
    var visited: [_ViewList_ID] = []
    _ = first.applyNodes(from: &start, style: style, list: nil, transform: &transform) { _, _, node, _ in
        if case let .sublist(sublist) = node { visited.append(sublist.id) }
        return true
    }
    check(visited == [first.ids[1]], "traversal resumes at requested offset")
    second.recordEdits(from: first, transaction: TransactionID(value: 2))
    check(second.edit(forID: first.ids[0], since: TransactionID(value: 1)) == .removed, "removed ID is reported")
    check(second.edit(forID: second.ids[1], since: TransactionID(value: 1)) == .inserted, "inserted ID is reported")
}

private func testAppearancePhase() {
    var appeared = 0
    var disappeared = 0
    var modifier = _AppearanceActionModifier(appear: { appeared += 1 }, disappear: { disappeared += 1 })
    var effect = AppearanceEffect(modifier: modifier)
    effect.updateValue(modifier: modifier)
    effect.updateValue(modifier: modifier)
    check(appeared == 1, "appearance is idempotent within phase")
    modifier.phase.resetSeed = 1
    effect.updateValue(modifier: modifier)
    check(appeared == 2 && disappeared == 1, "new phase resets visible effect")
    modifier.phase.isBeingRemoved = true
    effect.updateValue(modifier: modifier)
    check(disappeared == 2, "removed phase emits disappearance")
}

private func testViewConstructionCompatibilitySurface() {
    let adaptor = _UnaryViewAdaptor(Text("content"))
    let outputs = type(of: adaptor).makeDebuggableViewList(
        view: adaptor,
        inputs: _ViewListInputs()
    )
    check(outputs.views.staticCount == 1, "unary adaptor produces one view-list element")
    check(!outputs.displayList.commands.isEmpty, "unary adaptor forwards wrapped content")

    var visitor = RecordingViewTypeVisitor()
    visitor.visit(type: Text.self)
    check(visitor.visited, "view type visitor accepts a concrete View type")
}

@main
private struct TestViewAlignment {
    static func main() {
        testBindingLifetime()
        testComposedModifierProperties()
        testLayoutProposals()
        testExplicitAlignment()
        testTransactionsAndCustomProperties()
        testStableIdentityOwnership()
        testViewListTraversal()
        testAppearancePhase()
        testViewConstructionCompatibilitySurface()
        fflush(nil)
        precondition(failures == 0, "View alignment regressions")
        print("View alignment tests: PASS")
    }
}
