#include <stdbool.h>
#include <stdint.h>

#include "lvgl.h"
#include "src/core/lv_obj_draw_private.h"

static bool lock_available = true;
static int32_t lock_depth;

bool bsp_lvgl_lock(int timeout_ms) {
    (void)timeout_ms;
    if (!lock_available) return false;
    ++lock_depth;
    return true;
}

void bsp_lvgl_unlock(void) { --lock_depth; }
int32_t test_lvgl_lock_depth(void) { return lock_depth; }
void test_lvgl_set_lock_available(bool available) { lock_available = available; }
int32_t test_lv_obj_get_ext_draw_size(const lv_obj_t *object) {
    return lv_obj_get_ext_draw_size(object);
}
void bsp_display_backlight(uint8_t percent) { (void)percent; }

// The generic App runtime is linked with the Swift screenshot entry point.
int32_t bsp_i2c_init(void) { return 0; }
int32_t bsp_display_init(void) { return 0; }
lv_display_t *bsp_lvgl_init(void) { return lv_display_get_default(); }
bool passport_ui_initialize_input(void) { return true; }
void passport_ui_report_runtime(void) {}

bool passport_ui_poll_input(int32_t *button, int32_t *event) {
    (void)button;
    (void)event;
    return false;
}
