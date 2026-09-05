#pragma once

#include <stdbool.h>
#include <stdint.h>

struct _lv_obj_t;

bool bsp_lvgl_lock(int timeout_ms);
void bsp_lvgl_unlock(void);

int32_t test_lvgl_lock_depth(void);
void test_lvgl_set_lock_available(bool available);
int32_t test_lv_obj_get_ext_draw_size(const struct _lv_obj_t *object);
