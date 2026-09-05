<p align="right">
  <a href="agent-monitor.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Agent Monitor

Agent Monitor is a nearby, read-only task monitor. A Mac receives Codex lifecycle-hook input and writes compact status events to an ESP32-C3 over Bluetooth LE. The device also exposes a locally controlled connection menu for known Wi-Fi networks and the first Mac pairing.

## Trust and data protection

The monitor uses Bluetooth LE Secure Connections with authenticated pairing, a six-digit code displayed on the device, a 128-bit encryption key, and a persistent bond. The first Mac that completes the locally opened pairing session becomes the sole owner.

- An unbound device does not advertise a connectable service. Open `CONNECT` → `BLUETOOTH` and the first-pairing advertising window starts automatically.
- The device name is `AgentMonitor-<12 uppercase hexadecimal digits>`, derived from the board's Wi-Fi MAC address. It is a public identifier, not a secret.
- The firmware permits one BLE connection and stores one bond. On later boots, controller white-list filtering accepts connection requests only from that bonded Mac.
- The GATT write characteristic and usage-request notification require an encrypted, authenticated, bonded link with a 128-bit key. Their access paths repeat the owner check before queueing an event or notifying the Mac.
- The Mac bridge must be started with the exact device name. It scans the service UUID and connects only when the advertised local name matches exactly, so nearby deployments do not route events to one another by accident.

BLE Secure Connections provides the link confidentiality and integrity for every status packet. The protocol does not add a second application-layer encryption format. The Bluetooth page does not replace an existing owner; retain the pairing record when preparing a board for a presentation.

## Data path and packet boundary

```text
Status: Codex hook → same-user Unix socket → exact-target Mac CoreBluetooth central → authenticated encrypted GATT write → FreeRTOS queue → LVGL screen / audio task
Usage: LVGL timer → secure device notification → Mac bridge background read → authenticated encrypted GATT write → latest-value queue → LVGL screen
```

| Item | Value |
| --- | --- |
| Service UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000001` |
| Write characteristic UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000002` |
| Usage-request notification UUID | `CB9E9B00-9B0E-4B44-9CC7-7077A7000003` |
| Connection and bond limit | One Mac |
| Status packet limit | 101 bytes: version, state, 16-character session hash, title, and detail |
| Usage response | 7 bytes: version, response type, availability bits, 5h used percent, 1w used percent, and a 16-bit reset count |

The Mac bridge converts a Codex `session_id`, or an `agent_id` for subagents, into an uppercase 64-bit FNV-1a hash before it leaves the Mac. It omits prompt text, tool input, tool output, transcript paths, working directories, and model output. Firmware accepts only printable ASCII title/detail fields and a fixed-length hexadecimal session hash. Usage responses contain no account identifier, credential, reset-credit record, or reset time.

## Device controls

The dashboard keeps one focused task session. `UP` selects the previous session and `DOWN` selects the next session. Hold `OK` to open `CONNECT`; use `UP` and `DOWN` to choose `WI-FI` or `BLUETOOTH`, then press `OK` to open that module. Hold `OK` on either module to return to `CONNECT`.

Only the dashboard shows the centered mascot. Its color and motion indicate standing by, working, action needed, completed, or interrupted. The dashboard also shows the consumed Codex 5h and 1w allowances with a green, blue, yellow, or red progress bar. It shows `RESETS` only when the paired Mac reports a positive reset count. No screen displays button-operation hints.

The Wi-Fi page starts the STA service on demand and exposes a manual scan with `OK`. It displays only SSIDs already configured in the firmware, in configured priority order, and always shows `PRESET BEFORE FLASH` at the bottom. Nearby SSIDs that are not configured remain hidden. The archived implementation reads credentials from the ignored `main/legacy/config/WiFiCredentials.local.swift`.

On an unbound board, opening the Bluetooth page starts first-pairing advertising automatically. The screen stays empty until macOS requests pairing, then displays only the six-digit code in large type. Once the secure connection is complete, it displays only `CONNECTED`. A successful pairing saves that Mac as the owner and returns the device to owner-only advertising.

| State | Screen color | Trigger | Audio |
| --- | --- | --- | --- |
| Working | blue | session start, subagent start, prompt submission, or tool start | none |
| Action needed | red | `PermissionRequest` | urgent high-pitched three-tone alert once when entering this state |
| Done | green | `Stop`, `SessionEnd`, or subagent stop | gentle low-pitched two-tone completion chime once when entering this state |
| Interrupted | purple | `Interrupt` | none |

An attention event becomes focused immediately. I2S playback runs in a dedicated FreeRTOS task, and BLE callbacks only enqueue validated data; neither path touches LVGL directly.

## Build, pair, and run the Mac bridge

Compile the bridge on the Mac that runs Codex:

```bash
mkdir -p "$HOME/bin"
xcrun --sdk macosx swiftc \
  tools/agent-monitor/mac/AgentMonitorBridge.swift \
  -framework CoreBluetooth \
  -o "$HOME/bin/agent-monitor-bridge"
```

Pair the board before configuring hooks:

1. Hold `OK` on the dashboard and choose `BLUETOOTH`. The unbound board begins advertising immediately.
2. Select the `AgentMonitor-<12 uppercase hexadecimal digits>` device shown by macOS and record that exact name, for example `AgentMonitor-A1B2C3D4E5F6`.
3. Enter the code shown on the device in the macOS pairing dialog.
4. Start the bridge with that exact name and keep it running in the logged-in user session.

```bash
"$HOME/bin/agent-monitor-bridge" serve \
  --device AgentMonitor-A1B2C3D4E5F6
```

The process creates `/tmp/agent-monitor-<uid>.sock` with mode `0600`, reconnects after an owner disconnect, and writes packets with response. On a secure device usage request, it uses the locally authenticated `codex app-server --stdio` account limit read on a utility queue, then sends only the compact 5h/1w used percentages and reset count. Each read has a 15-second maximum and never blocks the device UI. `AGENT_MONITOR_CODEX_EXECUTABLE` can point to a nonstandard Codex executable. macOS may ask for Bluetooth permission for the terminal that runs the bridge.

## Configure Codex hooks

1. Open [codex-hooks.json.template](../../tools/agent-monitor/codex-hooks.json.template).
2. Replace every `/PATH/TO/agent-monitor-bridge` placeholder with the absolute path of the compiled executable.
3. Merge its event entries into the current user's `~/.codex/hooks.json`; retain any existing hook entries.
4. Open Codex and run `/hooks` to review and trust the exact command definitions.
5. Keep the target-locked bridge process running, then start or resume a Codex task.

The template uses `SessionStart`, `SubagentStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `Stop`, `SubagentStop`, `Interrupt`, and `SessionEnd`. Normal runtime hooks are asynchronous with a three-second timeout; `SessionEnd` remains synchronous because Codex treats that event synchronously. See the [Codex Hooks documentation](https://learn.chatgpt.com/zh-Hans/docs/hooks) for supported event fields, trust review, and hook lifecycle details.

## Device acceptance

Flash using the normal project flow; preserve the `cardid` and Recovery partition contract and avoid erase-flash operations. Verify these behaviors on the physical board:

1. Boot an unbound device and confirm the dashboard says `NO MAC` with no connectable advertisement.
2. Open the Bluetooth page and confirm that advertising begins automatically, the page shows only the six-digit code during pairing, and it shows only `CONNECTED` after the secure link completes.
3. Restart the board and confirm that the same Mac reconnects while a second nearby Mac cannot connect or write an event.
4. Run two boards in the same room with two bridges using their distinct `--device` names. Confirm each hook reaches only its selected board.
5. With the Mac bridge connected, confirm the dashboard refreshes the Codex 5h and 1w used percentages without interrupting task-state updates. Confirm the green, blue, yellow, and red thresholds, and that `RESETS` appears only for a positive reported count.
6. Open the Wi-Fi page and confirm that only configured SSIDs appear, with `PRESET BEFORE FLASH` visible at the bottom.
7. Submit a Codex task, cause a permission request, switch focused sessions, and verify working, attention, completion, and interruption states.
8. Measure BLE range, audio level, heap headroom, power draw, and Wi-Fi/BLE coexistence on the target board.

Automated validation remains `./tools/validate.sh --static` and `./tools/validate.sh --firmware`; neither check substitutes for the physical observations above.
