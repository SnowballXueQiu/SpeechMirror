#include <napi/native_api.h>
#include <napi/native_node_api.h>

#include "speechmirror_edge.h"

namespace {
napi_value AbiVersion(napi_env env, napi_callback_info) {
  napi_value result;
  napi_create_int32(env, sm_edge_abi_version(), &result);
  return result;
}

napi_value ModuleInit(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"abiVersion", nullptr, AbiVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, 1, descriptors);
  return exports;
}
}  // namespace

static napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = ModuleInit,
    .nm_modname = "speechmirror_edge_napi",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterSpeechMirrorEdge() {
  napi_module_register(&module);
}
