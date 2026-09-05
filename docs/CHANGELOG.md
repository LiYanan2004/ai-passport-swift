<p align="right">
  <a href="CHANGELOG.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Changelog

## Unreleased

- Raised USB mirroring to native 240×320 RGB565 without retaining a complete
  framebuffer. `PMIRROW6` queues row segments in approximately 12 KiB, captures
  key frames in 20-row stripes, isolates them from continuous animation flushes,
  rotates bounded delta stripes across dirty regions, and decodes
  directly to RGBA without pixel-format branching. USB mirroring remains available
  while HTTPS and SwiftUI rendering run.

- Render Wi-Fi connection state with animated vector dots and store the Tibo portraits as
  100×100 RGB565 assets matching their view size. Resizable RGB565 images use a
  bounded one-time resize when their source and view sizes differ, and image
  circles use LVGL's scanline radius clip without an ARGB8888 layer. Software
  rasterization yields periodically so the single-core idle task can service
  its watchdog.

- Restrict enterprise credentials to EAP-TLS, extend active Wi-Fi scan dwell
  time to 120 ms, and log scan, candidate, and disconnect-reason diagnostics.
  When a configured SSID is absent from scan records, the station now tries
  configured credentials without a pinned channel or BSSID so hidden and
  temporarily undiscoverable networks remain connectable. China deployments
  configure the validated `CN` country code with automatic 802.11d updates,
  enabling 2.4 GHz channels 12 and 13 before the first association.

- Retain every scanned channel for each configured network and try them in RSSI
  order before rescanning. Enterprise WLAN controllers can advertise BSSIDs
  that reject a direct association, so the driver chooses the valid AP within
  each channel. Unpinned fallback candidates correctly leave BSSID and channel
  unset. Failed connection rounds back off at 5, 10, 30, then 60 seconds; a
  successful connection or an explicit refresh resets the delay.

- Raised the ESP32-C3 station buffer profile to 6 static RX, 16 dynamic RX,
  16 dynamic TX and 12 management short buffers with a six-frame RX BA window.
  Long software-rasterized Shape fills now yield periodically, and the
  single-core task-watchdog window is 15 seconds so valid LVGL and TLS work can
  complete without watchdog reports.

- Added a Swift Tibo reset tracker for ESP32-C3. It fetches the verified HTTPS
  status API from codex-resets.com on a FreeRTOS worker, shows the latest reset,
  scheduled reset or active watch, latest Tibo X post, GMT+8 timestamps, cached
  and network states, supports OK-button refresh, and selects one of three
  Flash-backed RGB565 portraits. The application and input runtime under `main`
  are implemented in Swift, with `HeaderBridge.h` retained as the sole C-family
  source interface in that component. The tracker profile disables USB display
  mirroring and uses bounded Wi-Fi buffers so UI updates and HTTPS handshakes
  retain sufficient internal RAM on the no-PSRAM target.

- Kept the optional Wi-Fi and Wi-Fi RX optimized routines in Flash for more
  than 27 KB of additional internal RAM, preserving the default receive-buffer
  counts while allowing `esp_wifi_init()` to reserve its DMA buffers on the
  no-PSRAM ESP32-C3.

- Keep the four Wi-Fi strength dots at fixed active/inactive opacities, with
  inactive dots visible at 45% as placeholders. While connecting, each dot
  continuously eases between those values through retained LVGL animations
  with a 130 ms phase delay, producing a left-to-right wave without rebuilding
  the view tree.

- Moved the reusable hardware wrappers and Wi-Fi connection state machine out of
  `main/legacy/` into the formal application modules under `main/platform` and
  `main/wifi`. The default credentials-free build now leaves the Wi-Fi radio
  untouched and reports a skipped startup instead of creating a network task.

- Added a combined EmbeddedSwiftUI connectivity indicator and made it the
  default `PassportApplication` view. Its layered battery arc, Bluetooth state
  glyph and four Wi-Fi strength dots now refresh from the CW2017 fuel gauge,
  Bluetooth controller/NimBLE connection state, and connected-station RSSI.

- Moved the double-ball loader from 500 ms timer-driven state updates to one
  retained, autoreversing LVGL animation. Intermediate frames now remain smooth
  beside the full List, and each half-cycle no longer rebuilds the application
  view tree.

- Generate EmbeddedSwiftUI dynamic-property registration for every application
  Swift source in the component, so newly added views retain `State`, `Binding`,
  and environment properties. Corrected the physical-button modifier API to
  `onPhysicalButton`.

- Restored the upstream `_UnaryViewAdaptor` and `ViewTypeVisitor` construction
  entry points. The embedded adaptor forwards unary construction without adding
  a graph or renderer node.

- Fixed five EmbeddedSwiftUI compatibility regressions: nested unary/custom
  modifiers preserve the configured implicit root; State body captures stay
  attached to their original mount; stacks allocate space by priority group;
  long animation durations are preserved with timer quantization isolated in
  LVGLRendererAdaptor; nested and sibling eager collections share one bounded
  expansion budget. Added core and LVGL timing regressions.

- Fixed repeated restarts when the double-ball loader and full EmbeddedSwiftUI
  List render together. The embedded renderer now consumes transient display
  commands while creating layout nodes and releases construction outputs before
  mounting the replacement LVGL tree. Added command-lifetime and combined
  animation/input/lifecycle regressions.

- Corrected EmbeddedSwiftUI modifier property installation, stale Binding
  lifetime, proposal-sensitive padding and custom alignment callbacks. Added
  typed property lifecycle boxes, per-host transactions, separate display/stable
  identities and eager ViewList traversal metadata. Platform configuration now
  supplies the implicit root layout. LVGL preserves unchanged active animations
  across redraws, accepts empty paths and rejects unsupported reflections.
  Layout placement uses an explicit work stack under the unchanged 16 KiB gate;
  embedded adaptations and regression coverage are documented.

- Fixed scaled Shapes being clipped into rounded rectangles during opacity
  animations by refreshing the parent LVGL layer bounds on every scale update.

- Optimized ESP-IDF C/C++ code for size in production firmware, reducing the
  measured application image by 53,104 bytes while retaining debug symbols and
  runtime assertions.

- Fixed `zIndex(_:)` on views wrapped by geometry or renderer effects. Traits
  now remain attached to the resulting ViewList root, so overlapping LVGL
  siblings change front-to-back order when their z-index values change.

- Fixed full EmbeddedSwiftUI List updates exhausting ESP32-C3 stack and heap.
  Identity scopes now retain nested display lists; parsing and LVGL mounting
  use explicit frame stacks; layout receives a metrics-only provider; renderer
  metadata is pruned without dictionary COW rebuilds; queued input updates are
  coalesced; and Circle clipping uses LVGL's native rounded clip. Embedded-only
  deviations carry enforced `Embedded adaptation:` source comments.

- Reduced recursive EmbeddedSwiftUI construction stack use with copy-on-write
  View inputs and immutable shared builder-pair storage. Branch environments,
  transactions, state installation, and structural identity retain their
  existing semantics. Added a guard-page-protected 16 KiB LVGL host regression
  covering the complete List demo and repeated animation/scroll updates.

- Extended EmbeddedSwiftUI's synchronous OpenSwiftUI profile with compile-time
  dynamic-property registration, nested `@State`, `Binding`, environment keys,
  explicit/keyed view identity, identity-based lifecycle and scroll restoration,
  scoped animation transactions, and proposal-aware layout before LVGL mounting.
  Fixed root trait-modifier construction, custom modifier counts, background
  sizing, and nonsquare ellipses. Platform metrics/defaults and image resolution
  are supplied by the adaptor; generated SwiftSyntax tooling runs only on the
  build host.

- Added screenshot and H.264 screen-recording controls to the PassportMirroring
  toolbar. Captures use the original 240 × 320 mirrored frames. Recording starts
  immediately in a temporary file, prompts for a destination after stopping,
  then moves the result or deletes it when saving is cancelled or fails.

- Added EmbeddedSwiftUI `rotationEffect` following the upstream geometry-effect
  flow. It preserves layout measurements and maps the angle and anchor to LVGL
  layer rotation, including overflow bounds and implicit animation.

- Added the upstream-compatible `_ViewTraitKey` and `ViewTraitCollection`
  foundations. EmbeddedSwiftUI can now store, override, default, and merge
  strongly typed container traits without AttributeGraph.

- Added the upstream-compatible EmbeddedSwiftUI `zIndex(_:)` trait. Synchronous
  layouts preserve source-order geometry while drawing overlapping siblings by
  stable ascending z-index, and LVGL overlay containers use the same ordering.
  The modifier now writes `ZIndexTraitKey` through the generic
  `_TraitWritingModifier` and `ViewTraitCollection` path.

- Refined the Douyin double-ball loading indicator with a smooth horizontal
  crossover curve and synchronized front-to-back ordering while retaining the
  cyan/red size and opacity exchange. Consecutive animation transactions now
  sample the current LVGL presentation state before changing z-index order,
  preventing a stale-frame jump as the balls separate.

- Aligned the single-display EmbeddedSwiftUI entry with the upstream App hosting
  model while omitting the Scene layer. `LVGLHostingController` now binds to the
  active LVGL display, rebuilds `RootGeometry` from its current logical
  resolution on every pass, applies safe-area content bounds, and automatically
  invalidates when the display resolution changes.

- Fixed `List` and `ForEach` physical-button propagation. Unhandled buttons now
  return through their content instead of evaluating the primitive `Never`
  body and triggering an illegal-instruction panic.

- Fixed task-watchdog resets during continuously animated Shape effects.
  Scale and layered-opacity buffers now cover the actual overflowing subtree
  instead of the full screen, while Shape edges and scanline storage are reused
  across frames. Overflow and clipping behavior remain unchanged.

- Added the EmbeddedSwiftUI `opacity(_:)` renderer effect with multiplicative
  nesting, hidden hit testing, and implicit animation. The LVGL renderer applies
  opacity to the composed subtree through layered opacity.

- Fixed the Douyin double-ball loading indicator remaining static on device.
  The animation now uses distinct LVGL-interpolated endpoints with an
  autoreversing loop, and appearance-triggered state changes are rendered by
  the application timer.

- Added EmbeddedSwiftUI `onAppear`, `onDisappear`, and anchored `scaleEffect`
  modifiers. `frame` and `offset` now
  accept `Double` values and round validated dimensions to physical pixels.
  LVGL timers can now invalidate themselves safely from their callbacks.

- Prevented the LCD from flashing uninitialized white and black frames during
  startup. Backlight control now initializes before panel setup and remains off
  until LVGL has synchronously rendered the first complete application frame.

- Consolidated the platform-independent retained renderer into the `OpenSwiftUI`
  module. The package and firmware now build two targets: `OpenSwiftUI` and
  `LVGLRendererAdaptor`.

- Added the SwiftUI-shaped `Spacer(minLength:)` primitive to embedded
  OpenSwiftUI. Stacks now allocate their remaining proposed pixels to spacers,
  including multiple spacers in the same layout.

- Fixed OpenSwiftUI Shape fills, curved strokes, and non-rectangular
  `clipShape` masks on ESP32-C3. Curved fills now use contiguous scanline
  spans, eliminating the radial seams created by the previous triangle fan;
  LVGL's complex software renderer, ARGB8888 intermediate layers, and A8 mask
  buffers are enabled. The firmware continues to render to the ST7789 display
  in RGB565.

- Fixed OpenSwiftUI startup resets for nested View modifier trees by deferring
  root View construction and first mount to the LVGL timer task, where
  input-driven renders already execute.

- Fixed false USB mirroring disconnects on static screens. The macOS receiver
  now allows seven seconds between complete frames to cover the firmware's
  five-second idle key-frame interval, while retaining the three-second initial
  frame timeout and immediate serial-error handling.

- Added SwiftUI-compatible `clipped(antialiased:)` and `clipShape(_:style:)` modifiers, including synchronous `Path` clip propagation, native LVGL rectangle and rounded-corner clipping, and bounded view-local A8 masks for custom shapes.

- Fixed the LVGL retained renderer background expansion when an `offset` is
  applied inside the background. The background keeps its original frame size;
  only the content drawing position is offset.

- Changed OpenSwiftUI animations to interpolate matching LVGL node position,
  width, height, and background RGBA values between renders. `offset` changes
  move from the previous value to the new value without repositioning sibling
  views or clipping outside the original bounds. Scroll containers retain
  viewport clipping, and structurally different trees continue to use a fade
  transition.

- Added USB LVGL live mirroring and the minimal PassportMirroring macOS receiver.
  The stream preserves 240×320 resolution using RGB332, with automatic connection
  and reconnection, compressed checked rows, a default 30 fps limit configurable
  to 60 fps, changed-row transport, and periodic recovery key frames. Flash mode
  releases the serial port without closing the app. The macOS app presents
  waiting, connecting, connected, and USB-released states with manual reconnect,
  and keeps its content area at a 3:4 aspect ratio while resizing.

- Expanded the OpenSwiftUI demo into a scrollable capability gallery covering
  typography, colors, stack layouts, frames, padding, backgrounds, offsets,
  shape fills and strokes, clipping, conditional content, and range-based
  `ForEach`. Each OK press animates the state panel while preserving the List
  and its scroll position. The gallery uses grouped rows and native rounded
  clipping to keep startup and animated replacement within the ESP32-C3 LVGL
  memory budget.

- Aligned the Embedded OpenSwiftUI sources with their reference files,
  documented the Text and RenderSink compatibility adaptations, and added
  source checks while preserving the existing List, ScrollView and ForEach
  implementations.

- Added the embedded Shape pipeline: floating-point `Path` commands,
  `Shape`/`ShapeStyle`, `FillStyle`/`StrokeStyle`, rectangle, rounded rectangle,
  capsule, ellipse and circle primitives, plus `fill`, `stroke`,
  `strokeBorder`, and `InsettableShape`. Synchronous sinks, visitors,
  `EmbedRenderer`, and the bounded LVGL draw-event backend now carry shape
  operations without a full-screen Canvas or ThorVG.

- Completed the embedded OpenSwiftUI transaction and animation path with
  `Transaction`, `withTransaction`, value-tracked `View.animation(_:value:)`,
  sequence-sensitive delay/speed composition, cubic Bézier and spring
  evaluation, repeat/autoreverse execution, and LVGL cancellation and cleanup
  across replacement and unmount.

- Aligned the embedded OpenSwiftUI API with the supplied
  `OpenSwiftUICore/Embedded` implementation, including custom `Layout`,
  `LayoutSubviews`, stack layouts, generic backgrounds, offsets, strict layout
  input validation, and a standard-shaped `ScrollView` with synchronous
  render-sink measurement and clipping.

- Added an OpenSwiftUI compatibility rendering path matching the reference
  firmware APIs: retained root `@State`, static `Image`, `Color` views,
  `foregroundStyle`, physical-button handlers, measured geometry, synchronous
  render sinks, and `EmbeddedViewHost`.

- Split the embedded UI into three package targets: `OpenSwiftUI`,
  platform-independent `EmbedRenderer`, and `LVGLRendererAdaptor`. Moved the
  reusable LVGL UI wrappers and bridges into the adaptor, reduced the current
  firmware target to the files required to display `OpenSwiftUIDemoView`, and
  isolated every previous application page and service under `main/legacy`.

- Added a top-level RGB565 screen snapshot API for the OpenSwiftUI application, with LVGL locking, bounded buffer ownership, and explicit allocation-failure reporting. Added an unconnected BLE screenshot service that recognizes a dedicated command and returns MTU-sized chunks with metadata and CRC32.

- Fixed the OpenSwiftUI startup reboot loop caused by overflowing the LVGL port's 7 KiB drawing stack. Added a configurable 16 KiB BSP task stack, enforced a minimum 48 KiB LVGL memory pool for existing configurations, and added periodic UI stack/heap diagnostics.

- Expanded the embedded OpenSwiftUI subset with List, ScrollView, range ForEach, ZStack, animation values, explicit `withAnimation` transitions, physical-button handling, fonts, alignment and ordered style/layout modifiers. Simplified `App.body` to return a root View directly without Scene or WindowGroup, placed platform initialization in the concrete App initializer and direct UI mounting in the LVGL adaptor's `App.main()`, queued input on the UI thread, and added real LVGL backend tests.

- Added an OpenSwiftUI embedded source subset and an independent `EmbedRenderer`
  target. Firmware opens a declarative counter with UP/DOWN adjustment, OK reset
  and long-OK return to Agent Monitor. Added bounded LVGL subtree rendering,
  Embedded Swift host tests and a boot-page configuration option.

- Refined Agent Monitor UI and live Codex allowance reporting: the dashboard now centers a state-aware mascot and shows 5h/1w consumed-usage meters with green, blue, yellow, and red thresholds plus an optional reset count; the mascot and button-operation hints were removed from connection screens. Opening Bluetooth now starts first-pairing advertising automatically and displays only the large passkey or `CONNECTED`. The paired Mac bridge reads the locally authenticated Codex app-server asynchronously and returns only compact allowance values over the authenticated BLE link.

- Replaced the boot menu with the first Agent Monitor phase: a Mac CoreBluetooth bridge forwards compact Codex Hook lifecycle status through a connectable NimBLE GATT service, the device uses a borderless dashboard for one focused session, reserves compact TOKENS and RESETS metrics, UP/DOWN switches retained sessions, and a dedicated audio task plays an urgent three-tone alert for permission requests and a gentle two-tone completion chime for DONE. Added the Mac bridge, hook template, protocol and security-boundary documentation, and host coverage for session state.

- Added the local CONNECT menu, known-Wi-Fi-only scanning, and secure single-Mac ownership for Agent Monitor. The device derives an exact public BLE name, requires a locally opened six-digit authenticated Secure Connections pairing, persists one owner bond, filters later connection requests through the controller white list, and accepts task events only over an authenticated encrypted 128-bit link. The Mac bridge now requires that exact device name before it scans and connects.

- Reworked the home screen into a horizontally paged application carousel: every existing view-controller page now has a title and one-line description, UP/DOWN animates the cards left or right, OK opens the selected page, and white dots with a blue selected state mark the current page beside the existing lower-right mascot. The shared status bar remains visible on every page, keeps the Wi-Fi state, uses a centered redrawn Bluetooth glyph, and adds a wider, shorter battery-level bar with a solid terminal.

- Restored opaque background rendering after the LVGL theme-size reduction. All views now apply a fully opaque background color, and labels default to white text for the dark interface.

- Redesigned the on-device interface around an English status bar, tab strip, and single focused content card. A separate control center presents large Wi-Fi and Bluetooth cards with clear focus, detail access, and close actions. The shared palette now uses a black background, white text, dark surface cards, and a muted teal focus state.

- Added boot-time Wi-Fi station connection that starts before slower peripheral checks, scans once, reuses the matched channel, and selects the first visible personal/EAP-TLS candidate in configured order. Personal networks use quick same-candidate authentication retries before automatic failover; the persistent scan page and high-contrast home-screen connection states remain available. Local credentials remain excluded from Git.

- Migrated application pages to Embedded Swift 6.3.3 while preserving the BSP initialization, button dispatch, demo menu, and low-power pages; the official Espressif `idf_swift` component is pinned for reproducible builds.

- Added the supplied 80-byte CW2017 profile for the specified 520 mAh cell, including content/update-flag checks, verified writes, the required restart sequence, and bounded SOC-readiness polling.

- Reorganized the documentation by function area with a dual entry point: the root `AGENTS.md` is now a thin router (hard constraints + task routing only) and the detailed AI workflow lives in `docs/development/ai-guide.md`; `agent-guide.md` was folded in. `docs/development/` gained a second level (`engineering/`, `ci/`, `release/`), and the `plays/` application archive and `experiences/` moved into a `docs/reference/` area with a dedicated README. Removed `docs/software-design/` (empty scaffold); folded the three `assets/{fonts,images,music}/README` leaves into the `assets/` README; flattened the six `project-completion` sub-documents into a single file; and unified each directory to a single README, eliminating every `INDEX` file and a duplicated experience index. All cross-references and bibliographic links were updated; no content was dropped.

- Made mini-program BLE install compatibility a template-level invariant: fixed
  protected `cardid`/Recovery partitions, retained the five-second UP-key
  Recovery boot hook, and added CI validation for merged-image structure,
  partition MD5/ranges, the 3 MB app limit, and protected payload exclusion.
- Documented a release-title convention for multi-app releases: name tags as `v<version>-<app-name>` (e.g. `v0.1.0-voice-keychain`) so the release title carries the version and the app, and confirm the title after the release is published so a release list is scannable by app.
- Added a post-release follow-up workflow: an `issue-suggestions` skill for filing user feedback as issues against the upstream project, an `experience-pr` skill for submitting reusable development experience as a documentation PR, a `docs/experiences/` directory for per-entry experience files, and supporting `project-completion`, `file-issues`, and experience-index documents.
- Simplified the tracked repository root: moved GitHub-recognized community documents into `.github/`, moved the changelog into `docs/`, updated every reference, and added a root-document allowlist to repository checks.
- Repository-wide language policy: every maintained Markdown default `.md` file is English, Simplified Chinese uses a paired `.zh_CN.md`, and both provide language switches. Static checks reject missing peers, missing switches, and Chinese prose in English defaults.
- Phase one of the AI development workflow: streamlined task-based context routing, unified local/CI validation, added PR checks and a template, and committed the dependency lock for reproducible builds.
- PR review fixes: pinned GitHub Actions to full commit SHAs, split build/release jobs by least privilege, disabled persisted sync checkout credentials, added Feature Request and Usage Question forms, clarified private security-report fallback, and corrected stale README, CI-trigger, and branch descriptions.
- Changed commit titles, PR titles, and PR bodies from Chinese-default to English; updated the Chinese punctuation rule so it no longer applies to PR descriptions.
- Reworked `build-firmware.yml` to pass `SDKCONFIG_DEFAULTS=sdkconfig.defaults`, enable `partitions.csv`, preserve the 8 MB image header, merge a flashable `FoloToy-AI-Passport-full.bin`, publish only that artifact, and use Actions cache v5.
- Integrated upstream PR #6 to resolve PR #4 conflicts: Wi-Fi, Bluetooth LE, radio lifecycle, and low-power demos; a 3 MB factory partition; build/menu/configuration updates; hardware-guide coverage; and bilingual capability tables.
- Defined English imperative Conventional Commit formatting for both commits and PR titles.
- Removed stale sync-workflow template comments and generalized an irrelevant Redis TTL rule to cache components.
- Added Chinese punctuation, credential safety, and recoverable file-deletion conventions.
- Expanded source-comment requirements for functions, state, ownership, concurrency, timing, registers, and magic values.
- Removed AI execution instructions from product READMEs so they remain human-facing product and repository overviews.
- Added `docs/development/agent-guide.md` as the focused AI workflow guide.
- Updated `AGENTS.md`, `docs/INDEX.md`, and the development index for the agent guide.
- Documented why the root README path is reserved for fork owners and how GitHub README precedence supports it.
- Created `main-update` from the upstream-aligned baseline and combined the repository-structure, firmware-CI, and upstream-sync work.
- Corrected the merged documentation index, workflow path, project tree, and CI references.
- Moved CI documentation from software design to `docs/development/`.
- Moved fork-only documentation assets from `assets/docs/` to `docs/assets/`.
- Moved the upstream English/Chinese project READMEs under `docs/` and renamed the documentation catalog to `docs/INDEX.md`.
- Initialized `AGENTS.md`, `CLAUDE.md`, and `CHANGELOG.md`.
- Standardized the initial project README language filenames.
- Added the `docs/`, `assets/`, and `skills/` directory structure.
- Moved the upstream hardware guide into `docs/hardware-design/`.
- Standardized subdirectory README capitalization and introduced fork conventions.
- Allowed fork-owned root README and supplemental documentation content on fork `main`.
- Added and documented the fork-only supplemental-document directory.
- Moved the build CI document to its dedicated CI branch before consolidation.
- Documented clean-`main` reasons, the direct-development exception, and Actions enablement for forks.
- Split the original agent rules into contribution, development, and fork documents with a compact root index.
- Updated software-design and project README references for the new documentation structure.
- Added the documentation catalog and task-triggered routing based on the earlier repository model.
- Added bilingual contribution, code-of-conduct, security, and support documents tailored to this ESP-IDF and fork workflow.
