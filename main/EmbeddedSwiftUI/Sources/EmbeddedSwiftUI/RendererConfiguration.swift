// Embedded adaptation: values supplied by OpenSwiftUI's platform glue become
// explicit renderer inputs. Memory budgets, metrics, defaults, and system
// colors stay outside the portable core and can vary by adaptor or device.

public struct RendererConfiguration {
    // This is device policy, not upstream _RendererConfiguration's renderer
    // selection enum. CoreGlue's implicit-root selection is injected here.
    package var implicitRootLayout: _AnyLayout
    public var maximumNodes: Int
    public var maximumDepth: Int
    public var maximumDimension: Int32
    public var defaultSpacing: Int32
    public var defaultPadding: EdgeInsets
    public var listSpacing: Int32
    public var defaultFont: Font
    public var defaultForegroundColor: Color
    public var systemColor: (SystemColorType) -> Color.Resolved

    public init<RootLayout: Layout>(
        maximumNodes: Int,
        maximumDepth: Int,
        maximumDimension: Int32,
        defaultSpacing: Int32,
        defaultPadding: EdgeInsets,
        listSpacing: Int32,
        defaultFont: Font,
        defaultForegroundColor: Color,
        implicitRootLayout: RootLayout,
        systemColor: @escaping (SystemColorType) -> Color.Resolved
    ) {
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
        self.maximumDimension = maximumDimension
        self.defaultSpacing = defaultSpacing
        self.defaultPadding = defaultPadding
        self.listSpacing = listSpacing
        self.defaultFont = defaultFont
        self.defaultForegroundColor = defaultForegroundColor
        self.implicitRootLayout = _AnyLayout(implicitRootLayout)
        self.systemColor = systemColor
    }
}

package protocol RendererProvider {
    var configuration: RendererConfiguration { get }
    func measureText(
        _ text: String,
        environment: RenderEnvironment,
        proposal: ProposedViewSize
    ) -> EmbeddedSize
    func imageSize(named name: String) -> EmbeddedSize?
}
