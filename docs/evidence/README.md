# SpeechMirror 验证记录

本目录只保存已完成的真实调试证据，不记录待验证结论，不包含测试账号、密码或接口密钥。

## 2026-09-25 Android 账号闭环

- 环境：Android Studio Debug、Flutter 3.35.5、Android 15 / API 35 模拟器 `SpeechMirror_QA`。
- 服务：本地 Axum API 与 SQLite 调试库，健康接口返回 `status: ok`。
- 流程：创建账号成功，退出后回到登录页，使用同一账号重新登录并进入项目列表。
- 异常验证：错误凭据显示中文错误，输入内容保留；最终冷启动和重新登录无 ANR、无异步 `setState` 断言。
- 自动化验证：Rust 7 项测试和 Flutter 7 项测试全部通过，`flutter analyze` 无问题。
- 界面证据：[Android 重新登录后的项目页](android-auth-projects.png)。

## 2026-09-25 Android 项目管理闭环

- 环境：Android Studio Debug、Android 15 / API 35 模拟器 `SpeechMirror_QA`，连接本地 Axum API 与 SQLite 调试库。
- 流程：创建 6 分钟答辩项目，进入详情页，将名称、说明和目标时长编辑为新值，再通过不可撤销确认对话框彻底删除。
- 数据核验：编辑后的 SQLite 记录为 7 分钟；删除完成后 `projects` 表记录数为 0，项目列表同步显示“0 个项目”。
- 回归修复：补充详情页返回后的列表刷新，避免数据库已删除但列表仍显示缓存项目。
- 自动化验证：Rust 8 项测试和 Flutter 9 项测试全部通过，`flutter analyze` 无问题。
- 界面证据：[编辑后的项目详情](android-project-management.png)、[删除后的空项目列表](android-project-deleted.png)。

## 2026-09-25 iOS 项目创建调试

- 环境：Xcode Debug、iOS 26.2 模拟器 `SpeechMirror QA`，调试器状态为 `Running Runner on SpeechMirror QA`。
- 流程：创建本地测试账号后进入项目列表，创建 6 分钟答辩项目并进入项目训练台。
- 构建核验：`flutter build ios --simulator --debug` 通过，生成未签名 Simulator 调试包。
- 界面证据：[Xcode 调试中的 iOS 项目详情](ios-project-management.png)。
