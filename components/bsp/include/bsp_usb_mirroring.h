#pragma once

#include "esp_err.h"

struct _lv_display_t;

// Call once with the LVGL lock held, after display registration and before UI
// creation. The display and capture task have application lifetime. Allocates
// a bounded queue of 24 RGB565 row segments (approximately 12 KiB) instead of a
// full framebuffer. Delta capture rotates through independently validated
// stripes of at most 20 rows. A 240x320 key frame is captured in 20-row stripes
// after the previous stripe is transmitted; unrelated animation flushes are
// ignored until it completes.
// Failure leaves the local display operational. Capture callbacks never wait
// for queue space; compression and blocking USB work run in a separate task.
esp_err_t bsp_usb_mirroring_init(struct _lv_display_t *display);
