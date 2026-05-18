#ifndef LIBBOSS_RS_H
#define LIBBOSS_RS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct BossBuffer {
    uint8_t *data;
    size_t len;
} BossBuffer;

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
} BossFfiErrorCode;

typedef enum BossFfiWriteDisposition {
    BOSS_FFI_WRITE_DISPOSITION_UNCHANGED = 0,
    BOSS_FFI_WRITE_DISPOSITION_UPDATED = 1,
    BOSS_FFI_WRITE_DISPOSITION_VERIFICATION_INCONCLUSIVE = 2,
} BossFfiWriteDisposition;

typedef struct BossFfiSessionCallbacks {
    void *context;
    uint8_t transport_kind;
    BossFfiLinkStatus (*send_packet_bytes)(void *context, const uint8_t *packet_data, size_t packet_len);
    BossFfiLinkStatus (*next_packet_bytes)(void *context, uint64_t timeout_millis, BossBuffer *out_packet);
    void (*release_context)(void *context);
} BossFfiSessionCallbacks;

typedef struct BossFfiCurrentAudioModeWriteResult {
    BossFfiWriteDisposition disposition;
    int32_t mode_index;
    int32_t target_index;
} BossFfiCurrentAudioModeWriteResult;

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

typedef struct BossFfiAudioModeSettingsWriteResult {
    BossFfiWriteDisposition disposition;
    BossFfiAudioModeSettingsConfig config;
} BossFfiAudioModeSettingsWriteResult;

typedef struct BossFfiError {
    BossFfiErrorCode code;
    BossBuffer message;
    bool has_bmap_error_code;
    uint8_t bmap_error_code;
} BossFfiError;

typedef struct BossFfiSessionHandle BossFfiSessionHandle;

#endif
