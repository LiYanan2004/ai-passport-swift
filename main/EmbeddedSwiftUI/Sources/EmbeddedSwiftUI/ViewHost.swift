//
//  EmbeddedViewHost.swift
//  EmbeddedSwiftUICore

/// Retains a root value and its state between synchronous construction passes.
///
/// Construct content inside the builder so its state can invalidate this host.
/// The platform requests `_ViewOutputs` when `needsRender` is true and owns
/// scheduling, rendering, input dispatch, and scene replacement.
public final class EmbeddedViewHost<Content: View> {
    private let content: Content
    private let graph = ViewGraph()
    private var renderedRevision: UInt64?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var needsRender: Bool { renderedRevision != graph.host.revision }

    package var retainedContent: Content { content }
    package var currentRevision: UInt64 { graph.host.revision }

    package func acknowledgeRender(startedAt revision: UInt64) {
        renderedRevision = revision
        graph.host.acknowledgeRender(startedAt: revision)
        graph.commit()
    }

    package func transactionForUpdate(_ transaction: Transaction) -> Transaction {
        graph.host.transactionForUpdate(transaction)
    }

    package func makeViewOutputs(
        transaction: Transaction = Transaction(),
        configuration: RendererConfiguration? = nil
    ) -> _ViewOutputs {
        graph.beginUpdate()
        defer { graph.endUpdate() }
        var inputs = _ViewInputs()
        inputs.graph = graph
        inputs.phase = graph.phase
        inputs.transaction = transactionForUpdate(transaction)
        inputs.configuration = configuration
        inputs.environment.systemColorDefinition = configuration?.systemColor
        return Content.makeDebuggableView(view: content, inputs: inputs)
    }

    /// Requests another construction pass, for example after a renderer failure.
    public func invalidate() {
        graph.invalidate()
    }

    /// Marks retained state for a fresh mount.
    public func unmount() {
        graph.unmount()
    }
}
