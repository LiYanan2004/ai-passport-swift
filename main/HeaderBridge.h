#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#include "lvgl.h"

#if __has_include("esp_err.h")
#include "esp_err.h"
#else
typedef int32_t esp_err_t;
#define ESP_OK 0
#endif

#if __has_include("esp_bt.h")
#include "esp_bt.h"
#endif

#if __has_include("esp_wifi.h")
#include "esp_wifi.h"

// Swift cannot import the WIFI_INIT_CONFIG_DEFAULT initializer macro.
static inline wifi_init_config_t passport_wifi_default_config(void) {
    wifi_init_config_t configuration = WIFI_INIT_CONFIG_DEFAULT();
    return configuration;
}
#endif

#if __has_include("esp_eap_client.h")
#include "esp_eap_client.h"
#endif

#if __has_include("esp_event.h")
#include "esp_event.h"
#endif

#if __has_include("esp_netif.h")
#include "esp_netif.h"
#endif

#if __has_include("esp_timer.h")
#include "esp_timer.h"
#endif

#if __has_include("esp_http_client.h")
#include "esp_http_client.h"
#include "esp_crt_bundle.h"
#include "cJSON.h"
#endif

#if __has_include("esp_heap_caps.h")
#include "esp_heap_caps.h"
#include "esp_system.h"
#endif

#if __has_include("esp_wifi_default.h")
#include "esp_wifi_default.h"
#endif

#if __has_include("nvs_flash.h")
#include "nvs_flash.h"
#endif

#if __has_include("freertos/FreeRTOS.h")
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

// FreeRTOS queue entry points are macros and therefore need stable functions
// before Swift can import them.
static inline QueueHandle_t passport_queue_create(UBaseType_t length, UBaseType_t item_size) {
    return xQueueCreate(length, item_size);
}

static inline BaseType_t passport_queue_send(QueueHandle_t queue, const void *item) {
    return xQueueSend(queue, item, 0);
}

static inline BaseType_t passport_queue_receive(QueueHandle_t queue, void *item) {
    return xQueueReceive(queue, item, 0);
}

static inline void passport_task_notify_give(TaskHandle_t task) {
    xTaskNotifyGive(task);
}

static inline uint32_t passport_task_notify_take(TickType_t ticks_to_wait) {
    return ulTaskNotifyTake(pdTRUE, ticks_to_wait);
}

// Long software-rasterized LVGL paths run on the only CPU. Block for one tick
// at bounded intervals so the idle task can service its watchdog subscription.
static inline void passport_lvgl_cooperative_yield(void) {
    vTaskDelay(1);
}
#endif

#if __has_include("bsp_button.h")
#include "bsp_button.h"
#endif

#if __has_include("host/ble_gap.h")
#include "host/ble_gap.h"
#include "host/ble_hs.h"

// ESP-NimBLE 1.8 exports this iterator and its callback type, but omits the
// function declaration from ble_gap.h.
void ble_gap_conn_foreach_handle(
    ble_gap_conn_foreach_handle_fn *callback,
    void *context
);
#endif

// Keep the Swift import surface complete when host tests provide reduced BSP
// headers. These declarations match the public BSP signatures.
esp_err_t bsp_display_init(void);
void bsp_display_backlight(uint8_t percent);
struct _lv_display_t *bsp_lvgl_init(void);
bool bsp_lvgl_lock(int timeout_ms);
void bsp_lvgl_unlock(void);
esp_err_t bsp_i2c_init(void);
esp_err_t bsp_battery_init(void);
int bsp_battery_soc(void);
int bsp_battery_mv(void);

// LV_SIZE_CONTENT expands through a function-like macro Swift cannot import.
static inline void swift_lv_obj_set_content_size(lv_obj_t *object) {
    lv_obj_set_size(object, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
}

bool passport_ui_initialize_input(void);
bool passport_ui_poll_input(int32_t *button, int32_t *event);
void passport_ui_report_runtime(void);

static const int32_t swift_lv_coord_max = LV_COORD_MAX;

// Stable addresses of imported const font globals; Swift owns font selection.
static const lv_font_t * const swift_lv_font_montserrat_12 = &lv_font_montserrat_12;
static const lv_font_t * const swift_lv_font_montserrat_14 = &lv_font_montserrat_14;
static const lv_font_t * const swift_lv_font_montserrat_16 = &lv_font_montserrat_16;
static const lv_font_t * const swift_lv_font_montserrat_18 = &lv_font_montserrat_18;
static const lv_font_t * const swift_lv_font_montserrat_20 = &lv_font_montserrat_20;
static const lv_font_t * const swift_lv_font_montserrat_24 = &lv_font_montserrat_24;
static const lv_font_t * const swift_lv_font_montserrat_28 = &lv_font_montserrat_28;

/**
 * Receives one RGB565 screen snapshot.
 *
 * The pixel memory is read-only and valid only until the callback returns.
 * Copy or encode it synchronously when it must outlive the callback.
 */
typedef void (*passport_ui_screenshot_handler_t)(
    const uint8_t *pixels,
    size_t byte_count,
    uint32_t width,
    uint32_t height,
    uint32_t stride,
    void *context
);

/**
 * Captures the active LVGL screen in RGB565 format.
 *
 * The function acquires the LVGL lock, allocates one full-screen buffer from
 * the system heap, renders the snapshot, releases the lock, invokes `handler`,
 * and frees the buffer after the callback returns.
 */
bool passport_ui_take_screenshot(
    passport_ui_screenshot_handler_t handler,
    void *context
);

// RGB565 image bytes are linked directly into flash by CMake. LVGL's image
// header uses C bit-fields, so this narrow initializer keeps that ABI detail
// out of Swift while Swift retains descriptor ownership and asset selection.
extern const uint8_t passport_tibo_confirmed_start[]
    asm("_binary_tibo_reset_confirmed_rgb565_start");
extern const uint8_t passport_tibo_confirmed_end[]
    asm("_binary_tibo_reset_confirmed_rgb565_end");
extern const uint8_t passport_tibo_announced_start[]
    asm("_binary_tibo_reset_announced_rgb565_start");
extern const uint8_t passport_tibo_announced_end[]
    asm("_binary_tibo_reset_announced_rgb565_end");
extern const uint8_t passport_tibo_idle_start[]
    asm("_binary_tibo_reset_idle_rgb565_start");
extern const uint8_t passport_tibo_idle_end[]
    asm("_binary_tibo_reset_idle_rgb565_end");

static inline const uint8_t *passport_tibo_confirmed_data_start(void) {
    return passport_tibo_confirmed_start;
}

static inline const uint8_t *passport_tibo_confirmed_data_end(void) {
    return passport_tibo_confirmed_end;
}

static inline const uint8_t *passport_tibo_announced_data_start(void) {
    return passport_tibo_announced_start;
}

static inline const uint8_t *passport_tibo_announced_data_end(void) {
    return passport_tibo_announced_end;
}

static inline const uint8_t *passport_tibo_idle_data_start(void) {
    return passport_tibo_idle_start;
}

static inline const uint8_t *passport_tibo_idle_data_end(void) {
    return passport_tibo_idle_end;
}

static inline void passport_tibo_initialize_image_descriptor(
    lv_image_dsc_t *descriptor,
    const uint8_t *data,
    size_t data_size
) {
    memset(descriptor, 0, sizeof(*descriptor));
    descriptor->header.magic = LV_IMAGE_HEADER_MAGIC;
    descriptor->header.cf = LV_COLOR_FORMAT_RGB565;
    descriptor->header.w = 100;
    descriptor->header.h = 100;
    descriptor->header.stride = 200;
    descriptor->data_size = data_size;
    descriptor->data = data;
}
