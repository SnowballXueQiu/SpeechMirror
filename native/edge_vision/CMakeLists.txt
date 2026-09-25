cmake_minimum_required(VERSION 3.18)
project(speechmirror_edge VERSION 0.1.0 LANGUAGES CXX)

option(SM_WITH_MINDSPORE "Build against a supplied MindSpore Lite SDK" OFF)
option(SM_BUILD_TESTS "Build native contract tests" ON)
set(MINDSPORE_LITE_ROOT "" CACHE PATH "MindSpore Lite SDK root")

add_library(speechmirror_edge STATIC
    src/edge_vision.cpp
    src/mindspore_runner.cpp
)
target_compile_features(speechmirror_edge PUBLIC cxx_std_17)
target_include_directories(speechmirror_edge PUBLIC include PRIVATE src)
target_compile_options(speechmirror_edge PRIVATE -Wall -Wextra -Wpedantic)

if(SM_WITH_MINDSPORE)
    if(NOT EXISTS "${MINDSPORE_LITE_ROOT}/runtime/include/include/api/model.h")
        message(FATAL_ERROR "MINDSPORE_LITE_ROOT does not contain runtime headers")
    endif()
    target_compile_definitions(speechmirror_edge PRIVATE SM_WITH_MINDSPORE=1)
    target_include_directories(speechmirror_edge PRIVATE
        "${MINDSPORE_LITE_ROOT}/runtime/include"
        "${MINDSPORE_LITE_ROOT}/runtime/include/dataset"
    )
    find_library(MSLITE_LIBRARY mindspore-lite
        PATHS "${MINDSPORE_LITE_ROOT}/runtime/lib"
        NO_DEFAULT_PATH REQUIRED)
    target_link_libraries(speechmirror_edge PRIVATE "${MSLITE_LIBRARY}")
endif()

if(SM_BUILD_TESTS)
    enable_testing()
    add_executable(speechmirror_edge_test tests/edge_vision_test.cpp)
    target_link_libraries(speechmirror_edge_test PRIVATE speechmirror_edge)
    add_test(NAME edge_vision_contract COMMAND speechmirror_edge_test)
endif()
