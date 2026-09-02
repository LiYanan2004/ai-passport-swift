#include "LVGLInterop.h"

void passport_lvgl_label_set_value(lv_obj_t *label, int value, const char *unit)
{
    lv_label_set_text_fmt(label, value < 0 ? "-- %s" : "%d %s", value, unit);
}

static void set_object_y(void *object, int32_t value)
{
    lv_obj_set_y(object, value);
}

static void set_object_opacity(void *object, int32_t value)
{
    lv_obj_set_style_opa(object, (lv_opa_t)value, 0);
}

void passport_lvgl_mascot_start_blink(lv_obj_t *eye)
{
    lv_anim_t animation;
    lv_anim_init(&animation);
    lv_anim_set_var(&animation, eye);
    lv_anim_set_exec_cb(&animation, set_object_opacity);
    lv_anim_set_values(&animation, LV_OPA_COVER, LV_OPA_20);
    lv_anim_set_duration(&animation, 70);
    lv_anim_set_playback_duration(&animation, 70);
    lv_anim_set_repeat_delay(&animation, 1700);
    lv_anim_set_repeat_count(&animation, LV_ANIM_REPEAT_INFINITE);
    lv_anim_set_path_cb(&animation, lv_anim_path_step);
    lv_anim_start(&animation);
}

void passport_lvgl_mascot_jump(lv_obj_t *mascot)
{
    int y = lv_obj_get_y(mascot);
    lv_anim_delete(mascot, set_object_y);

    lv_anim_t animation;
    lv_anim_init(&animation);
    lv_anim_set_var(&animation, mascot);
    lv_anim_set_exec_cb(&animation, set_object_y);
    lv_anim_set_values(&animation, y, y - 5);
    lv_anim_set_duration(&animation, 110);
    lv_anim_set_playback_duration(&animation, 140);
    lv_anim_set_path_cb(&animation, lv_anim_path_step);
    lv_anim_start(&animation);
}
