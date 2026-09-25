cmake_minimum_required(VERSION 3.18.1)
project(speechmirror_edge_napi)

set(SM_EDGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../native/edge_vision")
set(SM_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${SM_EDGE_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/edge")

add_library(speechmirror_edge_napi SHARED edge_napi.cpp)
target_compile_features(speechmirror_edge_napi PRIVATE cxx_std_17)
target_include_directories(speechmirror_edge_napi PRIVATE "${SM_EDGE_ROOT}/include")
target_link_libraries(speechmirror_edge_napi PRIVATE speechmirror_edge libace_napi.z.so libhilog_ndk.z.so)
