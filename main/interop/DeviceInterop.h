#pragma once

#include "esp_err.h"

#include <stdbool.h>
#include <stdint.h>

// Registers the C ABI callback exported by Main.swift with the BSP button driver.
esp_err_t swift_platform_button_init(void);

typedef enum {
    SWIFT_AUDIO_IDLE = 0,
    SWIFT_AUDIO_PLAYING_TONE,
    SWIFT_AUDIO_RECORDING,
    SWIFT_AUDIO_PLAYING_RECORDING,
    SWIFT_AUDIO_COMPLETE,
    SWIFT_AUDIO_FAILED,
} swift_audio_state_t;

void swift_platform_audio_start(void);
void swift_platform_audio_stop(void);
void swift_platform_audio_request_tone(void);
void swift_platform_audio_request_recording(void);
swift_audio_state_t swift_platform_audio_state(void);

typedef enum {
    SWIFT_WIFI_IDLE = 0,
    SWIFT_WIFI_STARTING,
    SWIFT_WIFI_SCANNING,
    SWIFT_WIFI_READY,
    SWIFT_WIFI_FAILED,
} swift_wifi_state_t;

void swift_platform_wifi_start(void);
void swift_platform_wifi_stop(void);
void swift_platform_wifi_rescan(void);
swift_wifi_state_t swift_platform_wifi_state(void);
const char *swift_platform_wifi_results(void);
const char *swift_platform_wifi_error(void);

typedef enum {
    SWIFT_BLE_IDLE = 0,
    SWIFT_BLE_STARTING,
    SWIFT_BLE_ADVERTISING,
    SWIFT_BLE_FAILED,
} swift_ble_state_t;

void swift_platform_ble_start(void);
void swift_platform_ble_stop(void);
void swift_platform_ble_restart_advertising(void);
swift_ble_state_t swift_platform_ble_state(void);
int swift_platform_ble_error(void);

typedef enum {
    SWIFT_POWER_IDLE = 0,
    SWIFT_POWER_LIGHT_PREPARING,
    SWIFT_POWER_LIGHT_WOKE,
    SWIFT_POWER_DEEP_PREPARING,
    SWIFT_POWER_FAILED,
} swift_power_state_t;

bool swift_platform_power_start(void);
void swift_platform_power_stop(void);
void swift_platform_power_run_light_sleep(void);
void swift_platform_power_run_deep_sleep(void);
swift_power_state_t swift_platform_power_state(void);
const char *swift_platform_power_error(void);
const char *swift_platform_power_initial_status(void);
