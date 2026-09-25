# SpeechMirror Flutter 客户端

该工程提供 iOS 与 Android 客户端，包含账号、项目、材料、训练录制、报告和 AI 评委流程。摄像头视频复制到应用文档目录并只保存在本机；训练音频与评委回答音频分别上传到不同的临时 ASR 接口。

材料页支持 PDF、PPTX、DOCX、UTF-8 文本、Markdown、PNG 和 JPEG，单文件上限为 25 MiB。上传后客户端会自动刷新处理状态；点击已完成或失败的材料可查看提取结果、人工纠正并重建知识库索引。

## 本地运行

```bash
flutter pub get
flutter run
```

未指定 `API_BASE_URL` 时，Android 模拟器自动使用 `http://10.0.2.2:8080/api/v1`，iOS Simulator 和桌面调试使用 `http://127.0.0.1:8080/api/v1`。真机应通过 `--dart-define=API_BASE_URL=...` 指定局域网地址或 HTTPS 公网域名。

macOS 上的 CocoaPods 1.16.2 会将工作路径中的全角括号错误归一化为半角括号。若 `pod install` 误报找不到已存在的 `Podfile`，请将仓库克隆到不含全角括号的路径（如 `~/Projects/speechmirror`）后再构建 iOS 工程。

## 验证与构建

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Android 调试 APK 使用调试签名。iOS 的 `--no-codesign` 产物必须由开发者账号重新签名后才能安装到真机；模拟器构建不需要真机签名。

当前 Flutter 客户端尚未桥接共享 C++ 视觉推理核心，因此报告会把视觉维度标为未采集，不生成替代分数。
