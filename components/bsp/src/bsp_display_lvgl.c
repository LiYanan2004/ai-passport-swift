// components/bsp/src/bsp_display_lvgl.c
// LVGL 接入单独成文件:不用 LVGL 的开发者删掉本文件 + idf_component.yml 里的两条依赖即可。
#include "bsp_display.h"
#include "bsp_pins.h"
#include "esp_lvgl_port.h"
#include "esp_log.h"
#include "bsp_usb_mirroring.h"

static const char *TAG = "bsp_lvgl";

static lv_display_t *s_disp;

lv_display_t *bsp_lvgl_init(void) {
    if (s_disp) return s_disp;
    if (!bsp_display_panel()) {
        ESP_LOGE(TAG, "请先成功调用 bsp_display_init()");
        return NULL;
    }

    lvgl_port_cfg_t pc = ESP_LVGL_PORT_INIT_CONFIG();
    // Nested SwiftUI layout wrappers increase LVGL's recursive draw depth.
    // The port's 7 KiB default overflows while drawing the initial List.
    pc.task_stack = CONFIG_BSP_LVGL_TASK_STACK_SIZE;
    if (lvgl_port_init(&pc) != ESP_OK) {
        ESP_LOGE(TAG, "lvgl_port_init 失败");
        return NULL;
    }

    const lvgl_port_display_cfg_t dc = {
        .panel_handle = bsp_display_panel(),
        .io_handle    = bsp_display_io(),
        // ⚠ C3 无 PSRAM,DMA 只能用内部 RAM(总共约 150KB)。
        // 20 行单缓冲 ≈ 9.6KB;若改成 40 行双缓冲(≈37.5KB)会把 I2S 等外设的
        // DMA 描述符挤到 NO_MEM。刷新略慢但稳。
        .buffer_size   = (uint32_t)BSP_LCD_W * 20,
        .double_buffer = false,
        .hres = BSP_LCD_W, .vres = BSP_LCD_H,
        // 旋转/镜像必须在这里配:esp_lvgl_port 注册显示时会重新下发 MADCTL,
        // 覆盖 bsp_display.c 里 esp_lcd_panel_mirror() 的设置。
        .rotation = { .swap_xy = false, .mirror_x = false, .mirror_y = false },
        // swap_bytes:LVGL 输出小端 RGB565,ST7789 走 SPI 要大端 → 需交换高低字节。
        .flags = { .buff_dma = true, .swap_bytes = true },
    };
    s_disp = lvgl_port_add_disp(&dc);
    if (!s_disp) { ESP_LOGE(TAG, "lvgl_port_add_disp 失败"); return NULL; }

#if CONFIG_BSP_USB_MIRRORING_ENABLED
    if (bsp_lvgl_lock(0)) {
        esp_err_t mirror_result = bsp_usb_mirroring_init(s_disp);
        bsp_lvgl_unlock();
        if (mirror_result != ESP_OK) {
            ESP_LOGW(TAG, "USB mirroring unavailable: %s", esp_err_to_name(mirror_result));
        }
    }
#endif

    ESP_LOGI(TAG, "LVGL 就绪");
    return s_disp;
}

bool bsp_lvgl_lock(int timeout_ms) { return lvgl_port_lock(timeout_ms); }
void bsp_lvgl_unlock(void)         { lvgl_port_unlock(); }
