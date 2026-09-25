# Embedding 与语义检索验证记录

- 验证日期：2026-09-26
- API 服务版本：`b20b14a`
- 供应商：阿里云百炼 OpenAI 兼容接口
- 模型：`qwen3.7-text-embedding-flash`
- 测试材料：仓库 `README.md`

本次验证只在 VPS 私有 `.env` 中配置 Embedding 凭据，文件权限保持为 `600`。健康接口返回 `llm: true`、`embedding: true`、`asr: false`、`ocr: false`，没有把尚未验证的 ASR 和 OCR 标记为可用。

首先直接调用 Embedding 接口，脱敏结果如下：

```json
{
  "object": "list",
  "model": "qwen3.7-text-embedding-flash",
  "data_count": 1,
  "dimension": 1024
}
```

随后使用临时账号创建项目并上传 `README.md`。材料处理状态由 `processing` 进入 `ready`，SQLite 副本中的真实记录如下：

```json
{
  "document_status": "ready",
  "storage": {
    "chunk_count": 3,
    "vector_count": 3,
    "min_vector_json_bytes": 19274,
    "max_vector_json_bytes": 19301
  },
  "semantic_retrieval_question_count": 5
}
```

`chunk_count` 与 `vector_count` 均为 3，说明每个新材料片段都保存了非空向量。之后的问题生成会先为检索语句生成向量，由 Rust 在当前项目片段内计算余弦相似度；该路径成功返回技术、应用、创新、风险和质疑共 5 个问题，证明项目内语义检索已实际执行。验证结束后删除测试项目、数据库副本和临时令牌文件。
