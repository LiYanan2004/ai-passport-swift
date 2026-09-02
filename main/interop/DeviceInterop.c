#include "swift_platform_bridge.h"

#include "bsp_button.h"

#include "bsp_audio.h"
#include "bsp_display.h"

#include "esp_attr.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "esp_wifi_default.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_gap.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "nvs_flash.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SWIFT_AUDIO_SAMPLE_RATE 16000
#define SWIFT_AUDIO_TONE_HZ 1000
#define SWIFT_AUDIO_CHUNK_SAMPLES 512
#define SWIFT_AUDIO_RECORD_SECONDS 3

extern void swift_main_button_event(int32_t button, int32_t event);

static void swift_platform_button_callback(bsp_btn_t button, bsp_btn_ev_t event, void *user)
{
    (void)user;
    swift_main_button_event((int32_t)button, (int32_t)event);
}

esp_err_t swift_platform_button_init(void)
{
    return bsp_button_init(swift_platform_button_callback, 0);
}

static bool s_nvs_ready;
static bool s_netif_ready;
static bool s_event_loop_ready;

static esp_err_t prepare_nvs(void)
{
    if (s_nvs_ready) return ESP_OK;
    esp_err_t error = nvs_flash_init();
    if (error == ESP_OK) s_nvs_ready = true;
    return error;
}

static esp_err_t prepare_network(void)
{
    if (!s_netif_ready) {
        esp_err_t error = esp_netif_init();
        if (error != ESP_OK) return error;
        s_netif_ready = true;
    }
    if (!s_event_loop_ready) {
        esp_err_t error = esp_event_loop_create_default();
        if (error != ESP_OK) return error;
        s_event_loop_ready = true;
    }
    return ESP_OK;
}

static TaskHandle_t s_audio_task;
static volatile uint32_t s_audio_request;
static volatile swift_audio_state_t s_audio_state;

static void play_tone(void)
{
    s_audio_state = SWIFT_AUDIO_PLAYING_TONE;
    if (bsp_audio_set_format(SWIFT_AUDIO_SAMPLE_RATE, 16, 1) != ESP_OK) goto failed;
    bsp_audio_set_volume(80);

    int16_t *samples = malloc(SWIFT_AUDIO_CHUNK_SAMPLES * sizeof(*samples));
    if (!samples) goto failed;
    int phase = 0;
    int remaining = SWIFT_AUDIO_SAMPLE_RATE;
    const int period = SWIFT_AUDIO_SAMPLE_RATE / SWIFT_AUDIO_TONE_HZ;
    while (remaining > 0) {
        const int count = remaining < SWIFT_AUDIO_CHUNK_SAMPLES ? remaining : SWIFT_AUDIO_CHUNK_SAMPLES;
        for (int index = 0; index < count; ++index) {
            samples[index] = phase < period / 2 ? 6000 : -6000;
            if (++phase >= period) phase = 0;
        }
        bsp_audio_write(samples, (size_t)count * sizeof(*samples));
        remaining -= count;
    }
    free(samples);
    s_audio_state = SWIFT_AUDIO_COMPLETE;
    return;
failed:
    s_audio_state = SWIFT_AUDIO_FAILED;
}

static void record_and_play(void)
{
    if (bsp_audio_set_format(SWIFT_AUDIO_SAMPLE_RATE, 16, 1) != ESP_OK) goto failed;
    const size_t total = SWIFT_AUDIO_SAMPLE_RATE * SWIFT_AUDIO_RECORD_SECONDS;
    int16_t *recording = malloc(total * sizeof(*recording));
    if (!recording) goto failed;

    s_audio_state = SWIFT_AUDIO_RECORDING;
    size_t received = 0;
    while (received < total) {
        const size_t count = (total - received) < SWIFT_AUDIO_CHUNK_SAMPLES
            ? (total - received) : SWIFT_AUDIO_CHUNK_SAMPLES;
        if (bsp_audio_read(recording + received, count * sizeof(*recording)) != ESP_OK) break;
        received += count;
    }
    s_audio_state = SWIFT_AUDIO_PLAYING_RECORDING;
    bsp_audio_set_volume(80);
    for (size_t offset = 0; offset < received; offset += SWIFT_AUDIO_CHUNK_SAMPLES) {
        const size_t count = (received - offset) < SWIFT_AUDIO_CHUNK_SAMPLES
            ? (received - offset) : SWIFT_AUDIO_CHUNK_SAMPLES;
        bsp_audio_write(recording + offset, count * sizeof(*recording));
    }
    free(recording);
    s_audio_state = SWIFT_AUDIO_COMPLETE;
    return;
failed:
    s_audio_state = SWIFT_AUDIO_FAILED;
}

static void audio_task(void *argument)
{
    (void)argument;
    for (;;) {
        const uint32_t request = s_audio_request;
        s_audio_request = 0;
        if (request == 1) play_tone();
        else if (request == 2) record_and_play();
        else vTaskDelay(pdMS_TO_TICKS(50));
    }
}

void swift_platform_audio_start(void)
{
    s_audio_request = 0;
    s_audio_state = SWIFT_AUDIO_IDLE;
    if (!s_audio_task && xTaskCreate(audio_task, "swift_audio", 4096, NULL, 4, &s_audio_task) != pdPASS) {
        s_audio_state = SWIFT_AUDIO_FAILED;
    }
}

void swift_platform_audio_stop(void)
{
    s_audio_request = 0;
    if (s_audio_task) {
        vTaskDelete(s_audio_task);
        s_audio_task = NULL;
    }
    s_audio_state = SWIFT_AUDIO_IDLE;
}

void swift_platform_audio_request_tone(void) { s_audio_request = 1; }
void swift_platform_audio_request_recording(void) { s_audio_request = 2; }
swift_audio_state_t swift_platform_audio_state(void) { return s_audio_state; }

#define SWIFT_WIFI_RESULT_COUNT 5
static esp_netif_t *s_wifi_station;
static esp_event_handler_instance_t s_wifi_scan_handler;
static volatile swift_wifi_state_t s_wifi_state;
static volatile esp_err_t s_wifi_error;
static bool s_wifi_initialized;
static bool s_wifi_started;
static bool s_wifi_handler_registered;
static char s_wifi_results[320];

static void wifi_scan_done(void *argument, esp_event_base_t base, int32_t identifier, void *data)
{
    (void)argument;
    (void)base;
    (void)identifier;
    (void)data;
    if (s_wifi_state == SWIFT_WIFI_SCANNING) s_wifi_state = SWIFT_WIFI_READY;
}

static void wifi_start_scan(void)
{
    if (!s_wifi_started) {
        s_wifi_error = ESP_ERR_INVALID_STATE;
        s_wifi_state = SWIFT_WIFI_FAILED;
        return;
    }
    const esp_err_t error = esp_wifi_scan_start(NULL, false);
    if (error == ESP_OK) s_wifi_state = SWIFT_WIFI_SCANNING;
    else {
        s_wifi_error = error;
        s_wifi_state = SWIFT_WIFI_FAILED;
    }
}

void swift_platform_wifi_start(void)
{
    s_wifi_state = SWIFT_WIFI_STARTING;
    s_wifi_error = ESP_OK;
    esp_err_t error = prepare_nvs();
    if (error != ESP_OK) goto failed;
    error = prepare_network();
    if (error != ESP_OK) goto failed;
    s_wifi_station = esp_netif_create_default_wifi_sta();
    if (!s_wifi_station) { error = ESP_ERR_NO_MEM; goto failed; }
    wifi_init_config_t configuration = WIFI_INIT_CONFIG_DEFAULT();
    error = esp_wifi_init(&configuration);
    if (error != ESP_OK) goto failed;
    s_wifi_initialized = true;
    error = esp_event_handler_instance_register(WIFI_EVENT, WIFI_EVENT_SCAN_DONE,
                                                wifi_scan_done, NULL, &s_wifi_scan_handler);
    if (error != ESP_OK) goto failed;
    s_wifi_handler_registered = true;
    error = esp_wifi_set_storage(WIFI_STORAGE_RAM);
    if (error != ESP_OK) goto failed;
    error = esp_wifi_set_mode(WIFI_MODE_STA);
    if (error != ESP_OK) goto failed;
    error = esp_wifi_start();
    if (error != ESP_OK) goto failed;
    s_wifi_started = true;
    wifi_start_scan();
    return;
failed:
    s_wifi_error = error;
    s_wifi_state = SWIFT_WIFI_FAILED;
}

void swift_platform_wifi_stop(void)
{
    if (s_wifi_started) {
        esp_wifi_scan_stop();
        esp_wifi_stop();
        s_wifi_started = false;
    }
    if (s_wifi_handler_registered) {
        esp_event_handler_instance_unregister(WIFI_EVENT, WIFI_EVENT_SCAN_DONE, s_wifi_scan_handler);
        s_wifi_handler_registered = false;
    }
    if (s_wifi_initialized) {
        esp_wifi_deinit();
        s_wifi_initialized = false;
    }
    if (s_wifi_station) {
        esp_netif_destroy_default_wifi(s_wifi_station);
        s_wifi_station = NULL;
    }
    s_wifi_state = SWIFT_WIFI_IDLE;
}

void swift_platform_wifi_rescan(void)
{
    if (s_wifi_state == SWIFT_WIFI_IDLE) wifi_start_scan();
}

swift_wifi_state_t swift_platform_wifi_state(void)
{
    if (s_wifi_state != SWIFT_WIFI_READY) return s_wifi_state;
    uint16_t total = 0;
    uint16_t count = SWIFT_WIFI_RESULT_COUNT;
    wifi_ap_record_t records[SWIFT_WIFI_RESULT_COUNT] = { 0 };
    esp_err_t error = esp_wifi_scan_get_ap_num(&total);
    if (error == ESP_OK) error = esp_wifi_scan_get_ap_records(&count, records);
    if (error != ESP_OK) {
        s_wifi_error = error;
        s_wifi_state = SWIFT_WIFI_FAILED;
        return s_wifi_state;
    }
    size_t used = 0;
    for (uint16_t index = 0; index < count && used < sizeof(s_wifi_results); ++index) {
        const int written = snprintf(s_wifi_results + used, sizeof(s_wifi_results) - used,
                                     "%d  %.18s  ch%u\n", records[index].rssi,
                                     (const char *)records[index].ssid, records[index].primary);
        if (written < 0 || (size_t)written >= sizeof(s_wifi_results) - used) break;
        used += (size_t)written;
    }
    if (count == 0) snprintf(s_wifi_results, sizeof(s_wifi_results), "No access points found");
    s_wifi_state = SWIFT_WIFI_IDLE;
    return s_wifi_state;
}

const char *swift_platform_wifi_results(void) { return s_wifi_results; }
const char *swift_platform_wifi_error(void) { return esp_err_to_name(s_wifi_error); }

static SemaphoreHandle_t s_ble_host_stopped;
static volatile swift_ble_state_t s_ble_state;
static volatile int s_ble_error;
static uint8_t s_ble_address_type;
static bool s_ble_initialized;
static bool s_ble_start_requested;

static int ble_gap_event(struct ble_gap_event *event, void *argument);

static int ble_advertise(void)
{
    static const char device_name[] = "FoloPassport";
    struct ble_hs_adv_fields fields = { 0 };
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (const uint8_t *)device_name;
    fields.name_len = strlen(device_name);
    fields.name_is_complete = 1;
    int result = ble_gap_adv_set_fields(&fields);
    if (result != 0) return result;
    struct ble_gap_adv_params parameters = { 0 };
    parameters.conn_mode = BLE_GAP_CONN_MODE_NON;
    parameters.disc_mode = BLE_GAP_DISC_MODE_GEN;
    result = ble_gap_adv_start(s_ble_address_type, NULL, BLE_HS_FOREVER, &parameters, ble_gap_event, NULL);
    if (result == 0) s_ble_state = SWIFT_BLE_ADVERTISING;
    return result;
}

static int ble_gap_event(struct ble_gap_event *event, void *argument)
{
    (void)argument;
    if (event->type == BLE_GAP_EVENT_ADV_COMPLETE && s_ble_start_requested) {
        const int result = ble_advertise();
        if (result != 0) { s_ble_error = result; s_ble_state = SWIFT_BLE_FAILED; }
    }
    return 0;
}

static void ble_on_reset(int reason) { s_ble_error = reason; s_ble_state = SWIFT_BLE_FAILED; }

static void ble_on_sync(void)
{
    int result = ble_hs_util_ensure_addr(0);
    if (result == 0) result = ble_hs_id_infer_auto(0, &s_ble_address_type);
    if (result == 0 && s_ble_start_requested) result = ble_advertise();
    if (result != 0) { s_ble_error = result; s_ble_state = SWIFT_BLE_FAILED; }
}

static void ble_host_task(void *argument)
{
    (void)argument;
    nimble_port_run();
    if (s_ble_host_stopped) xSemaphoreGive(s_ble_host_stopped);
    nimble_port_freertos_deinit();
}

void swift_platform_ble_start(void)
{
    if (s_ble_initialized) { s_ble_error = ESP_ERR_INVALID_STATE; s_ble_state = SWIFT_BLE_FAILED; return; }
    s_ble_state = SWIFT_BLE_STARTING;
    esp_err_t error = prepare_nvs();
    if (error != ESP_OK) goto failed;
    error = nimble_port_init();
    if (error != ESP_OK) goto failed;
    s_ble_initialized = true;
    s_ble_host_stopped = xSemaphoreCreateBinary();
    if (!s_ble_host_stopped) { error = ESP_ERR_NO_MEM; goto failed; }
    ble_svc_gap_init();
    ble_svc_gatt_init();
    if (ble_svc_gap_device_name_set("FoloPassport") != 0) { error = ESP_FAIL; goto failed; }
    ble_hs_cfg.reset_cb = ble_on_reset;
    ble_hs_cfg.sync_cb = ble_on_sync;
    s_ble_start_requested = true;
    nimble_port_freertos_init(ble_host_task);
    return;
failed:
    s_ble_error = error;
    s_ble_state = SWIFT_BLE_FAILED;
    if (s_ble_host_stopped) { vSemaphoreDelete(s_ble_host_stopped); s_ble_host_stopped = NULL; }
    if (s_ble_initialized) { nimble_port_deinit(); s_ble_initialized = false; }
}

void swift_platform_ble_stop(void)
{
    s_ble_start_requested = false;
    if (s_ble_initialized) {
        ble_gap_adv_stop();
        const int result = nimble_port_stop();
        if (result == 0 && s_ble_host_stopped) xSemaphoreTake(s_ble_host_stopped, portMAX_DELAY);
        if (result == 0) { nimble_port_deinit(); s_ble_initialized = false; }
    }
    if (!s_ble_initialized && s_ble_host_stopped) { vSemaphoreDelete(s_ble_host_stopped); s_ble_host_stopped = NULL; }
    s_ble_state = SWIFT_BLE_IDLE;
}

void swift_platform_ble_restart_advertising(void)
{
    if (!s_ble_initialized) return;
    ble_gap_adv_stop();
    const int result = ble_advertise();
    if (result != 0) { s_ble_error = result; s_ble_state = SWIFT_BLE_FAILED; }
}

swift_ble_state_t swift_platform_ble_state(void) { return s_ble_state; }
int swift_platform_ble_error(void) { return s_ble_error; }

#define SWIFT_POWER_DEEP_SLEEP_MAGIC 0x464F4C4FUL
static TaskHandle_t s_power_task;
static volatile swift_power_state_t s_power_state;
static volatile esp_err_t s_power_error;
static RTC_DATA_ATTR uint32_t s_power_deep_sleep_magic;
static RTC_DATA_ATTR uint32_t s_power_deep_sleep_count;
static char s_power_initial_status[96];

static void power_task(void *argument)
{
    (void)argument;
    for (;;) {
        uint32_t command = 0;
        xTaskNotifyWait(0, UINT32_MAX, &command, portMAX_DELAY);
        if (command == 2) {
            s_power_state = SWIFT_POWER_DEEP_PREPARING;
            vTaskDelay(pdMS_TO_TICKS(250));
            s_power_error = esp_sleep_enable_timer_wakeup(5ULL * 1000ULL * 1000ULL);
            if (s_power_error == ESP_OK) {
                if (s_power_deep_sleep_magic != SWIFT_POWER_DEEP_SLEEP_MAGIC) s_power_deep_sleep_count = 0;
                s_power_deep_sleep_magic = SWIFT_POWER_DEEP_SLEEP_MAGIC;
                ++s_power_deep_sleep_count;
                bsp_display_backlight(0);
                esp_deep_sleep_start();
            }
            s_power_state = SWIFT_POWER_FAILED;
        } else {
            s_power_state = SWIFT_POWER_LIGHT_PREPARING;
            vTaskDelay(pdMS_TO_TICKS(150));
            bsp_display_backlight(0);
            s_power_error = esp_sleep_enable_timer_wakeup(2ULL * 1000ULL * 1000ULL);
            if (s_power_error == ESP_OK) s_power_error = esp_light_sleep_start();
            esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER);
            bsp_display_backlight(100);
            s_power_state = s_power_error == ESP_OK ? SWIFT_POWER_LIGHT_WOKE : SWIFT_POWER_FAILED;
        }
    }
}

bool swift_platform_power_start(void)
{
    s_power_state = SWIFT_POWER_IDLE;
    s_power_error = ESP_OK;
    if (!s_power_task && xTaskCreate(power_task, "swift_power", 3072, NULL, 4, &s_power_task) != pdPASS) {
        s_power_error = ESP_ERR_NO_MEM;
        s_power_state = SWIFT_POWER_FAILED;
        return false;
    }
    return true;
}

void swift_platform_power_stop(void)
{
    if (s_power_task) { vTaskDelete(s_power_task); s_power_task = NULL; }
    bsp_display_backlight(100);
    esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_TIMER);
    s_power_state = SWIFT_POWER_IDLE;
}

void swift_platform_power_run_light_sleep(void)
{
    if (s_power_task && s_power_state != SWIFT_POWER_LIGHT_PREPARING && s_power_state != SWIFT_POWER_DEEP_PREPARING) {
        xTaskNotify(s_power_task, 1, eSetValueWithOverwrite);
    }
}

void swift_platform_power_run_deep_sleep(void)
{
    if (s_power_task && s_power_state != SWIFT_POWER_LIGHT_PREPARING && s_power_state != SWIFT_POWER_DEEP_PREPARING) {
        xTaskNotify(s_power_task, 2, eSetValueWithOverwrite);
    }
}

swift_power_state_t swift_platform_power_state(void) { return s_power_state; }
const char *swift_platform_power_error(void) { return esp_err_to_name(s_power_error); }
const char *swift_platform_power_initial_status(void)
{
    if (s_power_deep_sleep_magic == SWIFT_POWER_DEEP_SLEEP_MAGIC &&
        esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_TIMER) {
        snprintf(s_power_initial_status, sizeof(s_power_initial_status),
                 "DEEP TIMER WAKE  #%lu\nUP/DOWN: SELECT  OK: RUN",
                 (unsigned long)s_power_deep_sleep_count);
    } else {
        snprintf(s_power_initial_status, sizeof(s_power_initial_status),
                 "UP/DOWN: SELECT  OK: RUN\nRTC TIMER WAKE ONLY");
    }
    return s_power_initial_status;
}
