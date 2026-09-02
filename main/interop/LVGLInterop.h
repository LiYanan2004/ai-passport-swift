#pragma once

#include <stdint.h>

#include "lvgl.h"

const lv_font_t *swift_lvgl_font_montserrat_14(void);
const lv_font_t *swift_lvgl_font_montserrat_20(void);
void swift_lvgl_label_set_value(lv_obj_t *label, int value, const char *unit);
void swift_lvgl_mascot_start_blink(lv_obj_t *eye);
void swift_lvgl_mascot_jump(lv_obj_t *mascot);
