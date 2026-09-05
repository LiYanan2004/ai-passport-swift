English | [简体中文](embedded-swiftui.zh_CN.md)

# EmbeddedSwiftUI MVP

The entry point in `main/Main.swift` declares `PassportApplication: App`, whose
body returns `ConnectivityStatusView` by default. The full
`EmbeddedSwiftUIDemoView` List remains a source-level demo exercised by host
regressions. The firmware has one permanent display, so the embedded `App`
protocol uses `View` as its body and has no `Scene` or `WindowGroup` layer.
`PassportApplication.init()` initializes the platform. The LVGL adaptor
provides `App.main()`, constructs the application, mounts its root UI, and
starts the timers directly. The lightweight LVGL host presents the root view
directly on a black screen. A permanent Swift worker caches CW2017 battery level,
Bluetooth controller/NimBLE connection state, and connected Wi-Fi station RSSI;
the view refreshes changed values once per second. The MVP does not start Agent
Monitor, BLE, Wi-Fi, audio, legacy pages, or the previous pixel-theme UI.
The previous application remains in
`main/legacy/AgentMonitorApplication.swift`, but its build is temporarily
outside the supported configuration.

In the full gallery, UP/DOWN scroll the ten-row List and OK animates the accent
panel while preserving List identity and scroll offset. Input callbacks enqueue
events without waiting; a 20 ms LVGL timer drains at most 16 events per tick
and coalesces their state changes into one render.

## Supported API and limits

- `View`, `_UnaryViewAdaptor`, custom body, `ViewBuilder`, optional/conditional children, `EmptyView`.
- Synchronous `ViewModifier` and `ModifiedContent` composition for
  custom and primitive modifiers. Trait writing, appearance actions,
  value-tracked animation, environment values, renderer effects, geometry
  effects, and focusable scopes use this path.
- `App` with a root `View` body and an LVGL-adaptor-provided default `main()`.
- `EmbeddedViewHost`, `RootGeometry`, `EmbeddedSize`, `EmbeddedRect`, and
  `ProposedViewSize`. The host retains `@State` by view identity and synchronously builds
  `_ViewOutputs`; it owns no renderer or physical-input API.
- `VStack`, `HStack`, `ZStack`, `Spacer(minLength:)`, horizontal/vertical
  alignment and nine frame alignments. `Spacer` accepts the remaining proposed
  size after fixed-size stack children. `zIndex(_:)` controls overlapping
  sibling draw order; equal values retain source order. The default value is
  zero, so `ZStack` draws later unmodified children above earlier children.
- Floating-point `Path` move, line, quadratic curve, cubic curve, and close
  commands; `Shape`, `ShapeStyle`, `FillStyle`, `StrokeStyle`, and
  `InsettableShape`; `Rectangle`, `RoundedRectangle`, `Capsule`, `Ellipse`, and
  `Circle`; and `fill`, `stroke`, and inset `strokeBorder` modifiers. Unstyled
  shapes inherit the current foreground color. Rounded rectangles accept
  `cornerSize`, `cornerRadius`, and `RoundedCornerStyle`.
- The Embedded `Layout` contract, non-generic `LayoutSubviews` and
  `LayoutSubview` proxies, callable custom layouts, and `VStackLayout` and
  `HStackLayout`.
- `Transaction`, `withTransaction`, `withAnimation`, and
  `View.animation(_:value:)` follow the corresponding OpenSwiftUICore API
  shapes. An implicit animation starts only after its `Equatable` value changes;
  the first mount and unchanged values do not animate. A transaction with
  `disablesAnimations` suppresses both explicit and value-driven animation.
- `Animation` provides linear and easing Bézier curves, custom cubic Bézier
  control points, physical spring evaluation, sequence-sensitive `delay` and
  `speed`, and finite or continuous repetition with optional autoreverse.
  LVGL crossfades the replaced root subtree when both trees fit the adaptor
  budget, removes the outgoing subtree after the first segment, and cancels
  retained animation callbacks when the renderer unmounts or a newer replacement
  supersedes them. Trees containing bitmap masks use identity-matched local
  animation without overlapping full roots.
- `List { ... }`, `List(0..<10) { ... }`, keyed collection/range `ForEach` and `ScrollView`
  with axis sets and optional indicators. Lists are eager, without selection,
  row recycling or editing. The same 64-node budget includes offscreen rows.
  LVGL clips scrolling content to the viewport.
- `font`, `foregroundColor`: inherited by descendants; inner values override.
- `@State`, `@Binding`, generic environment keys, `@Environment`, and `id(_:)`.
  The build-host SwiftSyntax generator registers stored dynamic properties
  before body evaluation.
- Named `Image` content uses the hosting controller's optional `imageResolver`;
  a missing asset fails the update and preserves the previous scene.
- Generic `background(View)`, `offset`, `padding`, `EdgeInsets`, and fixed
  `frame` use `_BackgroundModifier`, `_OffsetEffect`, `_PaddingLayout`, and
  `_FrameLayout`. Flexible frame constraints and the desktop graph-based
  layout runtime are not included.
- `Font.system(size:)`, text styles from largeTitle through caption2. Sizes map
  to the nearest compiled Montserrat 12/14/16/18/20/24/28 face. Weights, custom
  fonts and Dynamic Type are not implemented; these are regular bitmap faces.
- `onPhysicalButton` and `PhysicalButton` live in `LVGLRendererAdaptor`.
  Scroll containers focus automatically; `focusable` and the adaptor renderer
  support focus traversal. There is no general spatial focus engine.

PRESS dispatches each physical button, while a long UP or DOWN repeats scrolling.
CLICK, DOUBLE and long OK are ignored. Unhandled UP/DOWN input scrolls the focused
container, including horizontal containers on this three-button board. Handled
view input reevaluates the root view; scroll-only input retains all nodes. The
core host retains state in children reconstructed by `body`, associates it with
structural/explicit identity, and invalidates after writes. Removed state
locations reject stale bindings. Independent `.animation(_:value:)` scopes
produce independent item transactions; lifecycle and scroll restoration also
use identity. The backend still mounts a replacement tree. General gestures,
row recycling, and arbitrary custom Animatable interpolation remain outside
this profile.

## Reference source alignment

The implementation combines the supplied Embedded source subset with the
corresponding OpenSwiftUICore View, modifier, layout, animation, environment,
effect, and DisplayList sources. `UPSTREAM.json` records every mapping and
intentional omission. `EmbeddedRenderSink` and the embedded reference renderer
are omitted because they duplicate View responsibilities and platform
rendering.

Construction enters through `_makeView`, `_makeViewList`, and
`_viewListCount`. `_ViewInputs`, `_ViewOutputs`, `_ViewListInputs`,
`_ViewListOutputs`, `ViewList`, `ViewVisitor`, `PrimitiveView`, `UnaryView`,
and `MultiView` retain their upstream entry-point names. AttributeGraph and
`_GraphValue` parameters are omitted; the complete upstream graph, preference,
and ViewList traversal contracts are not included.

`DisplayList` is the only portable renderer output. Identity scopes retain
nested child lists instead of repeatedly flattening command arrays. Parsing
and LVGL item mounting use explicit frame stacks, preserving traversal order
without recursive native frames. `ViewModifier`,
`PrimitiveViewModifier`, `UnaryViewModifier`, `MultiViewModifier`,
`_ViewModifier_Content`, and `ModifiedContent` provide synchronous composition.
`EnvironmentValues`, `_EnvironmentKeyWritingModifier`, `Animatable`,
`GeometryEffect`, `_RendererEffect`, and `RendererEffect` use their upstream
roles. `ViewTraitCollection` remains synchronous. `DisplayListLayout` measures
through proposal-aware proxies before emitting identified, positioned
`DisplayList.Item` values. `RendererProvider` supplies real text/image metrics
and configuration defaults; LVGL only mounts and animates the resolved items.
This document records the exact adaptations and remaining scope.

The reviewed profile installs every composed modifier's dynamic properties,
binds projections to their original installed location and keeps transactions
per host. Typed property boxes and ID/appearance phases replace graph-backed
lifecycle evaluation. Display instance IDs are mapped separately from stable
identities. Eager ViewList exposes ID/trait metadata, resumable traversal and
single-update edit snapshots. Custom alignment guides, Layout spacing and stack
orientation are consumed during placement; placement uses an explicit work
stack and retains each child's measurement proposal. Configuration now requires
the adaptor's `implicitRootLayout`. LVGL retargets unchanged native animations
without restarting their time/phase, accepts empty paths and rejects negative
scale/reflection matrices. These constraints are covered by
`tests/TestViewAlignment.swift` and the LVGL host suite.

`UPSTREAM.json` records reference-to-local filenames, SHA-256 values and every
documented adaptation. It also lists implementations whose embedded constraints
require a nearby `Embedded adaptation:` source comment. Host validation checks
both with `tools/check-embedded-reference.py`; pass `--reference` with the
reference Embedded directory to also check the supplied source and file coverage.
List, ScrollView, ForEach, Shape, font, and animation all use the same
DisplayList construction path.

The public application model is `App -> View`, matching the upstream structure
with the Scene layer omitted for the single permanent display. The internal
`LVGLApplicationRuntime` constructs the App and root View on the LVGL timer task.
It obtains the current default display and creates one
`LVGLHostingController`, which owns the `EmbeddedViewHost`, LVGL screen and
retained renderer.

`LVGLHostingController` binds to a concrete LVGL display instead of accepting a
fixed screen size. Every render reads the display's current logical horizontal
and vertical resolution, creates a `RootGeometry`, applies its content bounds,
and sizes the LVGL screen and content root accordingly. Its `needsRender`
property also detects display-resolution changes, so the existing application
tick schedules a new layout pass after rotation or a runtime resolution update.
All operations require the LVGL task or the BSP LVGL lock.

The adaptor implements Shape callbacks, root animations, font selection and
snapshots in Swift, split into `LVGLShapeRenderer.swift`,
`LVGLAnimation.swift`, `LVGLFont.swift`, and `LVGLScreenshot.swift`.
`HeaderBridge.h` exposes LVGL/BSP declarations, constant addresses and macro
values. The screenshot C entry point remains available to the BLE transport
through Swift's `@_cdecl`. Drawing contexts are released on LVGL object deletion;
animation contexts are released on completion or cancellation. Snapshot
callbacks run after unlocking, and the pixel buffer is freed after the callback
returns.

## Implementation and provenance

The package contains two modules. `EmbeddedSwiftUI` defines declarative
construction, ViewList, modifiers, traits, environment, layout, state,
transactions, animations, and DisplayList. `LVGLRendererAdaptor` owns the
display-list renderer, LVGL object creation, text/image metrics, physical
input, timers, animations, and snapshot support. The subset derives from the supplied
`Sources/OpenSwiftUICore/Embedded` implementation from
[upstream revision acee5c4](https://github.com/OpenSwiftUIProject/OpenSwiftUI/tree/acee5c44efea03d09031779bffdb42e273b93e2d).
[UPSTREAM.json](../../../main/EmbeddedSwiftUI/UPSTREAM.json) records source mappings,
functional replacements, and format-only adaptations; the MIT license is retained.
The original checkout is untouched.
The supplied revision has no concrete `List` or `ScrollView` type
implementation. These local Embedded counterparts use the standard
`ScrollView(_:showsIndicators:content:)` API shape. Full upstream graph/runtime
modules are not linked.

`LVGLRenderBackend` maps resolved frames to LVGL object/scroll/style APIs. A
lightweight layout provider carries only configuration and metric resolution,
so layout does not copy mutable node dictionaries. New subtrees are mounted
before deleting old ones; allocation failure preserves the old tree, focus and
scroll positions. Limits are 64 nodes and 16 container levels. Scroll offsets
are retained by core identity and axes, so inserting
or removing earlier siblings does not transfer another container's offset.
The renderer clamps offsets to content bounds and unmounts before screen deletion.
Replacement and dismissal also delete superseded roots and their LVGL animation
state, including delayed and forever-repeating animations.

Shapes use one LVGL object plus a bounded command block of at most 64 commands.
Its draw-event callback flattens quadratic and cubic curves into six line
segments and submits LVGL line or triangle tasks directly. It allocates no
full-screen pixel buffer and does not enable Canvas or ThorVG. The compact
backend preserves floating-point commands until rasterization; its fill
tessellation targets the convex standard shapes, and its dashed stroke uses the
first dash/gap pair. Continuous corners use the same cubic approximation as
circular corners in this low-memory backend. Circle clipping uses a centered
native rounded square, with a direct image-radius path for square images;
nonsquare ellipse masks use analytic coverage, while
arbitrary paths retain bounded winding-rule rasterization. `DisplayList.ShapeContent`
preserves the path, resolved color, `FillStyle`, and `StrokeStyle` until the
LVGL adaptor consumes them.

The host lives for the firmware lifetime. The generic root view is retained by
the input timer. Firmware builds compile both RISC-V CMake targets. The
standalone manifest also records both package products; LVGL integration
requires the platform headers and bridge supplied by the firmware build.

### Screen snapshots

`passport_ui_take_screenshot(handler, context)` captures `lv_screen_active()` as
RGB565 and invokes the synchronous handler with the pixel pointer, byte count,
width, height, and stride. The pointer remains valid only until the handler
returns. The bridge acquires the LVGL lock while rendering, releases it before
the handler runs, and frees the system-heap buffer afterward.

A 240 × 320 snapshot requires about 150 KiB of contiguous internal RAM because
the board has no PSRAM. The call returns `false` if locking, allocation, or
rendering fails. The bytes use LVGL's native RGB565 layout; they are raw pixels,
not a PNG or JPEG file.

`BLEScreenshotService` implements an optional screenshot transport without
registering it in the existing GATT service. After initialization, an integration
can pass a validated characteristic write plus its connection and notify-value
handles to `handleCommand`. The exact request is `[0x01, 0x30]`. The worker
returns metadata (`0x31`), ordered data chunks (`0x32`), a completion packet with
CRC32 (`0x33`), or an error (`0x34`). Multi-byte fields use network byte order.
Chunk size follows the negotiated ATT MTU. The integration remains responsible
for assigning a notify characteristic and routing writes to the class.

## Validation

Activate ESP-IDF 5.5.3 and the installed Embedded Swift toolchain. Set `SWIFTC`
for host tests if the default compiler lacks Embedded standard libraries.

```bash
bash tools/test-embed-renderer.sh
bash tools/test-embed-renderer.sh --lvgl
./tools/validate.sh
```

The first suite tests View construction, ViewList counts, custom modifier
bodies, environment propagation, traits, effects, layout proxies, state
invalidation, and lifecycle output. The optional LVGL suite uses the real
backend and installed managed LVGL sources to verify dimensions, custom layout
binding, alignment, low-memory shapes, colors, font pointers, input, scroll
limits, animation timing, restoration, and cleanup. It requires CMake and a C
compiler.
`LVGL_HOST_BUILD_DIR` can retain its C build directory between runs.
Both targets use `-Osize` in host tests, matching firmware optimization.
The LVGL suite also runs the complete List demo, eight animation/scroll updates,
and unmount on a 16 KiB pthread with protected guard pages. It reports the
canary-measured high-water usage, including host runtime overhead. This catches
large recursive-stack regressions but does not measure the device's remaining
stack. View inputs use copy-on-write storage; builder pairs share immutable
children so recursive calls do not copy the entire descendant value.

The full gate verifies `build/FoloToy-AI-Passport-full.bin` and the protected
[BLE Recovery contract](ble-recovery-compatibility.md). `idf.py flash` uses the
application binary and segmented bootloader/table writes in the local build.
Firmware verification also inspects final RISC-V code and rejects
`_ViewInputs.pushStableType` specializations whose entry stack frame exceeds
192 bytes. The previous failing implementation used 448 bytes; the compact
copy-on-write implementation uses 96 bytes with the pinned toolchain.
The ESP32-C3 full-List stress run reached 271,896 ms after repeated OK animation
and UP/DOWN scrolling without a panic or watchdog report. Its minimum free task
stack stabilized at 6,476 bytes and free heap at 104,468 bytes. This measured
run complements, but does not replace, visual display inspection.

The BSP configures an 18 KiB LVGL task stack through `CONFIG_BSP_LVGL_TASK_STACK_SIZE`. The measured reset-tracker high-water mark leaves more than 6 KiB of stack headroom while returning 6 KiB to the internal heap. A ten-second UI timer reports the task stack minimum free bytes and free heap for device validation.

The demo requires at least 48 KiB of LVGL memory (`CONFIG_LV_MEM_SIZE_KILOBYTES`). Existing `sdkconfig` files retain their old values; CMake rejects smaller pools to prevent allocation assertions during startup.
The host LVGL test uses a 96 KiB pool so replacement tests can hold the outgoing
and incoming trees at the same time.
