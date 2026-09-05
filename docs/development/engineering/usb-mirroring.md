<p align="right">
  <a href="usb-mirroring.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# USB Mirroring MVP

Build and install the firmware using [Build and Test](build-and-test.md), then
open `PassportMirroring/PassportMirroring.xcodeproj` and run the macOS app.
Connect one Passport using a USB data cable and close serial monitors before
starting the app. The window automatically displays the screen and reconnects
after unplugging. Before flashing or opening a serial monitor, click
**Release USB for Flashing**. The image pauses after the receiver closes the
serial descriptor; flash normally, then click **Resume Mirroring** to reconnect.
The app can remain open throughout this sequence. A single USB Serial/JTAG port
cannot carry mirroring and flashing traffic concurrently. The local development
app disables App Sandbox to open the serial device.

The receiver matches Espressif USB Serial/JTAG VID `303a`, PID `1001`. This MVP
supports one connected Passport. It has no recording, controls, audio, or settings.
After connecting, seven seconds without a validated mirror packet pauses
mirroring and offers manual reconnect. This covers the five-second idle
key-frame interval plus two seconds of transfer/scheduling margin. The initial
validated-packet wait remains three seconds per port attempt; a full key frame
can arrive over several bounded stripes. Manual reconnect retains its five-second
overall deadline. Serial I/O errors still disconnect immediately.

## Capture and transport

- LVGL `FLUSH_START` copies RGB565 pixels before the display port swaps bytes.
  The firmware places each changed pixel from the native 240×320 display into
  row segments in a bounded 24-entry queue. It retains no complete mirror
  framebuffer. The macOS decoder converts the fixed RGB565 stream directly to a
  native 240×320 RGBA frame for display, screenshots, and recording.
- The row queue occupies approximately 12 KiB of internal RAM. The USB task adds
  a 5,120-byte stack, 1,024-byte TX buffer, 256-byte RX buffer, and driver
  overhead. Allocation failure logs a warning and keeps the local display running.
- `sdkconfig.defaults` keeps the optional Wi-Fi and Wi-Fi RX optimized routines
  in flash. Espressif documents more than 27 KB of combined internal-RAM savings.
  Together with the bounded station buffers, this leaves memory for mirroring,
  TLS, and UI updates on the no-PSRAM ESP32-C3.
- Capture callbacks never wait for queue capacity. Delta capture rotates through
  the dirty flushes and through stripes within a tall, narrow flush. Each LVGL
  refresh contributes at most one independently framed update of 20 rows, so it
  cannot fill the queue before `REFR_READY`. An update is skipped when its complete
  row set and frame boundary cannot fit. Compression and blocking USB writes run
  in a separate task.
- The app sends ASCII `M` every 500 ms. Firmware sends while that request is less
  than two seconds old. Changed LVGL regions are transmitted as they are flushed.
  A complete key frame every five seconds repairs packet loss and updates pixels
  omitted by an overloaded delta frame.
- A key frame is redrawn and captured in 20-row stripes. Firmware starts the next
  stripe only after the previous stripe has left the queue, so a 153,600-byte
  image never needs to reside in ESP32-C3 RAM. Unrelated flushes from continuous
  animations are ignored while key-frame capture is active. All stripes share
  one frame sequence and one final frame-end packet.
- The USB and LVGL tasks both run at priority 4 so FreeRTOS time slicing advances
  transmission during animations. Blocking USB writes naturally yield CPU time.
- Console output uses the same USB driver's queue. Boot logs and other bytes are
  skipped by the receiver. Damaged or incomplete frames are discarded until the
  next key frame.

## Wire format, version 6

Each row packet contains one horizontal segment. Multibyte integers are little
endian. The protocol has one fixed pixel format: 240×320 RGB565. Each packet ends
with FNV-1a over its header and payload.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `PMIRROW6` |
| 8 | 1 | Type: `1` row segment, `2` frame end |
| 9 | 1 | Row bit 0: PackBits; frame-end bit 0: key frame; all other bits must be zero |
| 10 | 2 | Frame sequence, wrapping at 65535 |
| 12 | 2 | Row index, or transmitted segment count for frame end |
| 14 | 2 | Payload byte count |
| 16 | Variable | Raw segment or byte-oriented PackBits data; empty for frame end |
| 16 + payload length | 4 | FNV-1a: initial 2166136261, multiplier 16777619 |

A decoded row payload starts with a little-endian 16-bit first-column index,
followed by 1–240 little-endian RGB565 pixels. This supports partial-width LVGL
flush areas and multiple segments for the same row. For a PackBits control byte with its high bit
clear, the next `control + 1` bytes are literals. With its high bit set, the
following byte repeats `(control & 0x7f) + 2` times. Compression covers both the
first-column field and pixels and is used only when it shortens the payload.

The frame-end count is the number of row-segment packets in that frame. A key
frame is accepted only when its validated segments cover all 240×320 pixels.
The receiver retains the previous complete image, applies valid delta segments,
and presents only at a valid frame boundary. The sender and macOS receiver
implement only the fixed `PMIRROW6` format.

An uncompressed 240×320 RGB565 wire frame is 153,600 bytes. Pixel payload alone is
approximately 4.61 MB/s at 30 fps and 9.22 MB/s at 60 fps. Actual throughput
depends on changed area, PackBits ratio, USB capacity, and device load; continuous
full-screen high-entropy content cannot sustain those rates.

Protocol tests run as part of `./tools/validate.sh --static`. On macOS, this also
tests the receiver over a pseudo-terminal: five-second idle key frames, outgoing
heartbeats, stalled-stream disconnection despite console traffic, manual
reconnect gating, and the initial-frame timeout.

## Device acceptance

Verify initial display, changing screens, animation, RGB565 color blocks,
orientation, unplug/replug, closing/reopening the app, and normal standalone
operation. Measure static UI, local-animation, and full-screen-animation rates,
plus free/largest internal heap blocks after UI initialization. Build and host
tests alone do not establish these hardware results.
