# SpeechMirror / 言镜

SpeechMirror 是面向大学生答辩训练的三端应用。用户上传自己的论文、PPT、文档或图片，在手机上完成模拟答辩；系统只上传音频和端侧派生指标，原始视频保存在本机。内容评价必须引用用户材料，不输出情绪、性格、可信度或医学意义上的判断。

## 仓库结构

- `apps/flutter_mobile`：iOS / Android Flutter 客户端
- `apps/harmony`：HarmonyOS 6 ArkTS / ArkUI 原生客户端
- `services/api`：Rust + Axum + SeaORM + SQLite 后端
- `native/edge_vision`：三端共享的 C++ 端侧指标 ABI
- `openapi/openapi.yaml`：三端共同遵循的接口契约
- `docs/paper`：XeLaTeX 论文源码与可核验资料记录
- `infra`：Docker Compose 与 Caddy 部署配置

## 本地启动

后端需要 Rust、Poppler 和 LibreOffice。Tesseract 可在未配置云端 OCR 时提供本地图片与扫描 PDF 文字提取；中文识别需安装 `chi_sim` 语言包。复制 `services/api/.env.example` 为 `.env`，至少修改 `JWT_SECRET`。LLM 默认接入 DeepSeek，Embedding、ASR 和 OCR 分别使用独立的服务地址与密钥；DeepSeek 密钥不会被用于其未提供的语音识别、OCR 或向量接口。
若另有浏览器前端，再通过 `CORS_ALLOWED_ORIGINS` 配置逗号分隔的 HTTPS 来源；默认不允许浏览器跨域访问，iOS、Android 与 HarmonyOS 原生请求不依赖 CORS。

```bash
cd services/api
cargo run
```

健康检查和接口契约位于 `http://127.0.0.1:8080/api/v1/health` 与 `http://127.0.0.1:8080/api-docs/openapi.yaml`。

```bash
cd apps/flutter_mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Android 模拟器访问宿主机时应把地址改为 `http://10.0.2.2:8080/api/v1`。真机必须使用局域网或 HTTPS 公网地址。

## Docker 部署

`infra/docker-compose.yml` 默认将 API 发布到宿主机回环地址 `127.0.0.1:48180`，避免未配置域名与 HTTPS 时意外暴露公网。临时远程调试可在 `infra/.env` 中显式设置 `API_PUBLISH_HOST=0.0.0.0` 与未占用的 `API_PORT`；正式部署应配置 `DOMAIN` 并通过 Caddy 提供 HTTPS。

```bash
cd infra
docker compose up -d --build api
curl http://127.0.0.1:48180/api/v1/health
```

后端 Dockerfile 使用 BuildKit 命名缓存保存 Cargo registry、Git 依赖和 release 编译产物。同一台构建主机首次构建完成后，后续源码更新只重新编译受影响的 crate；不要在日常部署前执行 `docker builder prune`，否则会主动清除这些缓存。

## 验证命令

```bash
cd services/api && cargo test
cd apps/flutter_mobile && flutter analyze && flutter test
cd apps/flutter_mobile && flutter build apk --debug
```

构建产物统一归档到：

- `output/android/SpeechMirror-android-debug.apk`：Android 调试签名 APK。
- `output/ios/SpeechMirror-ios-debug-unsigned.zip`：iOS 真机 Debug App，无签名，需用开发者账号签名。
- `output/pdf/SpeechMirror项目论文.pdf`：带真实 iOS 模拟器截图的可编译论文。

## 后续实施

所有需要凭据、设备、模型、部署或人工参与的事项集中记录在 [`docs/IMPLEMENTATION_CHECKLIST.md`](docs/IMPLEMENTATION_CHECKLIST.md)。论文正文不放置待验证标记、空白问卷或未产生的数据。
