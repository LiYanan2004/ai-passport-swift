<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Assets

This directory stores reusable fonts, images, music, and sound effects, organized by asset type.

Keep each asset in the matching subdirectory and document its destination, naming, integration method, and source/license. Do not mix binary assets with Markdown documentation.

## Fonts

Store reusable font files and generated font sources in `fonts/`.

- Use descriptive names that include the family, weight, size, and format when relevant.
- Document the source, license, character range, conversion command, and expected destination.
- Check Flash and internal-RAM impact before adding a font; the ESP32-C3 has no PSRAM.
- Do not commit fonts whose license does not permit redistribution.

## Images

Store reusable source images and generated display assets in `images/`.

- Use descriptive names and document dimensions, pixel format, conversion steps, and destination.
- Prefer formats suitable for the 240 × 320 RGB565 display and account for Flash and internal RAM.
- Preserve editable sources where licensing permits, and record the source and license.
- Never commit device QR secrets, credentials, or personal data in images.

### Tibo reset tracker avatars

The tracker uses three project-owner-provided square portraits:

| Source asset | UI state | Original size | Firmware asset |
| --- | --- | --- | --- |
| `images/tibo-reset-confirmed.png` | Reset confirmed within 24 hours | 374 × 374 | `main/assets/tibo-reset-confirmed.rgb565` |
| `images/tibo-reset-announced.jpg` | Scheduled reset or active watch | 400 × 400 | `main/assets/tibo-reset-announced.rgb565` |
| `images/tibo-reset-idle.jpg` | Waiting, normal, or unavailable | 1290 × 1290 | `main/assets/tibo-reset-idle.rgb565` |

Each firmware asset is resized to 100 × 100 and stored as 16-bit RGB565
(20,000 bytes). CMake links the bytes into Flash, and Swift owns the LVGL image
descriptors and state selection. The files were supplied by the project owner
for this integration; confirm public redistribution terms before a release.

## Music and sound effects

Store reusable music and sound-effect sources in `music/`.

- Document the source, license, sample rate, bit depth, channels, conversion command, and destination.
- Prefer 16 kHz, 16-bit mono PCM when it matches the current BSP audio path.
- Check Flash and internal-RAM cost before embedding audio; stream or chunk long recordings.
- Do not commit media without redistribution permission.
