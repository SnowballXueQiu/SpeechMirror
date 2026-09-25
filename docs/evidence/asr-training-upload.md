# 训练音频 ASR 验证记录

- 验证日期：2026-09-26
- 服务端提交：`8134922`
- 供应商：阿里云百炼 OpenAI 兼容接口
- 模型：`qwen3-asr-flash-2026-02-10`
- 样本时长：7.550250 秒
- 样本格式：16 kHz、单声道 PCM WAV
- 样本大小：241686 字节

验证前通过百炼模型列表确认工作区存在该模型。供应商的 `/audio/transcriptions` 路由返回 HTTP 404，因此服务端没有沿用不兼容的 multipart 假设，而是按已实测协议向 `/chat/completions` 发送 `input_audio` Data URL。单元测试同时覆盖 WAV、M4A 和 MP3 容器识别以及非法内容拒绝。

测试语音由 macOS 中文语音合成生成，原文为：

> 言镜是一款面向大学生答辩训练的人工智能应用。原始视频保存在手机本地。

部署后使用临时账号依次调用注册、项目创建、训练创建和训练音频上传接口。脱敏后的真实结果如下：

```json
{
  "providers": {
    "llm": true,
    "embedding": true,
    "asr": true,
    "ocr": false
  },
  "response": {
    "transcript": "言镜是一款面向大学生答辩训练的人工智能应用。原始视频保存在手机本地。"
  },
  "persisted_transcript": "言镜是一款面向大学生答辩训练的人工智能应用。原始视频保存在手机本地。",
  "temp_audio_files_after_job": 0
}
```

接口响应与训练记录中的文本完全一致，临时音频在识别完成后删除。本记录验证的是后端真实 ASR 闭环，不代替 iOS、Android 或 HarmonyOS 真机 5 分钟录音验收，也不将语音合成样本描述为真实用户发言。
