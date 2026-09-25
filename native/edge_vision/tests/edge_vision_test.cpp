#include "speechmirror_edge.h"

#include <array>
#include <cassert>
#include <string>

int main() {
  assert(sm_edge_abi_version() == 1);
  SmEdgeHandle* handle = sm_edge_create("/path/that/does/not/exist.ms", 2);
  assert(handle != nullptr);
  assert(std::string(sm_edge_last_error(handle)).find("does not exist") != std::string::npos);
  std::array<uint8_t, 16> pixels{};
  SmEdgeMetric metric{};
  assert(sm_edge_analyze_rgba(handle, pixels.data(), 2, 2, 8, 100, &metric) ==
         SM_EDGE_MODEL_NOT_LOADED);
  assert(sm_edge_analyze_rgba(nullptr, pixels.data(), 2, 2, 8, 100, &metric) ==
         SM_EDGE_INVALID_ARGUMENT);
  sm_edge_destroy(handle);
  return 0;
}
