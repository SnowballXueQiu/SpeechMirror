# HarmonyOS 6 原生客户端

该目录是 Stage 模型、ArkTS/ArkUI 原生工程，不包含 WebView。它包含登录、项目、材料状态、训练预览 surface、系统振动提醒、报告和 AI 评委页面，并通过 N-API 链接共享 C++ 端侧指标 ABI。

## 已验证构建环境

- DevEco Studio `6.0.1.251`（6.0.1 Release）。
- IDE 内置 HarmonyOS SDK `6.0.1.112`、API 21，项目兼容与目标版本均为 `6.0.0(20)`。
- DevEco 工程同步、ArkTS 编译和 `arm64-v8a` C++ N-API 编译均已通过。
- 已生成未签名 Debug HAP，产物包含 `ets/modules.abc` 和 `libspeechmirror_edge_napi.so`。

在 DevEco Studio 中打开本目录即可同步工程。命令行构建可执行：

```bash
cd apps/harmony
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

未签名产物位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。

## 尚未验证

1. 用户确认 HarmonyOS 软件许可协议后下载并配置模拟器，或连接 HarmonyOS 6 真机。
2. 配置应用签名与真机权限，完成 HAP 安装和运行截图。
3. 将 `TrainingPage` 的 `XComponent` surface 绑定 CameraKit 与 AVRecorder。
4. 提供合法的 MindSpore Lite SDK 和经过验证的 `.ms` 模型，启用 `SM_WITH_MINDSPORE`。
5. 为 API 基址配置 HTTPS 域名，并在真机记录录制流畅度、抽帧 FPS、温升与能耗。

训练页当前在媒体管线未绑定时明确停止，不上传伪音频，也不产生视觉假分数。
