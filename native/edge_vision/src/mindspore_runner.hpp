#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace speechmirror {

class MindSporeRunner {
 public:
  MindSporeRunner();
  ~MindSporeRunner();
  MindSporeRunner(const MindSporeRunner&) = delete;
  MindSporeRunner& operator=(const MindSporeRunner&) = delete;

  bool Load(const std::string& model_path, int thread_count, std::string* error);
  bool Ready() const;
  bool RunRgba(const uint8_t* rgba, int width, int height, int row_stride,
               std::vector<float>* output, std::string* error);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace speechmirror
