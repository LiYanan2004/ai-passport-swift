#pragma once

#include "lvgl.h"

void passport_lvgl_label_set_value(lv_obj_t *label, int value, const char *unit);
void passport_lvgl_mascot_start_blink(lv_obj_t *eye);
void passport_lvgl_mascot_jump(lv_obj_t *mascot);
