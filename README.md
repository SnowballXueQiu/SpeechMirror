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

后端需要 Rust、Poppler 和 LibreOffice。复制 `services/api/.env.example` 为 `.env`，至少修改 `JWT_SECRET`；真实 ASR、OCR、问题生成和报告内容评价还需要配置兼容 OpenAI API 的国产服务凭据。
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

## 验证命令

```bash
cd services/api && cargo test
cd apps/flutter_mobile && flutter analyze && flutter test
cd apps/flutter_mobile && flutter build apk --debug
```

构建产物统一归档到：

- `output/android/SpeechMirror-android-debug.apk`：Android 调试签名 APK。
- `output/ios/SpeechMirror-ios-debug-unsigned.zip`：iOS 真机 Debug App，无签名，需用开发者账号签名。
- `output/pdf/SpeechMirror项目论文-工作稿.pdf`：带真实 iOS 模拟器截图的论文工作稿。

## 当前验收边界

Flutter 客户端和 Rust API 可在本机编译测试。真实 AI 输出取决于供应商凭据；HarmonyOS 安装包、MindSpore Lite 实机帧率与能耗数据取决于 DevEco Studio、HarmonyOS 6 SDK、模型文件和真机。论文中的用户调研、截图和性能结果必须由真实测试补入，不使用虚构数据。
