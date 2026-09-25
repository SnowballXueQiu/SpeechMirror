# AI 评委问题生成验证记录

- 验证日期：2026-09-26
- 服务端提交：`b20b14a`
- 调试接口：`http://183.234.145.210:48180`
- LLM：DeepSeek `deepseek-flash`
- 测试材料：仓库 `README.md`

验证过程使用临时账号创建项目，上传 Markdown 材料并等待处理状态变为 `ready`，随后请求生成 5 个问题。服务端逐项检查类别、非空问题、当前项目 `chunk_id` 和材料连续原文；不合格类别最多定向补问两次，全部合格后才在同一事务中保存。验证结束后删除测试项目和临时令牌文件。

接口返回 HTTP 200，并通过以下断言：

- 问题数恰好为 5；
- 类别顺序为技术、应用、创新、风险、质疑；
- 每个问题都有非空问题文本和至少一条材料证据；
- 每条引文都由服务端确认是相应材料片段中的连续原文。

脱敏后的真实响应如下。随机生成的问题、片段编号及引文均不包含账号、令牌或 API Key。

```json
[
  {
    "category": "技术",
    "question": "三端共享的 C++ 端侧指标 ABI 与 OpenAPI 契约如何保证 iOS、Android、HarmonyOS 上指标提取和接口行为一致？版本升级时如何检测并防止 ABI 或契约漂移？",
    "evidence": [
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "`native/edge_vision`：三端共享的 C++ 端侧指标 ABI"},
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "`openapi/openapi.yaml`：三端共同遵循的接口契约"}
    ]
  },
  {
    "category": "应用",
    "question": "面向大学生答辩训练，用户从上传论文、PPT、文档或图片到手机模拟答辩的完整使用路径是什么？在哪些环节需要授权、确认原始视频仅保存在本机并处理端侧指标异常？",
    "evidence": [
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "SpeechMirror 是面向大学生答辩训练的三端应用。"},
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "用户上传自己的论文、PPT、文档或图片，在手机上完成模拟答辩；系统只上传音频和端侧派生指标，原始视频保存在本机。"}
    ]
  },
  {
    "category": "创新",
    "question": "将‘仅上传音频和端侧派生指标、原始视频留本机’与‘内容评价必须引用用户材料且不做情绪、性格、可信度或医学判断’结合，项目的核心创新是隐私保护、可解释评价还是端云协同？与通用答辩评分或视频面试分析相比有何不可替代性？",
    "evidence": [
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "系统只上传音频和端侧派生指标，原始视频保存在本机。"},
      {"chunk_id": "c8b1f528-fc03-4d7e-b693-ef33faf94f21", "quote": "内容评价必须引用用户材料，不输出情绪、性格、可信度或医学意义上的判断。"}
    ]
  },
  {
    "category": "风险",
    "question": "系统依赖 DeepSeek、Embedding、ASR 和 OCR 多个外部服务，并允许在调试时设置 `API_PUBLISH_HOST=0.0.0.0`。密钥分离管理和发布地址切换分别会带来哪些泄露、锁定、中断或未加 HTTPS 暴露风险？如何降级和默认防护？",
    "evidence": [
      {"chunk_id": "8e27ae8c-92c0-4f93-90fd-7993e83d6a70", "quote": "LLM 默认接入 DeepSeek，Embedding、ASR 和 OCR 分别使用独立的服务地址与密钥；DeepSeek 密钥不会被用于其未提供的语音识别、OCR 或向量接口。"},
      {"chunk_id": "1d276c65-421b-4ff1-99af-696363c9655e", "quote": "`API_PUBLISH_HOST=0.0.0.0` 与未占用的 `API_PORT`；正式部署应配置 `DOMAIN` 并通过 Caddy 提供 HTTPS。"}
    ]
  },
  {
    "category": "质疑",
    "question": "材料称‘论文正文不放置待验证标记、空白问卷或未产生的数据’，但仍有 IMPLEMENTATION_CHECKLIST 集中记录待办。如何证明当前论文中的可核验资料、构建产物和测试结果均已真实产生，而不是把未完成项转移位置后仍存在未验证结论？",
    "evidence": [
      {"chunk_id": "1d276c65-421b-4ff1-99af-696363c9655e", "quote": "所有需要凭据、设备、模型、部署或人工参与的事项集中记录在 [`docs/IMPLEMENTATION_CHECKLIST.md`](docs/IMPLEMENTATION_CHECKLIST.md)。论文正文不放置待验证标记、空白问卷或未产生的数据。"}
    ]
  }
]
```

同一版本还完成 14 项 Rust 测试。新增测试覆盖错误类别、空问题、伪造引文、重复问题、缺失类别补问以及最终类别顺序。
