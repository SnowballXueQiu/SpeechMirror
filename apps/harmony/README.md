# HarmonyOS 6 原生客户端

该目录是 Stage 模型、ArkTS/ArkUI 原生工程，不包含 WebView。它包含登录、项目、材料状态、训练预览 surface、系统振动提醒、报告和 AI 评委页面，并通过 N-API 链接共享 C++ 端侧指标 ABI。

当前工作站未安装 DevEco Studio/HarmonyOS 6 SDK，因而尚未生成或声称通过 HAP、真机录制、后台任务、5 FPS 与能耗测试。导入 DevEco Studio 后需要完成以下设备相关工作：

1. 让 IDE 按实际 SDK 版本升级 `modelVersion` 和 `compatibleSdkVersion`。
2. 配置签名与真机权限，绑定 `TrainingPage` 的 `XComponent` surface 到 CameraKit 与 AVRecorder。
3. 提供合法的 MindSpore Lite SDK 和经过验证的 `.ms` 模型，启用 `SM_WITH_MINDSPORE`。
4. 为 API 基址配置 HTTPS 域名，并完成网络安全配置。
5. 在 HarmonyOS 6 真机记录录制流畅度、抽帧 FPS、温升与能耗；结果再写入论文。

训练页当前在媒体管线未绑定时明确停止，不上传伪音频，也不产生视觉假分数。
