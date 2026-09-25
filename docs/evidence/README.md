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

## 2026-09-25 五类材料导入与解析闭环

- 环境：本地 Axum API、SQLite 调试库、Poppler、LibreOffice 和 Tesseract；Android Studio Debug 与 Xcode Debug 分别连接 Android 15 和 iOS 26.2 模拟器。
- 样本：Markdown、PDF、DOCX、PPTX、PNG 图片和扫描 PDF 共 6 份；全部状态由 `processing` 进入 `ready`。
- 安全校验：服务端联合检查扩展名、MIME、文件特征及 OOXML ZIP 结构；将普通文本伪装为 PDF 上传时返回 HTTP 400。
- 数据核验：6 份材料均提取出非空文本，并各生成 1 个数据库分块；图片和扫描 PDF 均通过本地 OCR 获得文本。
- 校对核验：在材料文本页修改图片识别结果并保存，旧分块被替换，材料重新进入 `ready`。
- 未验证边界：健康接口为 `ai_configured: false`，6 个分块的向量均为空，因此本记录不声称 Embedding 或相似度检索已验证。
- 自动化验证：Rust 10 项测试和 Flutter 10 项测试全部通过，`flutter analyze` 无问题，OpenAPI YAML 可解析。
- 构建验证：Android Debug APK SHA-256 为 `704e177823809c37f9de2e485621d8a150acc37a634cf6d63dbe83886c6b4d6d`；iOS Simulator Debug ZIP SHA-256 为 `34688c4ccacb1048df39fbe81c85bb3aca973f1d22871a69f7acc119500f94f3`。
- Android 证据：[材料列表](android-material-processing.png)、[材料文本校对](android-material-text.png)、[Android Studio 调试器](android-studio-material-debug.png)。
- iOS 证据：[材料列表](ios-material-processing.png)、[扫描 PDF OCR 文本](ios-material-text.png)、[Xcode 调试器](xcode-material-debug.png)。

## 2026-09-25 Android 录制失败恢复闭环

- 环境：Android 15 / API 35 模拟器 `SpeechMirror_QA`，安装最新 Debug APK，摄像头使用模拟器虚拟场景。
- 流程：完成 28 秒摄像头与麦克风真实录制；音频提交返回网络请求失败后，页面保留待分析状态与重试入口。
- 本地文件：应用沙箱内音频为 464291 字节、视频为 881187 字节，恢复清单为 442 字节；清单记录会话、时长和本地文件引用，不包含账号或令牌。
- 冷启动核验：强制结束并重新启动应用后，再次进入同一项目训练页，自动恢复 28 秒待分析记录并显示“继续生成报告”。
- 隐私核验：本地服务端存储目录中 MP4/MOV 文件数为 0，原始视频未上传。
- 未验证边界：健康接口仍为 `ai_configured: false`，本次没有取得 ASR 转写或训练报告，不将恢复能力表述为完整训练闭环。
- 自动化验证：Flutter 11 项测试全部通过，`flutter analyze` 无问题。
- 构建验证：Android Debug APK SHA-256 为 `6c0d1e66b39f410c5e5dda1a384cd2866807554ba2d22b255f7f6138e5a5d2d2`；iOS Simulator Debug ZIP SHA-256 为 `4056437f77c92a8d4d5ce4354962c1fb5cd887b74dc85e570c16397d1ad24d2d`。
- 界面证据：[录制中](android-training-recording.png)、[提交失败后保留](android-training-pending.png)、[冷启动后恢复](android-training-recovered.png)。
