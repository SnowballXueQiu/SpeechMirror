# 云端 OCR 与材料入库验证记录

- 验证日期：2026-09-26
- 服务端提交：`e75d1d7`
- 供应商：阿里云百炼 OpenAI 兼容接口
- 模型：`qwen3.8-omni-flash`
- 样本：1400×520 JPEG 中文测试图，35621 字节

测试图由 ImageMagick 使用系统中文字体生成，包含以下三行已知文字：

```text
SpeechMirror 言镜
原始视频仅保存在手机本地
内容评价必须引用项目材料
```

首先直连模型验证 `image_url` Data URL 协议，接口返回 HTTP 200，三行文字与原图逐字一致。随后部署同一模型，通过 SpeechMirror 的注册、项目创建和图片材料上传接口执行真实后台任务。服务端完成云端 OCR、文本分块、Embedding 和 SQLite 入库后，材料状态变为 `ready`。

脱敏后的真实结果如下：

```json
{
  "ai_configured": true,
  "providers": {
    "llm": true,
    "embedding": true,
    "asr": true,
    "ocr": true
  },
  "document_status": "ready",
  "extracted_text": "SpeechMirror 言镜\n原始视频仅保存在手机本地\n内容评价必须引用项目材料",
  "storage": {
    "chunk_count": 1,
    "vector_count": 1
  }
}
```

SQLite 中该材料生成 1 个文本片段和 1 个非空向量。验证完成后已删除临时账号令牌、测试项目、数据库副本和测试图片。本记录只证明受控测试图的 OCR 准确性及服务端入库闭环，不把结果外推为复杂拍照场景的统一准确率。
