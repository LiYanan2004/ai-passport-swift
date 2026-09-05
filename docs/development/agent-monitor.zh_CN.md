<p align="right">
  <strong>简体中文</strong> · <a href="agent-monitor.md">English</a>
</p>

# Agent Monitor

Agent Monitor 是近距离只读任务状态显示器。Mac 接收 Codex 生命周期 Hook 输入，再通过 Bluetooth LE 向 ESP32-C3 写入简短状态。设备还提供由本机控制的连接菜单，用于查看已配置 Wi-Fi 和完成第一台 Mac 的配对。

## 信任与数据保护

状态上报使用 Bluetooth LE Secure Connections：设备显示六位验证码，连接使用已认证配对、128 位加密密钥和持久化 bond。第一个在设备本机开启配对后成功完成配对的 Mac 会成为唯一所有者。

- 未绑定的设备不会广播可连接服务。进入 `CONNECT` → `BLUETOOTH` 后，首次配对广播会自动开始。
- 设备名为 `AgentMonitor-<12 位大写十六进制>`，由板卡 Wi-Fi MAC 地址生成。它是公开标识，不是密钥。
- 固件只允许一条 BLE 连接，只保存一个 bond。以后启动时，控制器白名单只接受已绑定 Mac 的连接请求。
- GATT 写 characteristic 和限额请求通知要求链路已加密、已认证、已绑定且密钥长度为 128 位。它们会再次检查该 Mac 是否为所有者，然后才写入状态或发送通知。
- Mac bridge 必须传入准确设备名。它扫描 service UUID 后，只会连接广播本地名称完全匹配的设备，因此同一房间的多套部署不会误发到彼此设备。

Bluetooth LE Secure Connections 为每个状态包提供链路机密性和完整性。协议没有再叠加一层应用数据加密格式。蓝牙页面不会替换已经保存的所有者；展示前请保留已经完成的配对记录。

## 数据路径和数据包边界

```text
状态：Codex Hook → 同一用户的 Unix socket → 指定设备名的 Mac CoreBluetooth central → 已认证加密 GATT 写入 → FreeRTOS 队列 → LVGL 屏幕 / 音频任务
限额：LVGL 定时器 → 设备安全通知 → Mac bridge 后台读取 → 已认证加密 GATT 写入 → 最新值队列 → LVGL 屏幕
```

| 项目 | 数值 |
| --- | --- |
| Service UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000001` |
| 写 characteristic UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000002` |
| 限额请求通知 UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000003` |
| 连接和 bond 数量 | 一台 Mac |
| 状态包大小 | 最多 101 字节：版本、状态、16 字符 session hash、标题和详情 |
| 限额响应 | 7 字节：版本、响应类型、可用位、5h 已用百分比、1w 已用百分比和 16 位重置次数 |

Mac bridge 会把 Codex 的 `session_id`，或子智能体的 `agent_id`，转换为大写的 64 位 FNV-1a hash 后再离开 Mac。它不会传出提示词、工具输入、工具输出、记录文件路径、工作目录或模型输出。固件只接收可打印 ASCII 的标题/详情和固定长度的十六进制 session hash。限额响应不含账号标识、凭据、重置额度记录或重置时间。

## 设备操作

仪表盘一次显示一个焦点任务。短按 `UP` 选择上一个 session，短按 `DOWN` 选择下一个 session。长按 `OK` 进入 `CONNECT`；使用 `UP` 和 `DOWN` 选择 `WI-FI` 或 `BLUETOOTH`，短按 `OK` 进入对应模块。在任一模块长按 `OK` 返回 `CONNECT`。

只有仪表盘显示居中的机器人。它的颜色和动作表示待机、工作中、需要操作、已完成和已中断。仪表盘还显示 Codex 5h 和 1w 的已用比例，进度条依次使用绿、蓝、黄、红。已配对 Mac 返回大于零的重置次数时才显示 `RESETS`。页面不显示按键操作提示。

Wi-Fi 页面按需启动 STA 服务，短按 `OK` 扫描。它只按固件配置顺序显示已经配置的 SSID，底部始终显示 `PRESET BEFORE FLASH`。附近未配置的 SSID 不会显示。归档实现从已忽略的 `main/legacy/config/WiFiCredentials.local.swift` 读取凭据。

未绑定设备打开蓝牙页面后会自动开始首次配对广播。页面会保持空白，直到 macOS 请求配对；此时只用大字显示六位验证码。安全连接完成后，页面只显示 `CONNECTED`。成功配对后，该 Mac 会保存为所有者，设备回到只向所有者广播的状态。

| 状态 | 屏幕颜色 | 触发事件 | 声音 |
| --- | --- | --- | --- |
| 工作中 | 蓝色 | session 开始、子智能体开始、提交请求或开始调用工具 | 无 |
| 需要操作 | 红色 | `PermissionRequest` | 每次进入此状态播放一次高音三连提示 |
| 已完成 | 绿色 | `Stop`、`SessionEnd` 或子智能体结束 | 每次进入此状态播放一次低音双音完成提示 |
| 已中断 | 紫色 | `Interrupt` | 无 |

收到需要操作的事件时，屏幕会立即切到该 session。I2S 播放运行在独立 FreeRTOS 任务中，BLE 回调只把验证后的数据写入队列；两条路径都不直接访问 LVGL。

## 编译、配对并运行 Mac bridge

在运行 Codex 的 Mac 上编译 bridge：

```bash
mkdir -p "$HOME/bin"
xcrun --sdk macosx swiftc \
  tools/agent-monitor/mac/AgentMonitorBridge.swift \
  -framework CoreBluetooth \
  -o "$HOME/bin/agent-monitor-bridge"
```

配置 Hook 前先完成板卡配对：

1. 在仪表盘长按 `OK`，选择 `BLUETOOTH`。未绑定设备会立刻开始广播。
2. 在 macOS 中选择显示的 `AgentMonitor-<12 位大写十六进制>` 设备，并记录准确名称，例如 `AgentMonitor-A1B2C3D4E5F6`。
3. 在 macOS 配对对话框中输入设备显示的验证码。
4. 使用这个准确设备名启动 bridge，并在当前登录用户的会话中保持运行。

```bash
"$HOME/bin/agent-monitor-bridge" serve \
  --device AgentMonitor-A1B2C3D4E5F6
```

进程会创建权限为 `0600` 的 `/tmp/agent-monitor-<uid>.sock`，所有者断开后会重新连接，并使用带响应的方式写入数据包。设备通过安全连接请求限额后，bridge 会在后台队列中使用本机已登录的 `codex app-server --stdio` 读取账号限额，再只发送 5h/1w 已用百分比和重置次数。每次读取最多 15 秒，不会阻塞设备 UI。`AGENT_MONITOR_CODEX_EXECUTABLE` 可以指定非标准位置的 Codex 可执行文件。macOS 可能要求向运行 bridge 的终端授予 Bluetooth 权限。

## 配置 Codex Hooks

1. 打开 [codex-hooks.json.template](../../tools/agent-monitor/codex-hooks.json.template)。
2. 将所有 `/PATH/TO/agent-monitor-bridge` 替换为编译后可执行文件的绝对路径。
3. 将事件配置合并进当前用户的 `~/.codex/hooks.json`，保留已有 Hook 配置。
4. 在 Codex 中执行 `/hooks`，检查并信任准确的命令定义。
5. 保持指定设备名的 bridge 进程运行，然后新建或恢复 Codex task。

模板使用 `SessionStart`、`SubagentStart`、`UserPromptSubmit`、`PreToolUse`、`PermissionRequest`、`Stop`、`SubagentStop`、`Interrupt` 和 `SessionEnd`。常规运行事件使用异步 Hook，超时三秒；`SessionEnd` 保持同步，因为 Codex 对该事件使用同步方式。事件字段、信任检查和生命周期说明见 [Codex Hooks 文档](https://learn.chatgpt.com/zh-Hans/docs/hooks)。

## 真机验收

使用项目正常烧录流程，保留 `cardid` 和 Recovery 分区约定，避免执行擦除整片 Flash 的操作。在实机上检查：

1. 启动未绑定设备，确认仪表盘显示 `NO MAC`，且没有可连接广播。
2. 进入蓝牙页面，确认广播自动开始；配对时页面只显示六位验证码，安全连接完成后页面只显示 `CONNECTED`。
3. 重启设备，确认同一台 Mac 可以重连，附近第二台 Mac 无法连接或写入状态。
4. 在同一房间运行两块设备和两个 bridge，各自传入不同的 `--device` 名称，确认每台设备只接收自己的 Hook。
5. Mac bridge 连接后，确认仪表盘更新 Codex 5h 和 1w 已用百分比，且任务状态更新持续正常。确认绿、蓝、黄、红阈值，以及只有正数重置次数才显示 `RESETS`。
6. 打开 Wi-Fi 页面，确认只显示已配置 SSID，底部显示 `PRESET BEFORE FLASH`。
7. 提交 Codex task、触发权限请求、切换焦点 session，并确认工作中、需要操作、完成和中断状态。
8. 在目标板上测量 BLE 范围、音量、剩余堆、功耗和 Wi-Fi/BLE 共存表现。

自动验证继续使用 `./tools/validate.sh --static` 和 `./tools/validate.sh --firmware`；两项检查不能代替上面的真机观察。
