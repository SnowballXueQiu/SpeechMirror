# SpeechMirror Flutter 客户端

该工程提供 iOS 与 Android 客户端，包含账号、项目、材料、训练录制、报告和 AI 评委流程。摄像头视频复制到应用文档目录并只保存在本机；训练音频与评委回答音频分别上传到不同的临时 ASR 接口。

## 本地运行

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
```

Android 模拟器访问宿主机时使用 `http://10.0.2.2:8080/api/v1`。真机应使用局域网地址或 HTTPS 公网域名。

## 验证与构建

```bash
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Android 调试 APK 使用调试签名。iOS 的 `--no-codesign` 产物必须由开发者账号重新签名后才能安装到真机；模拟器构建不需要真机签名。

当前 Flutter 客户端尚未桥接共享 C++ 视觉推理核心，因此报告会把视觉维度标为未采集，不生成替代分数。
