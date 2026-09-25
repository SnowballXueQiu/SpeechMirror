# SpeechMirror 验证记录

本目录只保存已完成的真实调试证据，不记录待验证结论，不包含测试账号、密码或接口密钥。

## 2026-09-25 Android 账号闭环

- 环境：Android Studio Debug、Flutter 3.35.5、Android 15 / API 35 模拟器 `SpeechMirror_QA`。
- 服务：本地 Axum API 与 SQLite 调试库，健康接口返回 `status: ok`。
- 流程：创建账号成功，退出后回到登录页，使用同一账号重新登录并进入项目列表。
- 异常验证：错误凭据显示中文错误，输入内容保留；最终冷启动和重新登录无 ANR、无异步 `setState` 断言。
- 自动化验证：Rust 7 项测试和 Flutter 7 项测试全部通过，`flutter analyze` 无问题。
- 界面证据：[Android 重新登录后的项目页](android-auth-projects.png)。
