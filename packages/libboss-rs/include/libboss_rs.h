#ifndef LIBBOSS_RS_H
#define LIBBOSS_RS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LIBBOSS_RS_BLE_SERVICE_UUID "0000FEBE-0000-1000-8000-00805F9B34FB"
#define LIBBOSS_RS_BLE_SECURE_CHARACTERISTIC_UUID "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8"
#define LIBBOSS_RS_BLE_UNSECURE_CHARACTERISTIC_UUID "D417C028-9818-4354-99D1-2AC09D074591"
#define LIBBOSS_RS_SPP_UUID "00001101-0000-1000-8000-00805F9B34FB"

typedef struct BossBuffer {
    uint8_t *data;
    size_t len;
} BossBuffer;

typedef struct BossBufferList {
    BossBuffer *data;
    size_t len;
} BossBufferList;

typedef enum BossFfiLinkStatus {
    BOSS_FFI_LINK_STATUS_OK = 0,
    BOSS_FFI_LINK_STATUS_TIMED_OUT = 1,
    BOSS_FFI_LINK_STATUS_STREAM_ENDED = 2,
    BOSS_FFI_LINK_STATUS_UNEXPECTED_STREAM_TERMINATION = 3,
    BOSS_FFI_LINK_STATUS_OTHER = 4,
} BossFfiLinkStatus;

typedef enum BossFfiErrorCode {
    BOSS_FFI_ERROR_NONE = 0,
    BOSS_FFI_ERROR_INVALID_ARGUMENT = 1,
    BOSS_FFI_ERROR_RESPONSE_STREAM_ENDED = 2,
    BOSS_FFI_ERROR_RESPONSE_TIMED_OUT = 3,
    BOSS_FFI_ERROR_BMAP_ERROR_RESPONSE = 4,
    BOSS_FFI_ERROR_UNEXPECTED_OPERATOR = 5,
    BOSS_FFI_ERROR_MODE_CHANGE_NOT_OBSERVED = 6,
    BOSS_FFI_ERROR_EQUALIZER_NOT_OBSERVED = 7,
    BOSS_FFI_ERROR_SETTINGS_CONFIG_NOT_OBSERVED = 8,
    BOSS_FFI_ERROR_PRODUCT_INFO = 9,
    BOSS_FFI_ERROR_SETTINGS_CODEC = 10,
    BOSS_FFI_ERROR_AUDIO_MODES_CODEC = 11,
    BOSS_FFI_ERROR_UNSUPPORTED_OPERATION = 12,
    BOSS_FFI_ERROR_NO_FREE_CUSTOM_AUDIO_MODE_SLOT = 13,
    BOSS_FFI_ERROR_CUSTOM_AUDIO_MODE_SLOT_NOT_EDITABLE = 14,
    BOSS_FFI_ERROR_CUSTOM_AUDIO_MODE_SLOT_NOT_FOUND = 15,
} BossFfiErrorCode;

typedef enum BossFfiWriteDisposition {
    BOSS_FFI_WRITE_DISPOSITION_UNCHANGED = 0,
    BOSS_FFI_WRITE_DISPOSITION_UPDATED = 1,
    BOSS_FFI_WRITE_DISPOSITION_VERIFICATION_INCONCLUSIVE = 2,
} BossFfiWriteDisposition;

typedef enum BossFfiUpdateStreamKind {
    BOSS_FFI_UPDATE_STREAM_KIND_CURRENT_AUDIO_MODE = 0,
    BOSS_FFI_UPDATE_STREAM_KIND_AUDIO_MODE_SETTINGS = 1,
    BOSS_FFI_UPDATE_STREAM_KIND_EQUALIZER = 2,
    BOSS_FFI_UPDATE_STREAM_KIND_DEVICE_SETTINGS = 3,
    BOSS_FFI_UPDATE_STREAM_KIND_AUDIO_MODE_CATALOG = 4,
} BossFfiUpdateStreamKind;

typedef struct BossFfiSessionCallbacks {
    void *context;
    uint8_t transport_kind;
    BossFfiLinkStatus (*send_packet_bytes)(void *context, const uint8_t *packet_data, size_t packet_len);
    BossFfiLinkStatus (*next_packet_bytes)(void *context, uint64_t timeout_millis, BossBuffer *out_packet);
    void (*release_context)(void *context);
} BossFfiSessionCallbacks;

typedef struct BossFfiAudioModesCapabilities {
    int32_t bose_modes;
    int32_t user_modes;
} BossFfiAudioModesCapabilities;

typedef struct BossFfiAudioModeSettingsConfig {
    int32_t cnc_level;
    bool auto_cnc_enabled;
    uint8_t spatial_audio_mode;
    bool wind_block_enabled;
    bool anc_toggle_enabled;
} BossFfiAudioModeSettingsConfig;

typedef struct BossFfiAudioModeSettingsConfigPatch {
    bool has_cnc_level;
    int32_t cnc_level;
    bool has_auto_cnc_enabled;
    bool auto_cnc_enabled;
    bool has_spatial_audio_mode;
    uint8_t spatial_audio_mode;
    bool has_wind_block_enabled;
    bool wind_block_enabled;
    bool has_anc_toggle_enabled;
    bool anc_toggle_enabled;
} BossFfiAudioModeSettingsConfigPatch;

typedef struct BossFfiEqualizerPatch {
    bool has_bass;
    int32_t bass;
    bool has_mid;
    int32_t mid;
    bool has_treble;
    int32_t treble;
} BossFfiEqualizerPatch;

typedef struct BossFfiEqualizerRange {
    bool available;
    int32_t current_level;
    int32_t min_level;
    int32_t max_level;
} BossFfiEqualizerRange;

typedef struct BossFfiEqualizerSettings {
    BossFfiEqualizerRange bass;
    BossFfiEqualizerRange mid;
    BossFfiEqualizerRange treble;
} BossFfiEqualizerSettings;

typedef struct BossFfiCurrentAudioModeWriteResult {
    BossFfiWriteDisposition disposition;
    int32_t mode_index;
    int32_t target_index;
} BossFfiCurrentAudioModeWriteResult;

typedef struct BossFfiAudioModeSettingsWriteResult {
    BossFfiWriteDisposition disposition;
    BossFfiAudioModeSettingsConfig config;
} BossFfiAudioModeSettingsWriteResult;

typedef struct BossFfiAudioModeConfig {
    int32_t mode_index;
    uint8_t prompt_byte1;
    uint8_t prompt_byte2;
    size_t name_len;
    uint8_t name_bytes[32];
    bool favorite;
    bool user_configurable;
    bool user_configured;
    BossFfiAudioModeSettingsConfig settings;
} BossFfiAudioModeConfig;

typedef struct BossFfiAudioModePrompt {
    uint8_t byte1;
    uint8_t byte2;
    size_t name_len;
    uint8_t name_bytes[32];
} BossFfiAudioModePrompt;

typedef struct BossFfiEqualizerWriteResult {
    BossFfiWriteDisposition disposition;
    BossFfiEqualizerSettings settings;
} BossFfiEqualizerWriteResult;

typedef struct BossFfiOnHeadDetectionValue {
    bool is_enabled;
    bool has_auto_play_enabled;
    bool auto_play_enabled;
    bool has_auto_answer_enabled;
    bool auto_answer_enabled;
    bool has_auto_transparency_enabled;
    bool auto_transparency_enabled;
} BossFfiOnHeadDetectionValue;

typedef struct BossFfiVolumeControlStatus {
    uint8_t value;
    bool has_supported_values_mask;
    uint8_t supported_values_mask;
} BossFfiVolumeControlStatus;

typedef struct BossFfiStandbyTimerValue {
    int32_t minutes;
    bool supports_two_byte_minutes;
} BossFfiStandbyTimerValue;

typedef struct BossFfiObservedBool {
    bool has_value;
    bool value;
    bool has_source;
    uint8_t source;
    bool has_unavailable_reason;
    uint8_t unavailable_reason;
} BossFfiObservedBool;

typedef struct BossFfiObservedOnHeadDetection {
    bool has_value;
    BossFfiOnHeadDetectionValue value;
    bool has_source;
    uint8_t source;
    bool has_unavailable_reason;
    uint8_t unavailable_reason;
} BossFfiObservedOnHeadDetection;

typedef struct BossFfiObservedVolumeControlStatus {
    bool has_value;
    BossFfiVolumeControlStatus value;
    bool has_source;
    uint8_t source;
    bool has_unavailable_reason;
    uint8_t unavailable_reason;
} BossFfiObservedVolumeControlStatus;

typedef struct BossFfiDeviceSettingsReport {
    BossFfiObservedOnHeadDetection wear_detection;
    BossFfiObservedBool auto_aware_enabled;
    BossFfiObservedBool auto_play_pause_enabled;
    BossFfiObservedBool auto_answer_enabled;
    BossFfiObservedVolumeControlStatus volume_control;
} BossFfiDeviceSettingsReport;

typedef struct BossFfiFirmwareVersionInfo {
    int32_t port;
    size_t version_len;
    uint8_t version_bytes[64];
} BossFfiFirmwareVersionInfo;

typedef struct BossFfiBootstrappedDevice {
    size_t bmap_version_len;
    uint8_t bmap_version_bytes[64];
    uint16_t product_id;
    uint8_t variant;
    size_t product_name_len;
    uint8_t product_name_bytes[64];
    size_t function_blocks_len;
    uint8_t function_blocks_bytes[32];
    uint8_t transport_kind;
    int32_t default_device_id;
    int32_t default_port;
} BossFfiBootstrappedDevice;

typedef struct BossFfiError {
    BossFfiErrorCode code;
    BossBuffer message;
    bool has_bmap_error_code;
    uint8_t bmap_error_code;
} BossFfiError;

typedef struct BossFfiSessionHandle BossFfiSessionHandle;
typedef struct BossFfiUpdateStreamHandle BossFfiUpdateStreamHandle;
typedef struct BossFfiBleReassemblerHandle BossFfiBleReassemblerHandle;

const char *boss_ble_service_uuid(void);
const char *boss_ble_secure_characteristic_uuid(void);
const char *boss_ble_unsecure_characteristic_uuid(void);
const char *boss_spp_uuid(void);

void boss_buffer_free(BossBuffer buffer);
void boss_buffer_list_free(BossBufferList list);
void boss_error_free(BossFfiError error);
bool boss_bmap_decode_frame_size(const uint8_t *frame_data, size_t frame_len, size_t *out_payload_len);
BossBuffer boss_copy_bytes(const uint8_t *data, size_t len);
BossFfiBleReassemblerHandle *boss_ble_reassembler_create(void);
void boss_ble_reassembler_free(BossFfiBleReassemblerHandle *handle);
bool boss_ble_segment_packet(
    const uint8_t *packet_data,
    size_t packet_len,
    size_t mtu,
    BossBufferList *out_frames,
    BossFfiError *out_error
);
bool boss_ble_reassembler_push(
    BossFfiBleReassemblerHandle *handle,
    const uint8_t *segment_data,
    size_t segment_len,
    BossBuffer *out_packet,
    bool *out_has_packet,
    BossFfiError *out_error
);

BossFfiSessionHandle *boss_session_create(BossFfiSessionCallbacks callbacks, BossFfiError *out_error);
void boss_session_free(BossFfiSessionHandle *handle);
BossFfiUpdateStreamHandle *boss_update_stream_create(
    BossFfiSessionCallbacks callbacks,
    BossFfiUpdateStreamKind kind,
    BossFfiError *out_error
);
void boss_update_stream_free(BossFfiUpdateStreamHandle *handle);

bool boss_update_stream_next_current_audio_mode(
    BossFfiUpdateStreamHandle *handle,
    uint64_t timeout_millis,
    int32_t *out_mode_index,
    BossFfiError *out_error
);

bool boss_update_stream_next_audio_mode_settings(
    BossFfiUpdateStreamHandle *handle,
    uint64_t timeout_millis,
    BossFfiAudioModeSettingsConfig *out_config,
    BossFfiError *out_error
);

bool boss_update_stream_next_equalizer(
    BossFfiUpdateStreamHandle *handle,
    uint64_t timeout_millis,
    BossFfiEqualizerSettings *out_settings,
    BossFfiError *out_error
);

bool boss_update_stream_next_device_settings(
    BossFfiUpdateStreamHandle *handle,
    uint64_t timeout_millis,
    BossFfiDeviceSettingsReport *out_report,
    BossFfiError *out_error
);

bool boss_update_stream_next_audio_mode_catalog(
    BossFfiUpdateStreamHandle *handle,
    uint64_t timeout_millis,
    BossBuffer *out_catalog,
    BossFfiError *out_error
);

bool boss_bootstrap_session(
    BossFfiSessionCallbacks callbacks,
    BossFfiBootstrappedDevice *out_device,
    BossFfiError *out_error
);

bool boss_session_set_current_audio_mode(
    BossFfiSessionHandle *handle,
    int32_t target_index,
    bool play_voice_prompt,
    BossFfiCurrentAudioModeWriteResult *out_result,
    BossFfiError *out_error
);

bool boss_session_set_audio_mode_settings(
    BossFfiSessionHandle *handle,
    BossFfiAudioModeSettingsConfigPatch patch,
    BossFfiAudioModeSettingsWriteResult *out_result,
    BossFfiError *out_error
);

bool boss_session_set_equalizer(
    BossFfiSessionHandle *handle,
    BossFfiEqualizerPatch patch,
    BossFfiEqualizerWriteResult *out_result,
    BossFfiError *out_error
);

bool boss_session_set_enabled_setting(
    BossFfiSessionHandle *handle,
    uint8_t function_raw,
    bool enabled,
    bool *out_enabled,
    BossFfiError *out_error
);

bool boss_session_enabled_setting(
    BossFfiSessionHandle *handle,
    uint8_t function_raw,
    bool *out_enabled,
    BossFfiError *out_error
);

bool boss_session_current_audio_mode(
    BossFfiSessionHandle *handle,
    int32_t *out_mode_index,
    BossFfiError *out_error
);

bool boss_session_supported_audio_mode_prompts(
    BossFfiSessionHandle *handle,
    BossBuffer *out_prompts,
    BossFfiError *out_error
);

bool boss_session_audio_mode_configs(
    BossFfiSessionHandle *handle,
    BossBuffer *out_configs,
    BossFfiError *out_error
);

bool boss_session_audio_mode_capabilities(
    BossFfiSessionHandle *handle,
    BossFfiAudioModesCapabilities *out_capabilities,
    BossFfiError *out_error
);

bool boss_session_audio_mode_settings_config(
    BossFfiSessionHandle *handle,
    BossFfiAudioModeSettingsConfig *out_config,
    BossFfiError *out_error
);

bool boss_session_firmware_version(
    BossFfiSessionHandle *handle,
    int32_t port,
    int32_t device_id,
    BossFfiFirmwareVersionInfo *out_info,
    BossFfiError *out_error
);

bool boss_session_standby_timer(
    BossFfiSessionHandle *handle,
    BossFfiStandbyTimerValue *out_value,
    BossFfiError *out_error
);

bool boss_session_settings_snapshot(
    BossFfiSessionHandle *handle,
    BossBuffer *out_packets,
    BossFfiError *out_error
);

bool boss_session_equalizer_settings(
    BossFfiSessionHandle *handle,
    BossFfiEqualizerSettings *out_settings,
    BossFfiError *out_error
);

bool boss_session_favorite_audio_mode_indices(
    BossFfiSessionHandle *handle,
    BossBuffer *out_indices,
    BossFfiError *out_error
);

bool boss_session_on_head_detection(
    BossFfiSessionHandle *handle,
    BossFfiOnHeadDetectionValue *out_value,
    BossFfiError *out_error
);

bool boss_session_set_on_head_detection(
    BossFfiSessionHandle *handle,
    BossFfiOnHeadDetectionValue value,
    BossFfiOnHeadDetectionValue *out_value,
    BossFfiError *out_error
);

bool boss_session_volume_control_status(
    BossFfiSessionHandle *handle,
    BossFfiVolumeControlStatus *out_status,
    BossFfiError *out_error
);

bool boss_session_set_volume_control(
    BossFfiSessionHandle *handle,
    uint8_t value,
    BossFfiVolumeControlStatus *out_status,
    BossFfiError *out_error
);

bool boss_session_set_standby_timer(
    BossFfiSessionHandle *handle,
    int32_t minutes,
    BossFfiStandbyTimerValue *out_value,
    BossFfiError *out_error
);

bool boss_session_set_favorite_audio_mode_indices(
    BossFfiSessionHandle *handle,
    int32_t number_of_modes,
    const int32_t *favorite_indices_data,
    size_t favorite_indices_len,
    BossBuffer *out_indices,
    BossFfiError *out_error
);

bool boss_session_set_audio_mode_favorite(
    BossFfiSessionHandle *handle,
    int32_t index,
    bool is_favorite,
    BossBuffer *out_indices,
    BossFfiError *out_error
);

bool boss_session_save_custom_audio_mode(
    BossFfiSessionHandle *handle,
    const uint8_t *name_data,
    size_t name_len,
    BossFfiAudioModeSettingsConfig settings,
    uint8_t prompt_byte1,
    uint8_t prompt_byte2,
    bool has_requested_slot,
    int32_t requested_slot,
    BossFfiAudioModeConfig *out_config,
    BossFfiError *out_error
);

bool boss_session_delete_custom_audio_mode(
    BossFfiSessionHandle *handle,
    int32_t slot,
    BossFfiAudioModeConfig *out_config,
    BossFfiError *out_error
);

#endif
