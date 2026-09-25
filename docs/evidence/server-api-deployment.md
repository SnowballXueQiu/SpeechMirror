# VPS API 调试部署证据

- 验证日期：2026-09-25
- Git 提交：`bea2f3b`
- 部署目录：`/home/snowball_233/SpeechMirror`
- 宿主机端口：`48180`
- 容器重启策略：`unless-stopped`
- SQLite 与材料目录：Docker 卷 `infra_speechmirror_data`
- 私有环境文件权限：`600`

服务器本机及外部网络均成功访问健康接口：

```json
{"status":"ok","ai_configured":false,"providers":{"llm":false,"embedding":false,"asr":false,"ocr":false}}
```

OpenAPI 契约端点成功返回 `openapi: 3.1.0`。本次部署未写入任何 AI API Key，未启动 Caddy，也未将 HTTP 调试端口描述为生产 HTTPS 服务。域名解析、TLS 证书、AI 真实调用、数据备份与恢复仍按实施清单逐项验证。
