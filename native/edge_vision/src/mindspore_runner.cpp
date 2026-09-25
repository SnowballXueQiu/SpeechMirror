#include "mindspore_runner.hpp"

#include <algorithm>
#include <cstring>
#include <filesystem>

#if defined(SM_WITH_MINDSPORE)
#include "include/api/context.h"
#include "include/api/model.h"
#include "include/api/serialization.h"
#endif

namespace speechmirror {

class MindSporeRunner::Impl {
 public:
#if defined(SM_WITH_MINDSPORE)
  std::shared_ptr<mindspore::Model> model;
#endif
  bool ready = false;
};

MindSporeRunner::MindSporeRunner() : impl_(std::make_unique<Impl>()) {}
MindSporeRunner::~MindSporeRunner() = default;

bool MindSporeRunner::Load(const std::string& model_path, int thread_count,
                           std::string* error) {
  if (model_path.empty() || !std::filesystem::is_regular_file(model_path)) {
    *error = "model file does not exist";
    return false;
  }
#if defined(SM_WITH_MINDSPORE)
  auto context = std::make_shared<mindspore::Context>();
  context->SetThreadNum(std::clamp(thread_count, 1, 4));
  context->SetThreadAffinity(0);
  auto cpu = std::make_shared<mindspore::CPUDeviceInfo>();
  cpu->SetEnableFP16(false);
  context->MutableDeviceInfo().push_back(cpu);
  impl_->model = std::make_shared<mindspore::Model>();
  auto status = impl_->model->Build(model_path, mindspore::kMindIR, context);
  if (status != mindspore::kSuccess) {
    *error = "MindSpore Lite failed to build the model";
    impl_->model.reset();
    return false;
  }
  impl_->ready = true;
  return true;
#else
  (void)thread_count;
  *error = "library was built without SM_WITH_MINDSPORE";
  return false;
#endif
}

bool MindSporeRunner::Ready() const { return impl_->ready; }

bool MindSporeRunner::RunRgba(const uint8_t* rgba, int width, int height,
                              int row_stride, std::vector<float>* output,
                              std::string* error) {
#if defined(SM_WITH_MINDSPORE)
  auto inputs = impl_->model->GetInputs();
  if (inputs.size() != 1) {
    *error = "model must have exactly one input tensor";
    return false;
  }
  auto& input = inputs.front();
  const auto shape = input.Shape();
  if (shape.size() != 4 || shape[0] != 1 || shape[3] != 3 ||
      shape[1] != height || shape[2] != width) {
    *error = "model input must be NHWC RGB and match the sampled frame";
    return false;
  }
  auto* destination = static_cast<float*>(input.MutableData());
  if (destination == nullptr) {
    *error = "model input tensor is not writable";
    return false;
  }
  for (int y = 0; y < height; ++y) {
    const uint8_t* row = rgba + y * row_stride;
    for (int x = 0; x < width; ++x) {
      const auto source_index = x * 4;
      const auto target_index = (y * width + x) * 3;
      destination[target_index] = row[source_index] / 255.0f;
      destination[target_index + 1] = row[source_index + 1] / 255.0f;
      destination[target_index + 2] = row[source_index + 2] / 255.0f;
    }
  }
  std::vector<mindspore::MSTensor> outputs;
  auto status = impl_->model->Predict(inputs, &outputs);
  if (status != mindspore::kSuccess || outputs.size() != 1 ||
      outputs.front().DataSize() < 4 * sizeof(float)) {
    *error = "model prediction failed or output tensor is malformed";
    return false;
  }
  const auto* values = static_cast<const float*>(outputs.front().Data().get());
  output->assign(values, values + 4);
  return true;
#else
  (void)rgba;
  (void)width;
  (void)height;
  (void)row_stride;
  (void)output;
  *error = "library was built without SM_WITH_MINDSPORE";
  return false;
#endif
}

}  // namespace speechmirror
