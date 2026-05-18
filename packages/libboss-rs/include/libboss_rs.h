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

typedef struct BossFfiEqualizerWriteResult {
    BossFfiWriteDisposition disposition;
    BossFfiEqualizerSettings settings;
} BossFfiEqualizerWriteResult;

typedef struct BossFfiError {
    BossFfiErrorCode code;
    BossBuffer message;
    bool has_bmap_error_code;
    uint8_t bmap_error_code;
} BossFfiError;

typedef struct BossFfiSessionHandle BossFfiSessionHandle;

void boss_buffer_free(BossBuffer buffer);
void boss_error_free(BossFfiError error);
bool boss_bmap_decode_frame_size(const uint8_t *frame_data, size_t frame_len, size_t *out_payload_len);
BossBuffer boss_copy_bytes(const uint8_t *data, size_t len);

BossFfiSessionHandle *boss_session_create(BossFfiSessionCallbacks callbacks, BossFfiError *out_error);
void boss_session_free(BossFfiSessionHandle *handle);

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

#endif
