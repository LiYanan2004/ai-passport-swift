idf_component_register(
    SRCS "src/bsp_i2c.c"
         "src/bsp_display.c"
         "src/bsp_display_lvgl.c"
         "src/bsp_usb_mirroring.c"
         "src/bsp_button.c"
         "src/bsp_audio.c"
         "src/bsp_battery.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES vfs
    REQUIRES driver esp_driver_i2c esp_driver_i2s esp_driver_usb_serial_jtag esp_lcd esp_lvgl_port esp_timer button esp_adc esp_codec_dev
)
