#include "bsp_usb_mirroring.h"
#include "bsp_display.h"
#include "bsp_pins.h"
#include "driver/usb_serial_jtag.h"
#include "driver/usb_serial_jtag_vfs.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "lvgl.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define MIRROR_HEADER_SIZE 16
#define MIRROR_CHECKSUM_SIZE 4
#define MIRROR_CAPTURE_WIDTH BSP_LCD_W
#define MIRROR_CAPTURE_HEIGHT BSP_LCD_H
#define MIRROR_CAPTURE_ROW_BYTES (MIRROR_CAPTURE_WIDTH * sizeof(uint16_t))
#define MIRROR_ROW_QUEUE_LENGTH 24
#define MIRROR_KEY_FRAME_STRIPE_HEIGHT 20
#define MIRROR_RAW_PAYLOAD_SIZE (MIRROR_CAPTURE_ROW_BYTES + sizeof(uint16_t))
#define MIRROR_MAX_PAYLOAD \
    (MIRROR_RAW_PAYLOAD_SIZE + (MIRROR_RAW_PAYLOAD_SIZE + 127) / 128)
#define MIRROR_PACKET_ROW 1
#define MIRROR_PACKET_FRAME_END 2
#define MIRROR_FLAG_PACK_BITS 1
#define MIRROR_FLAG_KEY_FRAME 1
#define MIRROR_TX_BATCH_SIZE 512
#define MIRROR_KEY_FRAME_INTERVAL_US 5000000
#define MIRROR_TASK_PRIORITY 4

static const char *TAG = "usb_mirror";

_Static_assert(MIRROR_ROW_QUEUE_LENGTH >= MIRROR_KEY_FRAME_STRIPE_HEIGHT + 1,
               "row queue must hold one stripe and its frame boundary");

// Wire v6 uses independently checked, variable-size packets so console output
// cannot permanently desynchronize the receiver. The bounded queue keeps one
// RGB565 row segment per entry. The receiver assembles the fixed
// 240x320 RGB565 stream directly into its RGBA presentation frame.
typedef struct {
    uint16_t sequence;
    uint16_t row;
    uint16_t column;
    uint16_t pixel_count;
    uint16_t frame_packet_count;
    uint8_t type;
    bool key_frame;
    uint8_t pixels[MIRROR_CAPTURE_ROW_BYTES];
} mirror_row_entry_t;

static lv_display_t *s_display;
static QueueHandle_t s_row_queue;
static SemaphoreHandle_t s_capture_mutex;
static uint16_t s_capture_sequence;
static bool s_capture_enabled;
static bool s_key_frame_retry_needed;
static bool s_key_frame_capture_active;
static bool s_key_frame_refresh_pending;
static uint16_t s_key_frame_next_row;
static uint16_t s_key_frame_stripe_first_row;
static uint16_t s_key_frame_stripe_last_row;
static uint32_t s_key_frame_stripe_row_mask;
static uint16_t s_key_frame_packet_count;
static uint16_t s_delta_target_flush_index;
static uint16_t s_delta_current_flush_index;
static uint16_t s_delta_stripe_phase;

typedef struct {
    uint8_t bytes[MIRROR_TX_BATCH_SIZE];
    size_t size;
} mirror_writer_t;

static void capture_flush(lv_event_t *event) {
    lv_display_t *display = lv_event_get_target(event);
    const lv_area_t *area = lv_event_get_param(event);
    const lv_draw_buf_t *buffer = lv_display_get_buf_active(display);
    if (!buffer || area->x1 < 0 || area->y1 < 0 ||
        area->x2 >= BSP_LCD_W || area->y2 >= BSP_LCD_H) return;

    // FLUSH_START precedes the port's RGB565 byte swap and SPI submission.
    xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
    if (!s_capture_enabled) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }

    uint16_t pixel_count = (uint16_t)lv_area_get_width(area);
    if (s_key_frame_capture_active) {
        // A continuously animated view can flush between requested key-frame
        // stripes. Only the full-width rows belonging to the current stripe
        // are part of the key frame; unrelated animation flushes are ignored.
        if (!s_key_frame_refresh_pending || area->x1 != 0 ||
            area->x2 != MIRROR_CAPTURE_WIDTH - 1) {
            xSemaphoreGive(s_capture_mutex);
            return;
        }
        int first_row = area->y1 > s_key_frame_stripe_first_row
            ? area->y1 : s_key_frame_stripe_first_row;
        int last_row = area->y2 < s_key_frame_stripe_last_row
            ? area->y2 : s_key_frame_stripe_last_row;
        if (first_row > last_row ||
            uxQueueSpacesAvailable(s_row_queue) < (UBaseType_t)(last_row - first_row + 1)) {
            xSemaphoreGive(s_capture_mutex);
            return;
        }
        for (int source_y = first_row; source_y <= last_row; ++source_y) {
            uint32_t row_bit = 1u << (source_y - s_key_frame_stripe_first_row);
            if ((s_key_frame_stripe_row_mask & row_bit) != 0) continue;
            mirror_row_entry_t entry = {
                .sequence = s_capture_sequence,
                .row = (uint16_t)source_y,
                .column = 0,
                .pixel_count = MIRROR_CAPTURE_WIDTH,
                .type = MIRROR_PACKET_ROW,
                .key_frame = true,
            };
            const uint8_t *source_row =
                buffer->data + (source_y - area->y1) * buffer->header.stride;
            memcpy(entry.pixels, source_row, MIRROR_CAPTURE_ROW_BYTES);
            if (xQueueSend(s_row_queue, &entry, 0) != pdTRUE) {
                s_key_frame_retry_needed = true;
                s_key_frame_capture_active = false;
                s_key_frame_refresh_pending = false;
                ++s_capture_sequence;
                xSemaphoreGive(s_capture_mutex);
                return;
            }
            s_key_frame_stripe_row_mask |= row_bit;
            ++s_key_frame_packet_count;
        }
        xSemaphoreGive(s_capture_mutex);
        return;
    }

    // Capture one rotating, independently validated stripe per LVGL refresh.
    // Narrow dirty areas can be taller than 20 rows even with a 20-row full-width
    // draw buffer, so both flushes and rows within a flush are rotated. This
    // bounds producer demand while eventually updating every animated region.
    uint16_t flush_index = s_delta_current_flush_index++;
    if (flush_index != s_delta_target_flush_index) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    uint16_t area_row_count = (uint16_t)lv_area_get_height(area);
    uint16_t stripe_count =
        (area_row_count + MIRROR_KEY_FRAME_STRIPE_HEIGHT - 1) /
        MIRROR_KEY_FRAME_STRIPE_HEIGHT;
    uint16_t stripe_index = s_delta_stripe_phase % stripe_count;
    int first_row = area->y1 + stripe_index * MIRROR_KEY_FRAME_STRIPE_HEIGHT;
    int last_row = first_row + MIRROR_KEY_FRAME_STRIPE_HEIGHT - 1;
    if (last_row > area->y2) last_row = area->y2;
    uint16_t row_count = (uint16_t)(last_row - first_row + 1);
    if (uxQueueSpacesAvailable(s_row_queue) < (UBaseType_t)(row_count + 1)) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    uint16_t sequence = s_capture_sequence++;
    bool frame_completed = true;
    for (int source_y = first_row; source_y <= last_row; ++source_y) {
        mirror_row_entry_t entry = {
            .sequence = sequence,
            .row = (uint16_t)source_y,
            .column = (uint16_t)area->x1,
            .pixel_count = pixel_count,
            .type = MIRROR_PACKET_ROW,
            .key_frame = false,
        };
        const uint8_t *source_row =
            buffer->data + (source_y - area->y1) * buffer->header.stride;
        memcpy(entry.pixels, source_row, pixel_count * sizeof(uint16_t));
        if (xQueueSend(s_row_queue, &entry, 0) != pdTRUE) {
            frame_completed = false;
            break;
        }
    }
    if (frame_completed) {
        mirror_row_entry_t frame_end = {
            .sequence = sequence,
            .frame_packet_count = row_count,
            .type = MIRROR_PACKET_FRAME_END,
            .key_frame = false,
        };
        frame_completed = xQueueSend(s_row_queue, &frame_end, 0) == pdTRUE;
    }
    if (!frame_completed) s_key_frame_retry_needed = true;
    xSemaphoreGive(s_capture_mutex);
}

static void capture_ready(lv_event_t *event) {
    (void)event;
    xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
    if (!s_key_frame_capture_active) {
        uint16_t flush_count = s_delta_current_flush_index;
        s_delta_current_flush_index = 0;
        if (flush_count > 0) {
            if (s_delta_target_flush_index + 1 < flush_count) {
                ++s_delta_target_flush_index;
            } else {
                s_delta_target_flush_index = 0;
                ++s_delta_stripe_phase;
            }
        }
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    if (!s_key_frame_refresh_pending) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    uint16_t stripe_row_count =
        s_key_frame_stripe_last_row - s_key_frame_stripe_first_row + 1;
    uint32_t expected_row_mask = (1u << stripe_row_count) - 1u;
    s_key_frame_refresh_pending = false;
    if (s_key_frame_stripe_row_mask != expected_row_mask) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    s_key_frame_next_row = s_key_frame_stripe_last_row + 1;
    if (s_key_frame_next_row < MIRROR_CAPTURE_HEIGHT) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    mirror_row_entry_t entry = {
        .sequence = s_capture_sequence,
        .frame_packet_count = s_key_frame_packet_count,
        .type = MIRROR_PACKET_FRAME_END,
        .key_frame = true,
    };
    if (xQueueSend(s_row_queue, &entry, 0) != pdTRUE) {
        s_key_frame_retry_needed = true;
    }
    ++s_capture_sequence;
    s_key_frame_capture_active = false;
    s_delta_target_flush_index = 0;
    s_delta_current_flush_index = 0;
    s_delta_stripe_phase = 0;
    xSemaphoreGive(s_capture_mutex);
}

static uint32_t packet_checksum(const uint8_t *bytes, size_t count) {
    uint32_t checksum = 2166136261u;
    for (size_t index = 0; index < count; ++index) {
        checksum = (checksum ^ bytes[index]) * 16777619u;
    }
    return checksum;
}

static bool flush_writer(mirror_writer_t *writer) {
    size_t sent = 0;
    while (sent < writer->size) {
        int written = usb_serial_jtag_write_bytes(
            writer->bytes + sent, writer->size - sent, pdMS_TO_TICKS(20));
        if (written <= 0) return false;
        sent += written;
    }
    writer->size = 0;
    return true;
}

static bool queue_packet(mirror_writer_t *writer, uint8_t type, uint8_t flags,
                         uint16_t sequence, uint16_t row_or_count,
                         const uint8_t *payload, uint16_t payload_size) {
    size_t packet_size = MIRROR_HEADER_SIZE + payload_size + MIRROR_CHECKSUM_SIZE;
    if (writer->size + packet_size > sizeof(writer->bytes) && !flush_writer(writer)) {
        return false;
    }

    uint8_t *packet = writer->bytes + writer->size;
    memcpy(packet, "PMIRROW6", 8);
    packet[8] = type;
    packet[9] = flags;
    packet[10] = sequence;
    packet[11] = sequence >> 8;
    packet[12] = row_or_count;
    packet[13] = row_or_count >> 8;
    packet[14] = payload_size;
    packet[15] = payload_size >> 8;
    if (payload_size > 0) memcpy(packet + MIRROR_HEADER_SIZE, payload, payload_size);

    size_t checked_size = MIRROR_HEADER_SIZE + payload_size;
    uint32_t checksum = packet_checksum(packet, checked_size);
    for (int index = 0; index < MIRROR_CHECKSUM_SIZE; ++index) {
        packet[checked_size + index] = checksum >> (8 * index);
    }
    writer->size += packet_size;
    return true;
}

static size_t encode_pack_bits(const uint8_t *source, size_t source_size,
                               uint8_t *destination) {
    size_t source_index = 0;
    size_t destination_index = 0;
    while (source_index < source_size) {
        size_t run_length = 1;
        while (source_index + run_length < source_size &&
               source[source_index + run_length] == source[source_index] &&
               run_length < 129) {
            ++run_length;
        }
        if (run_length >= 3) {
            destination[destination_index++] = 0x80 | (uint8_t)(run_length - 2);
            destination[destination_index++] = source[source_index];
            source_index += run_length;
            continue;
        }

        size_t literal_start = source_index;
        source_index += run_length;
        while (source_index < source_size && source_index - literal_start < 128) {
            run_length = 1;
            while (source_index + run_length < source_size &&
                   source[source_index + run_length] == source[source_index] &&
                   run_length < 3) {
                ++run_length;
            }
            if (run_length >= 3) break;
            if (source_index - literal_start + run_length > 128) break;
            source_index += run_length;
        }
        size_t literal_length = source_index - literal_start;
        destination[destination_index++] = (uint8_t)(literal_length - 1);
        memcpy(destination + destination_index, source + literal_start, literal_length);
        destination_index += literal_length;
    }
    return destination_index;
}

static bool begin_key_frame(void) {
    xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
    s_capture_enabled = true;
    if (s_key_frame_capture_active) {
        s_key_frame_retry_needed = true;
        xSemaphoreGive(s_capture_mutex);
        return false;
    }
    s_key_frame_capture_active = true;
    s_key_frame_refresh_pending = false;
    s_key_frame_next_row = 0;
    s_key_frame_packet_count = 0;
    s_key_frame_retry_needed = false;
    s_delta_target_flush_index = 0;
    s_delta_current_flush_index = 0;
    s_delta_stripe_phase = 0;
    xSemaphoreGive(s_capture_mutex);
    return true;
}

static void capture_next_key_frame_stripe(void) {
    uint16_t first_row;
    uint16_t last_row;
    xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
    if (!s_key_frame_capture_active || s_key_frame_refresh_pending ||
        s_key_frame_next_row >= MIRROR_CAPTURE_HEIGHT) {
        xSemaphoreGive(s_capture_mutex);
        return;
    }
    first_row = s_key_frame_next_row;
    last_row = first_row + MIRROR_KEY_FRAME_STRIPE_HEIGHT - 1;
    if (last_row >= MIRROR_CAPTURE_HEIGHT) last_row = MIRROR_CAPTURE_HEIGHT - 1;
    s_key_frame_stripe_first_row = first_row;
    s_key_frame_stripe_last_row = last_row;
    s_key_frame_stripe_row_mask = 0;
    s_key_frame_refresh_pending = true;
    xSemaphoreGive(s_capture_mutex);

    if (bsp_lvgl_lock(100)) {
        lv_obj_t *screen = lv_display_get_screen_active(s_display);
        if (screen) {
            lv_area_t stripe = {
                .x1 = 0,
                .y1 = first_row,
                .x2 = MIRROR_CAPTURE_WIDTH - 1,
                .y2 = last_row,
            };
            lv_obj_invalidate_area(screen, &stripe);
        }
        bsp_lvgl_unlock();
    } else {
        xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
        s_key_frame_capture_active = false;
        s_key_frame_refresh_pending = false;
        s_key_frame_retry_needed = true;
        ++s_capture_sequence;
        xSemaphoreGive(s_capture_mutex);
    }
}

static void transmit_rows(void *context) {
    (void)context;
    TickType_t last_request = 0;
    bool requested = false;
    int64_t last_key_frame_time = 0;
    for (;;) {
        uint8_t request[32];
        int count = usb_serial_jtag_read_bytes(request, sizeof(request), 0);
        for (int index = 0; index < count; ++index) {
            if (request[index] == 'M') {
                if (!requested) {
                    begin_key_frame();
                }
                last_request = xTaskGetTickCount();
                requested = true;
            }
        }
        if (!requested || xTaskGetTickCount() - last_request > pdMS_TO_TICKS(2000)) {
            if (requested) {
                xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
                s_capture_enabled = false;
                s_key_frame_capture_active = false;
                s_key_frame_refresh_pending = false;
                xQueueReset(s_row_queue);
                xSemaphoreGive(s_capture_mutex);
            }
            requested = false;
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        int64_t now = esp_timer_get_time();
        bool retry_key_frame;
        bool key_frame_capture_active;
        bool key_frame_refresh_pending;
        xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
        retry_key_frame = s_key_frame_retry_needed;
        key_frame_capture_active = s_key_frame_capture_active;
        key_frame_refresh_pending = s_key_frame_refresh_pending;
        xSemaphoreGive(s_capture_mutex);
        UBaseType_t queued_entry_count = uxQueueMessagesWaiting(s_row_queue);
        if (!key_frame_capture_active && queued_entry_count == 0 &&
            (retry_key_frame ||
             now - last_key_frame_time >= MIRROR_KEY_FRAME_INTERVAL_US)) {
            key_frame_capture_active = begin_key_frame();
            key_frame_refresh_pending = false;
        }
        if (key_frame_capture_active && !key_frame_refresh_pending &&
            queued_entry_count == 0) {
            capture_next_key_frame_stripe();
        }

        mirror_row_entry_t entry;
        if (xQueueReceive(s_row_queue, &entry, pdMS_TO_TICKS(10)) != pdTRUE) continue;

        mirror_writer_t writer = { .size = 0 };
        bool completed;
        if (entry.type == MIRROR_PACKET_ROW) {
            uint8_t raw[MIRROR_RAW_PAYLOAD_SIZE];
            raw[0] = (uint8_t)entry.column;
            raw[1] = (uint8_t)(entry.column >> 8);
            uint16_t pixel_byte_count = entry.pixel_count * sizeof(uint16_t);
            memcpy(raw + 2, entry.pixels, pixel_byte_count);
            uint16_t raw_size = pixel_byte_count + 2;
            uint8_t compressed[MIRROR_MAX_PAYLOAD];
            size_t compressed_size = encode_pack_bits(raw, raw_size, compressed);
            bool use_compression = compressed_size < raw_size;
            completed = queue_packet(
                &writer, MIRROR_PACKET_ROW,
                use_compression ? MIRROR_FLAG_PACK_BITS : 0,
                entry.sequence, entry.row,
                use_compression ? compressed : raw,
                use_compression ? (uint16_t)compressed_size : raw_size
            ) && flush_writer(&writer);
        } else {
            completed = queue_packet(
                &writer, MIRROR_PACKET_FRAME_END,
                entry.key_frame ? MIRROR_FLAG_KEY_FRAME : 0,
                entry.sequence, entry.frame_packet_count, NULL, 0
            ) && flush_writer(&writer);
            if (completed && entry.key_frame) last_key_frame_time = now;
        }
        if (!completed) {
            xSemaphoreTake(s_capture_mutex, portMAX_DELAY);
            s_key_frame_retry_needed = true;
            xSemaphoreGive(s_capture_mutex);
        }
    }
}

esp_err_t bsp_usb_mirroring_init(lv_display_t *display) {
    if (s_row_queue) return ESP_OK;
    if (!display || lv_display_get_color_format(display) != LV_COLOR_FORMAT_RGB565 ||
        lv_display_get_horizontal_resolution(display) != BSP_LCD_W ||
        lv_display_get_vertical_resolution(display) != BSP_LCD_H) return ESP_ERR_NOT_SUPPORTED;
    s_display = display;
    s_row_queue = xQueueCreate(MIRROR_ROW_QUEUE_LENGTH, sizeof(mirror_row_entry_t));
    s_capture_mutex = xSemaphoreCreateMutex();
    if (!s_row_queue || !s_capture_mutex) goto allocation_failed;
    usb_serial_jtag_driver_config_t configuration = {
        .tx_buffer_size = 1024, .rx_buffer_size = 256,
    };
    esp_err_t result = usb_serial_jtag_driver_install(&configuration);
    if (result != ESP_OK) {
        vSemaphoreDelete(s_capture_mutex);
        s_capture_mutex = NULL;
        vQueueDelete(s_row_queue);
        s_row_queue = NULL;
        return result;
    }
    uint32_t event_count = lv_display_get_event_count(display);
    lv_display_add_event_cb(display, capture_flush, LV_EVENT_FLUSH_START, NULL);
    lv_display_add_event_cb(display, capture_ready, LV_EVENT_REFR_READY, NULL);
    if (lv_display_get_event_count(display) != event_count + 2) {
        lv_display_remove_event_cb_with_user_data(display, capture_flush, NULL);
        lv_display_remove_event_cb_with_user_data(display, capture_ready, NULL);
        usb_serial_jtag_driver_uninstall();
        goto allocation_failed;
    }
    // Match the LVGL port's priority so active animations cannot starve frame
    // transmission. USB writes block naturally and yield CPU time back to LVGL.
    if (xTaskCreate(transmit_rows, "usb_mirroring", 5120, NULL,
                    MIRROR_TASK_PRIORITY, NULL) != pdPASS) {
        lv_display_remove_event_cb_with_user_data(display, capture_flush, NULL);
        lv_display_remove_event_cb_with_user_data(display, capture_ready, NULL);
        usb_serial_jtag_driver_uninstall();
        goto allocation_failed;
    }
    // Console and mirror packets must share the driver's serialized TX queue.
    usb_serial_jtag_vfs_use_driver();
    ESP_LOGI(TAG, "ready: RGB565 %ux%u row queue=%u bytes",
             (unsigned)MIRROR_CAPTURE_WIDTH, (unsigned)MIRROR_CAPTURE_HEIGHT,
             (unsigned)(MIRROR_ROW_QUEUE_LENGTH * sizeof(mirror_row_entry_t)));
    return ESP_OK;

allocation_failed:
    if (s_capture_mutex) vSemaphoreDelete(s_capture_mutex);
    s_capture_mutex = NULL;
    if (s_row_queue) vQueueDelete(s_row_queue);
    s_row_queue = NULL;
    s_display = NULL;
    return ESP_ERR_NO_MEM;
}
