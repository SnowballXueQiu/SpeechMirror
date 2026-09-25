#ifndef SPEECHMIRROR_EDGE_H
#define SPEECHMIRROR_EDGE_H

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#define SM_EDGE_ABI_VERSION 1

typedef struct SmEdgeHandle SmEdgeHandle;

typedef enum SmEdgeStatus {
  SM_EDGE_OK = 0,
  SM_EDGE_INVALID_ARGUMENT = 1,
  SM_EDGE_MODEL_NOT_LOADED = 2,
  SM_EDGE_INFERENCE_FAILED = 3,
  SM_EDGE_OUTPUT_INVALID = 4
} SmEdgeStatus;

typedef struct SmEdgeMetric {
  int64_t timestamp_ms;
  uint8_t face_detected;
  float gaze_centered;
  float posture_score;
  float confidence;
} SmEdgeMetric;

int32_t sm_edge_abi_version(void);
SmEdgeHandle* sm_edge_create(const char* model_path, int32_t thread_count);
void sm_edge_destroy(SmEdgeHandle* handle);

// RGBA input is copied into the model tensor. Values outside [0, 1] are never
// returned as metrics; malformed model output fails with SM_EDGE_OUTPUT_INVALID.
SmEdgeStatus sm_edge_analyze_rgba(
    SmEdgeHandle* handle,
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t row_stride,
    int64_t timestamp_ms,
    SmEdgeMetric* output);

const char* sm_edge_last_error(const SmEdgeHandle* handle);

#if defined(__cplusplus)
}
#endif

#endif
