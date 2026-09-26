# iOS 公网包、界面回归与真机签名记录

## 环境与产物

- 日期：2026-09-26。
- 客户端：Flutter 3.35.5、Xcode 26.2、iOS 26.2 模拟器 `SpeechMirror QA`，以及 iPhone 15 Pro / iOS 26.3 Beta 真机。
- API：`http://183.234.145.210:48180/api/v1`。
- Bundle ID：`cn.speechmirror.speechmirror`。
- Debug 与真机 Profile 测试构建分别使用 `Info-Debug.plist`、`Info-Profile.plist` 放行当前无域名阶段的明文 HTTP；Release 继续使用不含该放行项的 `Info.plist`。
- Simulator Debug ZIP：`output/ios/SpeechMirror-ios-simulator-debug-vps.zip`，SHA-256 `4bd7dc73fb0b4d81101fbbd70274796fda0aa525ac5e70a689136235903e1388`。
- iPhoneOS Debug 未签名 ZIP：`output/ios/SpeechMirror-ios-device-debug-vps-unsigned.zip`，SHA-256 `3d6a6827d36914eeea6fccfa95209ead6e283027d426470e236ad76c51e368ba`。
- iPhoneOS Profile 公网测试签名 ZIP 使用独立 Profile plist 在编译签名阶段放行当前无域名 HTTP；Release 配置仍保持 ATS 安全限制。产物校验值在每次真机构建后更新。

## 实际界面流程

1. 将 Simulator Debug 构建安装到已启动的 iOS 模拟器，确认编译产物内含 VPS 地址，最终 `Info.plist` 含 `NSAllowsArbitraryLoads = true`。
2. 使用既有演示账号从登录页登录，项目接口真实返回空列表。
3. 从 iOS 界面创建 `iOS VPS 回归测试` 项目，目标时长为 5 分钟。
4. 打开“添加材料”后，iOS 原生文件选择器正常显示。由于模拟器文件选择器中没有测试文件，随后通过同一账号的公网接口上传合成测试夹具 `fixtures/ios-vps-smoke.txt`。
5. 材料状态由 `processing` 进入 `ready`，提取文本为 468 个字符；iOS 页面刷新后显示“1 份材料已进入项目知识库”和“已完成解析”。
6. 从 iOS 界面调用 DeepSeek 生成材料约束问题；首屏问题引用了测试材料中的端云协同与隐私说明。
7. 在 iOS 界面提交一轮合成文字回答，服务端返回 65 分评价、材料一致性分析、改进建议和连续追问。该分数是测试输入结果，不代表真实用户表现。
8. 强制结束并重新启动应用后，安全存储中的登录状态恢复，项目列表重新从 VPS 返回 1 个项目。
9. Xcode 选择 `Snowball 233 (Personal Team)` 后生成 Apple Development 证书和开发描述文件，Team ID 为 `74NR8F9JK8`。
10. 在 iPhone 15 Pro / iOS 26.3 Beta 上安装并启动签名后的 Profile 应用；`devicectl` 同时确认应用已安装且 Runner 进程处于运行状态，真机登录页正常显示。

## 边界

- iOS 模拟器没有可用摄像头，训练页按预期显示 `CameraException(cameraUnavailable, 未检测到可用摄像头)`；本记录不声称摄像头、录制或麦克风流程已通过。
- 真机目前只完成签名、安装、启动和登录页显示验证；登录、摄像头、麦克风、录制、ASR 与报告闭环仍须单独实测，本记录不提前声明通过。
- 明文 HTTP 仅用于当前 Debug 和专用 Profile 测试产物。正式分发前仍需配置可信 HTTPS，并移除测试产物的任意明文加载放行。
- 测试材料为合成文本，不代表用户访谈、问卷、正式论文或真实训练数据。

## 截图

- [冷启动会话恢复与项目列表](ios-vps-session-restore.png)
- [材料解析完成](ios-vps-material-ready.png)
- [DeepSeek 材料约束问题](ios-vps-ai-jury.png)
- [文字回答评价与连续追问](ios-vps-ai-feedback.png)
- [模拟器摄像头边界](ios-vps-camera-boundary.png)
- [iPhone 15 Pro 真机登录页](ios-device-login.png)
