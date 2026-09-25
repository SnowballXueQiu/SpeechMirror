#include "speechmirror_edge.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include "mindspore_runner.hpp"

struct SmEdgeHandle {
  speechmirror::MindSporeRunner runner;
  std::string error;
};

namespace {
bool UnitValue(float value) { return std::isfinite(value) && value >= 0.0f && value <= 1.0f; }
}  // namespace

int32_t sm_edge_abi_version(void) { return SM_EDGE_ABI_VERSION; }

SmEdgeHandle* sm_edge_create(const char* model_path, int32_t thread_count) {
  auto* handle = new SmEdgeHandle();
  if (model_path == nullptr) {
    handle->error = "model_path is required";
    return handle;
  }
  handle->runner.Load(model_path, std::clamp(thread_count, 1, 4), &handle->error);
  return handle;
}

void sm_edge_destroy(SmEdgeHandle* handle) { delete handle; }

SmEdgeStatus sm_edge_analyze_rgba(SmEdgeHandle* handle, const uint8_t* rgba,
                                  int32_t width, int32_t height,
                                  int32_t row_stride, int64_t timestamp_ms,
                                  SmEdgeMetric* output) {
  if (handle == nullptr || rgba == nullptr || output == nullptr || width <= 0 ||
      height <= 0 || row_stride < width * 4 || timestamp_ms < 0) {
    return SM_EDGE_INVALID_ARGUMENT;
  }
  if (!handle->runner.Ready()) {
    return SM_EDGE_MODEL_NOT_LOADED;
  }
  std::vector<float> values;
  if (!handle->runner.RunRgba(rgba, width, height, row_stride, &values,
                              &handle->error)) {
    return SM_EDGE_INFERENCE_FAILED;
  }
  if (values.size() < 4 || !UnitValue(values[0]) || !UnitValue(values[1]) ||
      !UnitValue(values[2]) || !UnitValue(values[3])) {
    handle->error = "expected four normalized outputs: face, gaze, posture, confidence";
    return SM_EDGE_OUTPUT_INVALID;
  }
  output->timestamp_ms = timestamp_ms;
  output->face_detected = values[0] >= 0.5f ? 1 : 0;
  output->gaze_centered = values[1];
  output->posture_score = values[2];
  output->confidence = values[3];
  return SM_EDGE_OK;
}

const char* sm_edge_last_error(const SmEdgeHandle* handle) {
  return handle == nullptr ? "invalid handle" : handle->error.c_str();
}
