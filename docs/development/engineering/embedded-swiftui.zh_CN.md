[English](embedded-swiftui.md) | 简体中文

# EmbeddedSwiftUI MVP

`main/Main.swift` 的入口声明 `PassportApplication: App`，默认 body 直接返回
`ConnectivityStatusView`。完整的 `EmbeddedSwiftUIDemoView` List 作为源码示例，
由主机回归覆盖。固件只有一个常驻显示屏，因此嵌入式 `App` 协议以
`View` 作为 body，不再包含 `Scene` 和 `WindowGroup` 层。
`PassportApplication.init()` 负责初始化平台。LVGL adaptor 提供 `App.main()`，
直接创建应用实例、挂载根 UI 并启动相关定时器。轻量 LVGL 宿主直接在黑色屏幕上
显示根 View。常驻 Swift 工作任务会缓存 CW2017 电量、蓝牙控制器与 NimBLE 连接状态，以及
当前 Wi-Fi 连接的 RSSI；数值发生变化时，页面每秒刷新一次。MVP 不启动 Agent
Monitor、BLE、Wi-Fi、音频、旧页面和原像素主题 UI。
原应用仍保存在
`main/legacy/AgentMonitorApplication.swift`，其构建暂时不在支持范围内。

在完整能力示例中，UP/DOWN 滚动十行 List，OK 切换强调面板并执行动画，同时保留
List 身份及滚动位置。按键回调立即将事件放入队列；20 ms 的 LVGL 定时器每次最多
处理 16 个事件，并将其中的状态变化合并为一次渲染。

## 支持的 API 与限制

- `View`、`_UnaryViewAdaptor`、自定义 body、`ViewBuilder`、可选与条件子视图、`EmptyView`。
- 面向布局透明 primitive modifier 的同步 `ViewModifier` 和
  `ModifiedContent` 组合，支持自定义和 primitive modifier。trait 写入、
  appearance action、值驱动 animation、environment、renderer effect、
  geometry effect 和 focusable scope 均使用该路径。
- `App` 以根 `View` 作为 body，由 LVGL adaptor 提供默认 `main()`。
- 提供 `EmbeddedViewHost`、`RootGeometry`、`EmbeddedSize`、`EmbeddedRect` 和
  `ProposedViewSize`。Host 按 View 身份保留 `@State` 并同步构建 `_ViewOutputs`，不持有
  renderer 或物理输入 API。
- `VStack`、`HStack`、`ZStack`、`Spacer(minLength:)`、水平/垂直对齐，以及 frame
  的九个对齐位置。`Spacer` 在固定尺寸的栈子视图完成测量后使用剩余的建议尺寸。
  `zIndex(_:)` 控制重叠同级视图的绘制顺序，相同值保持源码顺序。默认值为零，
  因此 `ZStack` 中未修饰且后声明的子视图显示在先声明的子视图上方。
- 支持浮点 `Path` 的移动、直线、二次曲线、三次曲线和闭合命令；
  `Shape`、`ShapeStyle`、`FillStyle`、`StrokeStyle` 和 `InsettableShape`；
  `Rectangle`、`RoundedRectangle`、`Capsule`、`Ellipse`、`Circle`；以及
  `fill`、`stroke` 和内缩 `strokeBorder` 修饰器。未显式指定样式的 Shape 会继承
  当前前景色；圆角矩形支持 `cornerSize`、`cornerRadius` 和
  `RoundedCornerStyle`。
- 支持 Embedded `Layout` 协议、非泛型 `LayoutSubviews` 和 `LayoutSubview`
  代理、可调用的自定义布局，以及 `VStackLayout` 和 `HStackLayout`。
- `Transaction`、`withTransaction`、`withAnimation` 和
  `View.animation(_:value:)` 采用对应的 OpenSwiftUICore API 形态。隐式动画只在其
  `Equatable` 值变化后启动；首次挂载和值未变化时不执行动画。设置
  `disablesAnimations` 的 transaction 会禁止显式动画和值驱动动画。
- `Animation` 支持线性与缓动 Bézier 曲线、自定义三次 Bézier 控制点、物理弹簧计算、
  顺序敏感的 `delay` 和 `speed`，以及带可选 autoreverse 的有限或永久重复。
  当两棵树符合适配层资源预算时，LVGL 会对替换后的根子树执行淡入淡出，在第一个
  动画段结束后删除旧子树，并在 renderer 卸载或后续替换覆盖当前动画时取消仍保留
  的动画回调。包含 bitmap mask 的树仅执行按身份匹配的局部动画，不重叠完整根树。
- `List { ... }`、`List(0..<10) { ... }`、keyed 集合/整数范围 `ForEach` 和支持轴集合及滚动条
  开关的 `ScrollView`。列表一次性创建全部行，尚未实现选择、复用和编辑。
  屏幕外的行也计入 64 个节点上限。LVGL 会把滚动内容裁剪到可见区域。
- `font`、`foregroundColor`：子视图继承，内部值覆盖外部值。
- `@State`、`@Binding`、通用环境键、`@Environment` 和 `id(_:)`。
  构建主机上的 SwiftSyntax 生成器在 body 求值前注册存储型动态属性。
- 命名 `Image` 使用 hosting controller 的可选 `imageResolver`；资源缺失时更新失败，
  保留原场景。
- 任意 View 的 `background`、`offset`、`padding`、`EdgeInsets` 和固定尺寸
  `frame` 分别使用 `_BackgroundModifier`、`_OffsetEffect`、`_PaddingLayout`
  和 `_FrameLayout`。尚未包含弹性 frame 和桌面端图计算布局运行时。
- `Font.system(size:)` 和 largeTitle 到 caption2 的文字样式：映射到最近的
  Montserrat 12/14/16/18/20/24/28 位图字体。当前使用常规字重，尚未实现字重变化、
  自定义字体和动态字号。
- `onPhysicalButton` 和 `PhysicalButton` 位于 `LVGLRendererAdaptor`。滚动容器自动
  获得焦点，`focusable` 和适配层 renderer 支持焦点切换。尚未实现通用空间焦点导航。

PRESS 会分发物理按键，长按 UP 或 DOWN 会重复滚动；CLICK、DOUBLE 和长按 OK
会被忽略。未处理的 UP/DOWN 输入滚动焦点容器，三键设备的 UP/DOWN 也可以滚动
横向容器。View 已处理的输入会重新计算根视图，纯滚动输入保留全部节点。核心 Host
按结构/显式身份保留在 `body` 中重建的子 View 状态，状态写入后标记需要重绘；
移除后的状态位置拒绝旧绑定写入。独立 `.animation(_:value:)` 范围产生独立条目事务，
生命周期和滚动恢复同样按身份处理。后端仍采用替换树挂载；通用手势、行复用和任意
自定义 Animatable 插值尚未包含在该子集中。

## 参考源码对齐

实现同时参考所提供的 Embedded 源码子集，以及对应的 OpenSwiftUICore View、
modifier、layout、animation、environment、effect 和 DisplayList 源码。
`UPSTREAM.json` 记录每项映射和有意省略项。`EmbeddedRenderSink` 与 Embedded
参考 renderer 会重复 View 职责和平台渲染，因此不纳入本地核心。

构建统一通过 `_makeView`、`_makeViewList` 和 `_viewListCount`。
`_ViewInputs`、`_ViewOutputs`、`_ViewListInputs`、`_ViewListOutputs`、
`ViewList`、`ViewVisitor`、`PrimitiveView`、`UnaryView` 和 `MultiView`
保留上游入口名称，省略 AttributeGraph 和 `_GraphValue` 参数；尚未移植完整的
上游 graph、preference 和 ViewList 遍历接口。

`DisplayList` 是唯一通用 renderer 输出。Identity scope 保留嵌套子 List，
不再反复展平并复制命令数组；解析和 LVGL 条目挂载使用显式帧栈，保持遍历顺序且
不递归消耗原生栈。`ViewModifier`、
`PrimitiveViewModifier`、`UnaryViewModifier`、`MultiViewModifier`、
`_ViewModifier_Content` 和 `ModifiedContent` 提供同步组合。
`EnvironmentValues`、`_EnvironmentKeyWritingModifier`、`Animatable`、
`GeometryEffect`、`_RendererEffect` 和 `RendererEffect` 使用上游职责。
`ViewTraitCollection` 保持同步实现。`DisplayListLayout` 通过响应 proposal 的代理
完成测量，再输出带身份和位置的 `DisplayList.Item`。`RendererProvider` 提供真实
文本/图片度量和平台默认配置，LVGL 挂载已解析条目并执行动画。
本文档记录具体适配和保留范围。

复核后的实现会安装组合 modifier 每一层的动态属性，将投影固定到原始安装位置，
并按 host 保留事务。类型化属性 box 和 ID/appearance phase 替代图驱动的生命周期
求值。显示实例 ID 与稳定身份分别映射。Eager ViewList 提供 ID/trait 元数据、
可恢复遍历和单次更新编辑快照。自定义 alignment guide、Layout 间距与栈方向均参与
放置；放置使用显式工作栈并保留子项测量时的 proposal。配置要求适配层传入
`implicitRootLayout`。LVGL 迁移目标未变化的原生活动动画，保持时间与阶段，接受
空路径，并拒绝负缩放/反射矩阵。这些约束由 `tests/TestViewAlignment.swift` 和
LVGL 主机测试覆盖。

`UPSTREAM.json` 记录参考文件到本地文件的映射、SHA-256 和全部已记录的适配说明，
并列出受嵌入式约束影响、必须在附近保留 `Embedded adaptation:` 源码注释的实现。
主机验证通过 `tools/check-embedded-reference.py` 检查这两项；使用 `--reference`
指定参考 Embedded 目录，还会检查参考源码及文件覆盖范围。List、ScrollView、
ForEach、Shape、字体和动画统一使用 DisplayList 构建路径。

公开应用模型为 `App -> View`，整体结构与上游一致，并针对单个永久显示屏省略
Scene 层。内部 `LVGLApplicationRuntime` 在 LVGL 定时器任务中构造 App 和根 View，
取得当前默认 display，并创建唯一的 `LVGLHostingController`。该控制器持有
`EmbeddedViewHost`、LVGL screen 和 retained renderer。

`LVGLHostingController` 绑定具体的 LVGL display，不再接收固定屏幕尺寸。每次渲染
都会读取 display 当前的逻辑横向、纵向分辨率，创建 `RootGeometry`，应用其内容区域，
并同步更新 LVGL screen 与内容根节点尺寸。`needsRender` 也会检测 display 分辨率变化，
因此旋转或运行时调整分辨率后，现有应用 tick 会安排新的布局。所有操作都必须在
LVGL 任务中执行，或持有 BSP LVGL 锁。

适配层的 Shape 回调、根视图动画、字体选择和截图均使用 Swift 实现，分别放在
`LVGLShapeRenderer.swift`、`LVGLAnimation.swift`、`LVGLFont.swift` 和
`LVGLScreenshot.swift`。`HeaderBridge.h` 提供 LVGL/BSP 声明、常量地址和宏值。
截图的 C 入口通过 Swift `@_cdecl` 保留，供 BLE 传输调用。LVGL 对象删除时释放
绘图上下文；动画完成或取消时释放动画上下文。截图回调在解锁后执行，回调返回后
释放像素缓冲区。

## 实现与来源

package 包含两个模块。`EmbeddedSwiftUI` 定义声明式构建、ViewList、modifier、
trait、environment、layout、state、transaction、animation 和 DisplayList。
`LVGLRendererAdaptor` 负责 display-list renderer、LVGL 对象创建、文本/图片度量、
物理输入、宿主屏幕、timer、动画和截图。源码子集来源于所提供版本的
`Sources/OpenSwiftUICore/Embedded` 实现，该版本基于
[上游版本 acee5c4](https://github.com/OpenSwiftUIProject/OpenSwiftUI/tree/acee5c44efea03d09031779bffdb42e273b93e2d)。
[UPSTREAM.json](../../../main/EmbeddedSwiftUI/UPSTREAM.json) 记录文件对应关系、功能替换和
纯格式适配，保留 MIT 许可证，原始仓库保持原样。提供的版本没有具体的 `List` 或 `ScrollView`
类型实现；本地 Embedded 版本采用标准
`ScrollView(_:showsIndicators:content:)` API 形状。完整上游图计算与运行时模块未参与链接。

`LVGLRenderBackend` 将已解析 frame 转换为 LVGL 对象、滚动和样式调用。轻量布局
Provider 只携带配置与度量解析，因此布局不会复制可变节点字典。更新时先创建新树，
再删除旧树；分配失败保留原树、焦点和滚动位置。上限为 64 个节点和 16 层容器。
滚动位置按核心身份和方向保留，插入或移除前面的兄弟节点不会转移其他容器的偏移。
滚动值限制在内容范围内，删除屏幕前卸载渲染树。替换和关闭还会删除
已经被覆盖的根节点及其 LVGL 动画状态，包括处于 delay 阶段和永久重复的动画。

每个 Shape 使用一个 LVGL 对象和一块有界命令内存，最多保存 64 条命令。draw-event
回调将二次与三次曲线分别展开为六段线，并直接提交 LVGL 直线或三角形绘制任务；
过程中不分配整屏像素缓冲区，也不启用 Canvas 或 ThorVG。该后端在光栅化前保留
浮点命令；紧凑填充细分面向这些凸标准形状，虚线描边使用第一组 dash/gap，
`continuous` 圆角在该低内存后端中采用与 `circular` 相同的三次曲线近似。
Circle 裁剪使用居中的原生圆角正方形，正方形图片会直接使用图片圆角；
非正方形 Ellipse 蒙版使用解析覆盖计算，
任意 Path 保留有界 winding-rule 光栅。
`DisplayList.ShapeContent` 会保留 path、已解析颜色、`FillStyle` 和
`StrokeStyle`，直到 LVGL adaptor 消费。

运行层与固件生命周期一致，输入定时器持有泛型根视图。固件构建两个 RISC-V CMake
target。独立 manifest 也声明两个 package product；LVGL 集成需要固件构建提供的平台
头文件与 Bridge。

### 屏幕截图

`passport_ui_take_screenshot(handler, context)` 将 `lv_screen_active()` 截取为
RGB565，并通过同步回调提供像素指针、字节数、宽度、高度和步长。像素指针仅在回调
执行期间有效。桥接层在渲染时持有 LVGL 锁，在执行回调前释放锁，并在回调返回后释放
系统堆缓冲区。

240 × 320 截图需要约 150 KiB 连续内部 RAM，因为此开发板没有 PSRAM。锁定、分配或
渲染失败时方法返回 `false`。数据采用 LVGL 原生 RGB565 布局，是原始像素数据，
不是 PNG 或 JPEG 文件。

`BLEScreenshotService` 实现可选的截图传输，但不注册到现有 GATT service。初始化后，
接入层可将已经校验的 characteristic 写入及其连接句柄、通知值句柄传给
`handleCommand`。准确的请求为 `[0x01, 0x30]`。worker 依次返回元信息 `0x31`、
有序数据分片 `0x32`、带 CRC32 的完成包 `0x33`，失败时返回 `0x34`。多字节字段使用
网络字节序，分片大小跟随协商后的 ATT MTU。接入层仍需分配 notify characteristic，
并将写入事件转发给此类。

## 验证

激活 ESP-IDF 5.5.3 和已安装的 Embedded Swift 工具链。默认编译器缺少 Embedded
标准库时，通过 `SWIFTC` 指定主机测试编译器。

```bash
bash tools/test-embed-renderer.sh
bash tools/test-embed-renderer.sh --lvgl
./tools/validate.sh
```

第一组测试覆盖 View 构建、ViewList 数量、自定义 modifier body、environment
传播、trait、effect、布局代理、State 失效和生命周期输出。可选 LVGL 测试使用
真实后端与已安装的 managed LVGL 源码，验证尺寸、自定义布局绑定、对齐、低内存
Shape、颜色、字体指针、输入、滚动边界、动画时间、位置恢复和清理，需要 CMake
和 C 编译器。
`LVGL_HOST_BUILD_DIR` 可指定保留的 C 构建目录，便于增量运行。
两个 target 的主机测试使用 `-Osize`，与固件优化设置一致。LVGL 测试还在带保护页的
16 KiB pthread 上运行完整 List 示例、八次动画/滚动更新和卸载，并通过填充标记
测量包含主机运行时开销的栈高水位。该检查可发现明显递归栈回归，不能代替设备
剩余栈测量。View 输入使用写时复制存储，builder pair 共享不可变子元素，
避免递归调用反复复制整个后代值。

完整检查验证 `build/FoloToy-AI-Passport-full.bin` 及受保护的
[BLE Recovery 约定](ble-recovery-compatibility.zh_CN.md)。`idf.py flash` 使用本地
构建的应用文件，并分段写入 bootloader 和分区表。
固件校验还会检查最终 RISC-V 代码，拒绝入口栈帧超过 192 字节的
`_ViewInputs.pushStableType` 特化。此前发生崩溃的实现使用 448 字节，紧凑写时复制
实现通过固定工具链编译后使用 96 字节。
ESP32-C3 完整 List 压力复验在重复 OK 动画与 UP/DOWN 滚动后运行到
271,896 ms，未出现 panic 或看门狗报告；任务栈最低余量稳定为 6,476 字节，
空闲堆稳定为 104,468 字节。该实测结果仍不能替代人工画面检查。

BSP 通过 `CONFIG_BSP_LVGL_TASK_STACK_SIZE` 配置 18 KiB 的 LVGL 任务栈。根据重置追踪器实测的最小剩余值，该配置保留超过 6 KiB 的栈空间，并向内部堆归还 6 KiB。UI 每十秒记录任务栈最小剩余字节数及剩余堆内存，供真机验证。

Demo 要求 LVGL 内存池至少为 48 KiB（`CONFIG_LV_MEM_SIZE_KILOBYTES`）。已有 `sdkconfig` 会保留旧值；CMake 会拒绝更小的内存池，避免启动时分配失败触发断言。
Host LVGL 测试使用 96 KiB 内存池，以便替换测试同时保留移出树和移入树。
