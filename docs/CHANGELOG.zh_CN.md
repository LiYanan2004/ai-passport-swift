<p align="right">
  <strong>简体中文</strong> · <a href="CHANGELOG.md">English</a>
</p>

# Changelog

## Unreleased

- USB 屏幕投送提升为原生 240×320 RGB565，同时取消完整常驻帧缓冲。
  `PMIRROW6` 使用约 12 KiB 的行分段队列，以每块 20 行的方式采集关键帧，隔离持续
  动画产生的刷新，并在变化区域间轮换发送固定容量的增量分块，直接解码为 RGBA，无需按
  像素格式分支。投屏可与 HTTPS、SwiftUI 绘制同时运行。

- Wi-Fi 连接状态使用带动画的矢量信号点，Tibo 头像资源调整为与 View 尺寸一致的 100×100
  RGB565。可缩放 RGB565 图片的资源尺寸与 View 不同时会执行一次受限缩放；图片圆形
  裁切使用 LVGL 的逐行半径路径，无需 ARGB8888 图层。软件绘制会定期让出 CPU，保证
  单核空闲任务能够处理看门狗。

- 企业 Wi-Fi 凭据固定使用 EAP-TLS，主动扫描驻留时间调整为 120 ms，并记录扫描、
  候选网络和断连原因日志。扫描结果缺少已配置 SSID 时，Station 会使用未固定信道和
  BSSID 的配置凭据继续连接，使隐藏网络和短时未发现的网络仍可连接。中国部署会配置
  经过 API 校验的 `CN` 国家代码并启用自动 802.11d 更新，使首次关联前也能扫描 2.4 GHz
  的 12、13 信道。

- 每个已配置网络都会保留扫描到的全部信道，并按 RSSI 顺序依次尝试。企业 WLAN
  控制器可能广播无法直接关联的 BSSID，因此每个信道内由驱动选择可关联 AP。未固定
  候选会正确保持 BSSID 和信道为空。一次完整连接轮次失败后按 5、10、30、60 秒退避；
  成功连接或用户主动刷新会重置等待时间。

- ESP32-C3 Station 配置提升为 6 个静态 RX、16 个动态 RX、16 个动态 TX、
  12 个管理短缓冲区及 6 帧 RX BA 窗口。软件绘制 Shape 填充时会定期让出 CPU，
  单核任务看门狗窗口调整为 15 秒，使正常的 LVGL 绘制和 TLS 运算可以完成，
  避免产生看门狗报告。

- 新增用于 ESP32-C3 的 Swift Tibo 重置追踪器。FreeRTOS 工作任务通过 HTTPS
  访问 codex-resets.com 状态接口并校验证书；页面展示最近重置、计划重置或关注状态、
  Tibo 最新 X 内容、GMT+8 时间、缓存与网络状态，支持 OK 键立即刷新，并按状态选择
  三张存放在 Flash 的 RGB565 头像。`main` 下的应用及输入运行代码均使用 Swift，
  `HeaderBridge.h` 是该组件唯一保留的 C 系列源码接口。追踪器配置会关闭 USB
  屏幕投送并限制 Wi-Fi 缓冲区数量，为无 PSRAM 设备上的界面更新和 HTTPS 握手保留
  足够的内部内存。

- 将可选的 Wi-Fi 与 Wi-Fi RX 优化代码保留在 Flash，继续释放超过 27 KB 内部
  RAM；默认接收缓冲数量保持不变，确保无 PSRAM 的 ESP32-C3 可以在
  `esp_wifi_init()` 期间分配 DMA 缓冲。

- 四个 Wi-Fi 信号点保持固定的 active/inactive 透明度，未激活的点保持 45% 透明度作为
  可见占位符。连接过程中，每个点通过 LVGL 保留动画在两个透明度之间连续缓动，相邻点
  间隔 130 ms，形成从左到右的波动，同时避免重复构建 View 树。

- 将可复用硬件封装和 Wi-Fi 连接状态机从 `main/legacy/` 移至正式应用模块
  `main/platform` 与 `main/wifi`。默认的无凭据构建会保持 Wi-Fi 射频关闭，并记录跳过
  启动，不再创建网络任务。

- 新增 EmbeddedSwiftUI 综合连接状态指示器，并将其设为 `PassportApplication`
  默认页面。双层电量圆弧、蓝牙状态图标和四个 Wi-Fi 信号点会根据 CW2017 电量、
  蓝牙控制器与 NimBLE 连接状态、当前 Wi-Fi RSSI 定时刷新。

- 将双球加载动画从每 500 毫秒一次的定时状态更新改为单次创建、自动反向的 LVGL
  动画。与完整 List 同时显示时会保留中间帧，每个半周期也无需重建整个应用 View
  树。

- 为组件内所有应用 Swift 源文件生成 EmbeddedSwiftUI 动态属性注册代码，确保新加
  View 的 `State`、`Binding` 和环境属性可以正常保持；实体按键 modifier API
  更正为 `onPhysicalButton`。

- 恢复上游 `_UnaryViewAdaptor` 和 `ViewTypeVisitor` 构建入口。嵌入式 adaptor
  直接转发 unary 构建，不增加 graph 或 renderer 节点。

- 修复五项 EmbeddedSwiftUI 兼容性问题：嵌套 unary/custom modifier 保留配置中的
  隐式根布局；State 的 body 捕获固定到原挂载；Stack 按优先级分组分配空间；
  保留长动画时长，计时器量化移入 LVGLRendererAdaptor；嵌套及兄弟 eager 集合
  共享有界展开预算。新增核心层及 LVGL 计时回归验证。

- 修复双球加载动画和完整 EmbeddedSwiftUI List 同时渲染时反复重启的问题。
  嵌入式 renderer 会在创建布局节点时逐步释放临时 display command，并在挂载
  新 LVGL 树前释放构建产物。新增 command 生命周期及组合动画、输入、生命周期
  回归验证。

- 修复 EmbeddedSwiftUI modifier 属性安装、旧 Binding 生命周期、依赖 proposal 的
  padding 和自定义对齐回调。新增类型化属性生命周期 box、独立 host 事务、
  分离的显示/稳定身份及 eager ViewList 遍历元数据。平台配置提供隐式根布局。
  LVGL 在重绘时保留目标未变化的活动动画，接受空路径并拒绝不支持的反射变换。
  布局放置使用显式工作栈，16 KiB 门禁保持不变；补充嵌入式调整说明与回归覆盖。

- 修复 Shape 在 opacity 动画中缩放时被裁成圆角矩形的问题；每次缩放更新都会
  刷新父级 LVGL 离屏层边界。

- 生产固件的 ESP-IDF C/C++ 代码改为按大小优化，实测应用镜像减少
  53,104 字节，同时保留调试符号和运行时断言。

- 修复 geometry effect 或 renderer effect 包装后的 View 无法正确应用
  `zIndex(_:)` 的问题。Trait 现在会保留在 ViewList 根节点上，重叠的 LVGL
  同级节点会随 z-index 变化正确切换前后顺序。

- 修复完整 EmbeddedSwiftUI List 更新耗尽 ESP32-C3 栈与堆的问题。Identity scope
  改为保留嵌套 display list，解析和 LVGL 挂载使用显式帧栈，布局只接收度量
  Provider，renderer 元数据不再通过 Dictionary COW 重建，输入更新会被合并，
  Circle 裁剪使用 LVGL 原生圆角。所有嵌入式特有差异均由静态检查强制保留
  `Embedded adaptation:` 源码注释。

- 通过写时复制的 View 输入和不可变共享 builder pair 存储，降低 EmbeddedSwiftUI
  递归构建的栈占用；分支环境、事务、状态安装和结构身份语义保持不变。新增带保护页的
  16 KiB LVGL 主机栈回归，覆盖完整 List 示例及重复动画/滚动更新。

- 扩展 EmbeddedSwiftUI 的同步 OpenSwiftUI 兼容实现：加入编译期动态属性注册、
  嵌套 `@State`、`Binding`、环境键、显式/keyed View 身份、按身份处理的生命周期
  与滚动恢复、局部动画事务，以及 LVGL 挂载前的 proposal 布局。
  修复根 trait modifier 构建、自定义 modifier 计数、背景尺寸和非正方形椭圆。
  平台度量/默认值和图片解析由适配层提供，SwiftSyntax 生成工具只在构建主机运行。

- PassportMirroring toolbar 新增截图和 H.264 录屏按钮。截图与录屏使用原始
  240 × 320 投屏帧。录屏会立即写入临时文件，停止后再选择目标位置；取消或
  保存失败时删除临时文件，确认保存时移动录屏结果。

- EmbeddedSwiftUI 按照 upstream geometry effect 流程新增 `rotationEffect`。
  该修饰符保持原布局测量结果，并将角度和锚点映射为 LVGL 图层旋转，同时支持
  溢出边界和隐式动画。

- 新增与 upstream 兼容的 `_ViewTraitKey` 和 `ViewTraitCollection` 基础能力。
  EmbeddedSwiftUI 现在无需 AttributeGraph 即可保存、覆盖、读取默认值及合并
  强类型容器 trait。

- EmbeddedSwiftUI 新增与 upstream 兼容的 `zIndex(_:)` trait。同步布局保持源码
  顺序计算位置，并按稳定的 z-index 升序绘制重叠同级视图；LVGL 重叠容器采用
  相同顺序。该修饰符现在通过通用 `_TraitWritingModifier` 和
  `ViewTraitCollection` 写入 `ZIndexTraitKey`。

- 优化抖音双球加载指示器，采用更顺滑的水平交错曲线，并同步切换前后层级，
  同时保留青色与红色圆点的大小和透明度交换效果。连续动画事务现在会在切换
  z-index 顺序前读取 LVGL 当前呈现状态，避免两球展开时从过期帧发生跳变。

- 单屏 EmbeddedSwiftUI 入口现与上游 App 宿主模式对齐，并省略 Scene 层。
  `LVGLHostingController` 会绑定当前 LVGL display，每次渲染根据其逻辑分辨率
  重新创建 `RootGeometry`、应用安全区内容范围，并在 display 分辨率变化时自动
  标记需要重新布局。

- 修复 `List` 和 `ForEach` 的实体按键传递。未处理的按键现在会沿实际内容返回，
  不再读取原始视图的 `Never` body 并触发非法指令崩溃。

- 修复 Shape 效果持续动画期间触发任务看门狗的问题。缩放和分层透明度缓冲区改为
  覆盖实际溢出子树，不再覆盖整屏；Shape 边集合与扫描线交点存储也会跨帧复用。
  原有溢出显示和裁剪行为保持不变。

- EmbeddedSwiftUI 新增 `opacity(_:)` 渲染效果，支持嵌套透明度相乘、完全透明时
  停止响应按键，以及隐式动画。LVGL renderer 会通过分层透明度作用于合成后的
  整个子树。

- 修复抖音双球加载指示器在设备上保持静止的问题。动画改用 LVGL 可插值的不同
  起止状态和自动反向循环，应用定时器也会处理视图出现时触发的状态更新。

- EmbeddedSwiftUI renderer 现已支持 `onAppear`、`onDisappear` 和带锚点的
  `scaleEffect` 修饰符。`frame` 与 `offset` 现可接收
  `Double` 参数，并将校验后的尺寸四舍五入为物理像素。LVGL 定时器现在可在
  自身回调中安全失效。

- 避免 LCD 启动时闪过未初始化的白色和黑色画面。背光控制现在会在面板初始化前
  完成配置，并保持关闭，直到 LVGL 同步绘制出完整的应用首帧。

- 将平台无关的 retained renderer 合并到 `OpenSwiftUI` 模块。package 和固件现在只
  构建 `OpenSwiftUI` 与 `LVGLRendererAdaptor` 两个 target。

- 为嵌入式 OpenSwiftUI 新增与 SwiftUI API 形态一致的 `Spacer(minLength:)`。
  栈布局会将剩余建议尺寸分配给 Spacer，同一布局中的多个 Spacer 也会参与分配。

- 修复 ESP32-C3 上 OpenSwiftUI 的 Shape 填充、曲线描边和非矩形
  `clipShape` 蒙版渲染。曲线填充改为连续扫描线区域，消除了原三角扇形产生的
  放射状接缝；同时启用 LVGL 的复杂软件绘制、ARGB8888 中间层和 A8 蒙版缓冲区。
  ST7789 显示屏继续使用 RGB565 输出。

- 修复嵌套 View 修饰符导致的 OpenSwiftUI 启动重启：根 View 的构造与首次挂载改在
  LVGL 定时器任务中执行，和按键触发的重绘使用同一任务。

- 修复静止画面导致 USB 投屏误断开的问题。macOS 接收端将已连接后的完整帧
  超时调整为七秒，覆盖固件五秒的空闲关键帧周期；保留三秒首帧超时，
  串口错误仍立即触发断开。

- 新增与 SwiftUI 一致的 `clipped(antialiased:)` 和 `clipShape(_:style:)` 修饰符，支持同步 `Path` 裁剪传递、LVGL 原生矩形和圆角裁剪，以及有内存上限的当前 View 局部 A8 自定义形状蒙版。

- 修复 LVGL retained renderer 中 `offset` 位于背景内时扩大背景的问题。
  背景保持原 frame 尺寸，仅内容绘制位置偏移。

- OpenSwiftUI 动画现在会在两次渲染之间对结构一致的 LVGL 节点位置、宽高和背景
  RGBA 进行插值。`offset` 会从旧值移动到新值，不会重新定位兄弟视图，也不会被
  原始 bounds 裁剪。滚动容器继续按视口裁剪；视图树结构变化时继续使用淡入淡出过渡。

- 新增 LVGL USB 实时投屏与最小 PassportMirroring macOS 接收程序。
  数据流采用 RGB332，保留 240×320 分辨率，支持自动连接、断线重连、逐行压缩和
  数据校验；默认上限为 30 fps，可配置为 60 fps，并通过变化行传输和周期关键帧
  降低带宽、恢复丢包。macOS App 提供等待设备、正在连接、已连接和 USB 已释放
  状态界面，支持手动重连，并在缩放时保持内容区域为 3:4；刷机模式可在不关闭
  App 的情况下释放串口。

- 将 OpenSwiftUI 演示扩展为可滚动的能力画廊，覆盖字体、颜色、栈布局、frame、
  padding、背景、offset、形状填充与描边、裁剪、条件内容及范围 `ForEach`。
  每次按 OK 时会切换面板状态并播放动画，同时保留 List 及其滚动位置。能力画廊
  使用分组行和原生圆角裁剪，确保首次启动和动画替换保持在 ESP32-C3 的 LVGL
  内存预算内。

- Embedded OpenSwiftUI 源码已与参考文件对齐，记录 Text 和 RenderSink
  兼容适配并增加源码检查，同时保留现有 List、ScrollView、ForEach 实现。

- 新增 Embedded Shape 渲染链路：支持浮点 `Path` 命令、`Shape`/`ShapeStyle`、
  `FillStyle`/`StrokeStyle`、矩形、圆角矩形、胶囊、椭圆、圆，以及 `fill`、
  `stroke`、`strokeBorder` 和 `InsettableShape`。同步 sink、visitor、
  `EmbedRenderer` 与有界 LVGL draw-event 后端已同步支持 Shape；实现不使用整屏
  Canvas 或 ThorVG。

- 补齐嵌入式 OpenSwiftUI transaction 与动画路径：新增 `Transaction`、
  `withTransaction`、按值跟踪的 `View.animation(_:value:)`、顺序敏感的
  delay/speed 组合、三次 Bézier 与弹簧计算、repeat/autoreverse 执行，以及替换和
  卸载时的 LVGL 动画取消与资源清理。

- 将嵌入式 OpenSwiftUI API 与所提供的 `OpenSwiftUICore/Embedded` 实现对齐，新增
  自定义 `Layout`、`LayoutSubviews`、栈布局、任意 View 背景、偏移和严格的布局参数
  校验；`ScrollView` 采用标准 API 形状，并支持同步渲染 Sink 的测量与裁剪。

- 新增与参考固件接口一致的 OpenSwiftUI 兼容渲染路径：支持根 View 中保留的
  `@State`、静态 `Image`、作为 View 使用的 `Color`、`foregroundStyle`、
  物理按键处理、测量式布局、同步渲染 Sink 和 `EmbeddedViewHost`。

- 将嵌入式 UI 拆分为三个 package target：`OpenSwiftUI`、平台无关的
  `EmbedRenderer` 和 `LVGLRendererAdaptor`。通用 LVGL UI 包装与 Bridge 已迁入
  adaptor，当前固件 target 只编译显示 `OpenSwiftUIDemoView` 所需的文件，原应用页面
  与服务统一隔离到 `main/legacy`。

- 为 OpenSwiftUI 应用新增顶层 RGB565 屏幕截图 API，包含 LVGL 加锁、明确的缓冲区生命周期和内存分配失败返回值；新增尚未接入业务的 BLE 截图服务，可识别专用指令，并返回元信息、按 MTU 分片的数据和 CRC32。

- 修复 OpenSwiftUI 启动循环：嵌套绘制超过 LVGL 默认 7 KiB 栈。BSP 改用可配置的 16 KiB 任务栈，要求已有配置的 LVGL 内存池至少为 48 KiB，并定期记录 UI 栈余量和剩余堆内存。

- 扩展嵌入式 OpenSwiftUI：新增 List、ScrollView、范围 ForEach、ZStack、动画值、显式 `withAnimation` 切换、物理按键处理、字体、对齐及按顺序组合的样式与布局修饰符。`App.body` 简化为直接返回根 View，不再经过 Scene 或 WindowGroup；平台初始化放入具体 App 的初始化方法，LVGL adaptor 的 `App.main()` 直接挂载 UI；输入通过队列交给 UI 线程，并新增真实 LVGL 后端测试。

- 新增 OpenSwiftUI 嵌入式源码子集和独立 `EmbedRenderer` target。固件启动后进入
  声明式计数器，支持 UP/DOWN 调整、OK 清零和长按 OK 返回 Agent Monitor。
  新增限制节点数量的 LVGL 子树渲染、Embedded Swift 主机测试和启动页面配置项。

- 优化 Agent Monitor UI 和 Codex 实时限额：仪表盘现在在中间显示会随状态变化的机器人，并显示 5h/1w 已用量进度条，进度条按绿、蓝、黄、红变化；有正数重置次数时显示该数量。连接页面移除机器人和按键操作提示。打开蓝牙页面后会自动开始首次配对广播，页面只显示大号验证码或 `CONNECTED`。已配对 Mac 的 bridge 会异步读取本机已登录 Codex app-server 的限额，并通过已认证 BLE 链路只返回简短限额数值。

- 主菜单改为第一阶段 Agent Monitor：Mac CoreBluetooth bridge 将简短的 Codex Hook 生命周期状态通过可连接 NimBLE GATT 服务发到设备，设备以无边框仪表盘显示一个焦点 session，并预留紧凑的 TOKENS 与 RESETS 指标，UP/DOWN 切换已保留 session，独立音频任务在权限请求时播放高音三连提示、在任务完成时播放低音双音提示。新增 Mac bridge、Hook 模板、协议和安全边界文档，以及 session 状态主机测试。

- 新增本机 `CONNECT` 菜单、只显示已知 Wi-Fi 的扫描页和 Agent Monitor 单 Mac 安全所有者。设备生成准确的公开 BLE 名称，必须在设备本机开启配对、输入六位验证码后才能完成已认证 Secure Connections 配对；固件保存一个所有者 bond，后续通过控制器白名单过滤连接请求，并且只通过已认证、已加密、128 位密钥的链路接收任务状态。Mac bridge 现在必须传入准确设备名后才会扫描并连接。

- 主页改为横向分页 App 轮播：每个现有 View Controller 页面都有标题和一行功能说明，上下键会带动卡片向左或向右移动，确认键进入选中页面，白色圆点与蓝色选中态标记当前位置，并与原有右下角机器人动画同一行。共享状态栏持续显示在各页面顶部，保留 Wi-Fi 状态，重绘并居中 Bluetooth 图标，并加入更宽、更矮且带实心端头的电量条。

- 修复 LVGL 主题裁剪后的背景透明问题：所有视图设置背景色时都会设为完全不透明，深色界面的标签默认使用白色文字。

- 重新设计设备端界面：英文状态栏、页签和单个焦点内容卡作为主界面；独立控制中心提供大尺寸 Wi-Fi 与 Bluetooth 卡片，并明确显示焦点、详情入口和关闭操作。全局配色改为黑色背景、白色文字、深色卡片和低饱和青绿色选中状态。

- 新增开机自动连接 Wi-Fi：在耗时较长的外设检查前启动，单次扫描后复用匹配信道，并按配置顺序连接第一个可见的普通密码或 EAP-TLS 候选网络。个人网络在切换候选前快速重试同一候选的认证；Wi-Fi 扫描页保留扫描入口，首页以高对比度图标显示已连接、连接中和未连接状态。本地凭据继续排除在 Git 之外。

- 将应用页面迁移至 Embedded Swift 6.3.3，保留 BSP 初始化、按键分发、功能菜单和低功耗页面；同时固定 Espressif 官方 `idf_swift` 组件版本以保证构建结果可复现。

- 加入厂家为优特利 520mAh 电芯生成的 80 字节 CW2017 profile，并实现内容与更新标志检查、写入后校验、规定的重启时序以及有上限的 SOC 就绪等待。

- 按功能域整理文档并采用双入口：根目录 `AGENTS.md` 变为薄路由（只保留硬约束与任务路由），详细的 AI 开发工作流下沉到 `docs/development/ai-guide.md`，`agent-guide.md` 并入其中。为 `docs/development/` 增加二级分区（`engineering/`、`ci/`、`release/`），把 `plays/` 应用档案与 `experiences/` 移入带专属 README 的 `docs/reference/` 参考区；删除 `docs/software-design/`（空脚手架）；把 `assets/{fonts,images,music}/README` 三个叶子 README 并入 `assets/` README；把 `project-completion` 的六个子文档压平为单文件；并把每个目录统一为单一 README，消除所有 `INDEX` 文件与一处重复经验索引。所有交叉引用与文献链接已更新；未丢弃任何内容。

- 将小程序 BLE 安装兼容提升为二创模板强制契约：固定保护 `cardid`/Recovery 分区，
  保留上键持续 5 秒进入 Recovery 的 bootloader hook，并在 CI 强制校验合并镜像结构、
  分区表 MD5/范围、3 MB 应用上限和保护分区数据不入包。
- 规定多应用发布的 Release 标题约定：tag 按 `v<版本>-<应用名>`（如 `v0.1.0-voice-keychain`）命名，让 Release 标题同时带版本与应用名；发布成功后核对标题，保证一眼扫 Release 列表就能区分是哪个应用。
- 新增发布后收尾流程：`issue-suggestions` skill 用于把用户反馈作为 issue 提交到上游项目；`experience-pr` skill 用于把可复用的开发经验作为文档 PR 提交；新增 `docs/experiences/` 目录保存单条经验文件；并配套 `project-completion`、`file-issues` 与经验索引文档。
- 精简仓库根目录：将 GitHub 可识别的社区治理文档迁入 `.github/`，将变更记录迁入 `docs/`，同步全部引用，并在仓库检查中加入根目录文档白名单。
- 全仓库文档语言规范：所有维护中的 Markdown 默认 `.md` 文件使用英文，简体中文使用配对的 `.zh_CN.md`，双方提供语言切换；静态检查会阻止缺失配对、缺失切换链接或英文默认页混入中文正文。
- AI 开发流程一期：精简按任务加载的上下文入口，统一本地/CI 验证脚本，新增 PR 自动构建与模板，并提交依赖锁文件以提高构建可复现性。
- PR 审查修复：GitHub Actions 固定到完整 commit SHA，构建与发布 job 按最小权限拆分，同步 checkout 关闭凭证持久化；补充 Feature Request / Usage Question issue 表单；启用并修正私密安全报告兜底说明；清理 README 路径、CI 触发条件与历史分支描述漂移。
- 语言规范变更：commit 标题、PR 标题与 body 由"默认中文"改为**使用英文**（`docs/contribution/commit-and-pr.md` 更新）；中文写作规范（全角标点）适用范围剔除 PR/MR 描述（`doc-conventions.md` 更新）。
- CI 构建改造：`build-firmware.yml` 显式传入 `SDKCONFIG_DEFAULTS=sdkconfig.defaults` 再 `idf.py build`，由 defaults 启用自定义分区表（`CONFIG_PARTITION_TABLE_CUSTOM=y`，文件名为 `partitions.csv`）；`CONFIG_ESPTOOLPY_HEADER_FLASHSIZE_UPDATE` 改为 `n`，再用 `idf.py merge-bin -o build/FoloToy-AI-Passport-full.bin` 合并可直刷完整固件；产物精简为仅 full.bin；`actions/cache` 升级到 v5 以消除 GitHub Actions Node.js 20 弃用警告；CI 文档同步更新。
- 合并上游 PR #6（wireless-low-power-demos）以解决 PR #4 冲突：引入无线/低功耗 demo（`main/demo_wifi.c`、`demo_ble.c`、`demo_radio.c`、`demo_low_power.c`）、`partitions.csv`（NVS/PHY/3 MB factory-app 分区）、`main/CMakeLists.txt`/`main.c`/`demo.h`/`sdkconfig.defaults` 更新；同步硬件指南的 Wi-Fi/BLE/低功耗章节；README 能力契约表补充 Wi-Fi/Bluetooth LE/Low power 三项（中英双语）。
- 提交规范补充：`docs/contribution/commit-and-pr.md` 明确 PR 标题与 commit 标题使用相同的 Conventional Commit 格式和英文祈使句，不用名词短语当标题。
- CI 与文档清理：`sync-main.yml` 移除 `test_mode` 残留模板注释；`docs/development/coding-conventions.md` 将「Redis TTL」条目泛化为「缓存组件」条目（当前固件无 TTL 约束需求，消除从模板带入的无关约定）。
- 补充通用规范（借鉴 Shinku）：`docs/contribution/doc-conventions.md` 新增中文全角标点规范（正文 `，`；`（`）`，代码/命令/路径保留英文原样）、凭证不入仓规范（token/密钥/私钥绝不入仓，提交前 git diff 扫描敏感前缀）、文件删除安全规范（删除走系统回收站，不用 rm -rf/git clean -fd）。
- 代码注释规范强化：`docs/development/coding-conventions.md` 补充完善注释要求——函数说明（用途/参数/返回值/副作用/线程上下文/内存所有权/初始化顺序）、变量说明（语义/取值范围/生命周期/同步要求）、逻辑注释（状态机/时序/寄存器/魔数依据），覆盖范围宁多勿少，中文注释保留英文技术术语。
- 文档去 AI 化：`docs/README.md` / `docs/README.zh_CN.md` 移除 AI 专属章节（Entry point、Source-of-truth、提需求格式、BSP 边界、Runtime invariants、验收交付格式、构建命令），README 只保留给人看的项目介绍、硬件能力契约、demo 案例与项目结构；构建命令章节删除（与 `docs/development/build-and-test.md` 重复）。
- 新增 `docs/development/agent-guide.md`：集中承载"AI 如何在本仓库工作"（上下文建立顺序、事实来源优先级、提需求格式、BSP 边界、运行时规则、交付格式），并链接 build-and-test 与硬件指南，不重复构建命令与验收矩阵。
- 同步更新索引：`AGENTS.md` 规则索引新增 agent-guide 条目；`docs/INDEX.md` 与 `docs/development/README.md` 新增 agent-guide 索引行。
- 文档补充：`docs/fork-guide.md` 说明「为什么根目录不放置 README」——根目录 README 预留给 fork 开发者自行放置（上游留空），fork 后可将自己的内容写入根目录 `README.md` 介绍 fork 后的项目；GitHub 显示优先级（根 README > docs/README.md）契合该预留意图。
- 分支合并：创建 `main-update` 分支（基于与上游一致的 main），将 `feature/repo-structure`、`ci/build-firmware`、`ci/sync-main` 三个分支合并进来，统一 docs 结构（CI 文档归入 `docs/development/`，workflow 文件随 ci 分支引入 `.github/workflows/`）；解决 development/software-design README 的 add/add 冲突。
- 合并后审查修复：`docs/INDEX.md` 补充 CI 文档索引；`docs/fork-guide.md` 修正 workflow 引用为 `.github/workflows/sync-main.yml`；`docs/README` 双语项目结构块补充 `.github/workflows/` 与 CI 文档说明。
- ci 分支 CI 文档路径调整：`ci/build-firmware` 的 `docs/software-design/CI-build-and-release.md` 与 `ci/sync-main` 的 `docs/software-design/CI-sync-main.md` 均移入各分支的 `docs/development/`（CI 属工程规范）；`docs/software-design/README.md` 保留为软件设计索引；feature 分支的 software-design 索引同步更新引用。
- fork 补充文档目录迁移：`assets/docs/` 移至 `docs/assets/`（文档素材归入 docs/ 更合理），新增 `docs/assets/.gitkeep` 空目录占位；同步更新 AGENTS.md / INDEX / doc-conventions / fork-guide 的路径引用。
- 文档结构调整：根目录不再放 README——上游英文 README 移入 `docs/README.md`、中文移入 `docs/README.zh_CN.md`（GitHub 从 docs/ 识别主 README）；原 `docs/README.md` 根总索引更名为 `docs/INDEX.md`；同步更新 AGENTS.md / CONTRIBUTING / SUPPORT / fork-guide / doc-conventions 的路径引用。
- 初始化项目文档：新增 `AGENTS.md`、`CLAUDE.md` 和 `CHANGELOG.md`。
- 仓库结构规整：上游英文 `README.md` 更名为 `README.en_US.md`，保留 `README.zh_CN.md`。
- 新增目录骨架：`docs/`（software-design / hardware-design）、`assets/`（fonts / images / music，各含 `README.md`）、`skills/`。
- 将上游硬件开发指南归位到 `docs/hardware-design/AI_HARDWARE_DEVELOPMENT_GUIDE.md`。
- 文档规范：子目录 readme 统一为大写 `README.md`；补充 fork 用户约定（main 只动根 README）。
- 扩展 fork 用户约定：`main` 分支允许修改根目录 `README.md` 和 `assets/docs/`（README 不足以说明项目时存放补充文档与素材）。
- 新增 `assets/docs/` 目录约定：上游 main 只保留空目录 `.gitkeep`，内容文件仅存在于 fork；使用方法规范写入 AGENTS.md「给 fork 用户」约定。
- CI 文档迁移：`docs/software-design/CI.md` 从本分支移除，迁至 `ci/build-firmware` 分支并改名为 `docs/software-design/CI-build-and-release.md`。
- 补充 `main` 分支策略说明：解释 `main` 保持干净的两大原因（与上游同步无冲突 + 多小项目按分支整理）；例外——执意 main 开发需停用 CI 自动同步；提醒 fork 用户默认 action 关闭需手动启用（此条为整个 CI 的通用要求，统一写入 AGENTS.md）。
- 文档拆分：将 `AGENTS.md` 按主题拆为公共文档——新增 `docs/contribution/`（doc-conventions.md、commit-and-pr.md）与 `docs/development/`（build-and-test.md、coding-conventions.md），新增 `docs/fork-guide.md`；`AGENTS.md` 精简为简介 + 项目概述 + 必读文档索引。
- 同步更新索引：`docs/software-design/README.md`、`README.en_US.md` / `README.zh_CN.md` 的 `docs/` 目录说明。
- 参考 cindy 仓库文档组织完善索引：新增 `docs/README.md` 根总索引；AGENTS.md 规则索引按触发场景改写（附触发条件）；`docs/contribution/` 与 `docs/development/` 的 README 补充收录标准。
- 引入社区治理文档（参照 cindy 改写，放仓库根目录）：新增 `CONTRIBUTING.md` / `.zh_CN.md`（贡献指南，针对 ESP-IDF/AI agent/fork 场景改写）、`CODE_OF_CONDUCT.md` / `.zh_CN.md`（贡献者公约）、`SECURITY.md` / `.zh_CN.md`（安全报告流程）、`SUPPORT.md` / `.zh_CN.md`（支持渠道）；AGENTS.md 与 docs/README.md 同步引用。
