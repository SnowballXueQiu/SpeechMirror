# SpeechMirror Edge Vision

共享 C ABI 只输出可观察的画面指标：人脸是否存在、视线居中度、姿态稳定度和模型置信度。它不推断情绪、性格、可信度或医学意义上的紧张程度。

默认构建不包含 MindSpore Lite，也不会生成占位指标：模型调用返回 `SM_EDGE_MODEL_NOT_LOADED`。提供合法 SDK 和经过验证的四输出 `.ms` 模型后，使用：

```bash
cmake -S . -B build \
  -DSM_WITH_MINDSPORE=ON \
  -DMINDSPORE_LITE_ROOT=/absolute/path/to/mindspore-lite
cmake --build build
ctest --test-dir build --output-on-failure
```

移动端应以低频抽帧调用 ABI，录制管线与推理管线分离。iOS/Android/HarmonyOS 的封装必须检查返回码，只有 `SM_EDGE_OK` 才能把指标上传到 `/sessions/{id}/metrics`。
