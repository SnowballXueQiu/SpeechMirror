# 训练报告生成验证记录

- 验证日期：2026-09-26
- 服务端提交：`e6c12c4`
- 调试接口：`http://183.234.145.210:48180`
- 材料：仓库 `README.md`，经材料上传、解析、分块和向量化后状态为 `ready`

本次验证通过 SpeechMirror 公共接口依次完成临时账号注册、项目创建、材料上传、训练创建、端侧指标上传、训练完成、报告生成和报告读取。答辩文本与端侧指标均为专门构造的合成测试数据，只用于验证计算和持久化链路，不代表真实用户表现、用户调研或真机视觉模型输出。

合成指标包含视线偏离、姿态不稳和人物离开画面三个时间点。合成答辩文本覆盖项目定位、三端技术架构、隐私设计、AI 评委、国产模型接口和 HarmonyOS 6 原生适配，并含一次口头禅“嗯”。报告生成调用真实 DeepSeek 接口；内容证据必须通过材料分块编号和连续原文引文校验后才能写入数据库。

脱敏后的接口结果如下：

```json
{
  "document_status": "ready",
  "actual_seconds": 118,
  "character_count": 428,
  "characters_per_minute": 217.6271186440678,
  "filler_counts": {
    "嗯": 1
  },
  "long_pause_count": null,
  "scores": {
    "content": 78,
    "delivery": 97,
    "timing": 98,
    "visual": 70,
    "qa": null
  },
  "content_evidence_count": 5,
  "timeline_kinds": [
    "framing",
    "gaze",
    "posture"
  ],
  "suggestion_count": 5,
  "model_confidence": 0.9,
  "get_matches_post": true
}
```

自动断言确认：内容证据非空；语速、表达、时间和视觉指标均存在；三类预设视觉问题均进入时间线；尚未完成评委问答时 `qa.score` 为 `null`；`GET /sessions/{id}/report` 与 `POST /sessions/{id}/analyze` 返回一致，证明报告已经持久化。

当前 ASR 结果没有词级或分段时间戳，因此无法计算长停顿次数。接口明确返回 `long_pause_count: null`，客户端显示“未计算”，而不是用无依据的 `0` 代替。长停顿指标须在接入带时间戳的 ASR 或可靠分段数据后另行验收。本记录也不代替 iOS、Android 或 HarmonyOS 真机五分钟训练测试。
