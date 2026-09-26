# SpeechMirror 验证记录

本目录只保存已完成的真实调试证据，不记录待验证结论，不包含测试账号、密码或接口密钥。

## 2026-09-26 iOS 公网包、界面回归与真机签名

- 环境：Flutter 3.35.5、Xcode 26.2、iOS 26.2 模拟器 `SpeechMirror QA`，以及 iPhone 15 Pro / iOS 26.3 Beta 真机。
- 流程：真实登录、创建项目、材料进入知识库、DeepSeek 生成问题、提交文字回答、返回评价和连续追问，并在冷启动后恢复登录状态。
- 构建隔离：仅 Debug 使用独立 ATS 明文 HTTP 放行；Release 与 Profile 未放行任意 HTTP。
- 产物：Simulator Debug ZIP、iPhoneOS Debug 未签名 ZIP 和 iPhoneOS Profile 公网测试签名 ZIP 均已生成并记录 SHA-256。
- 真机结果：Personal Team 自动签名成功，应用已安装到 iPhone 并正常显示登录页；标准 Release/Profile 的 ATS 安全配置未放宽。
- 验证边界：模拟器无摄像头，训练页明确返回 `cameraUnavailable`；真机登录、录制、ASR 和报告闭环尚未在本记录中声明通过。
- 完整记录：[iOS 公网包、界面回归与真机签名](ios-vps-debug-package.md)。

## 2026-09-26 AI 评委回答与连续追问闭环

- 数据边界：文本回答和 10.9985 秒中文语音均为合成测试数据，不代表真人回答。
- 流程：从五类材料问题中提交首轮文本回答，再将语音 ASR 结果作为第二轮追问回答；第二轮请求绑定首轮回答 ID。
- 结果：第二轮实际评价的问题与首轮生成的追问逐字一致，两轮材料证据写入问答报告；跨问题父回答被 HTTP 400 拒绝。
- 真实性约束：第二轮合成回答偏离技术追问，真实得分仅 10，记录保留原始低分；处理后临时音频文件数为 0。
- 完整记录：[AI 评委回答与连续追问验证](ai-jury-conversation.md)。

## 2026-09-26 训练报告生成闭环

- 环境：公网 VPS 上的 Axum、SeaORM 与 SQLite 服务，四项 AI 能力健康状态均为 `true`。
- 数据边界：答辩文本与端侧指标均为合成测试数据，不代表真实用户、问卷或真机视觉模型结果。
- 流程：材料上传并向量化后，提交训练文本和三类端侧视觉事件，通过真实 DeepSeek 内容评价生成并持久化报告。
- 结果：报告含 5 条可验证材料证据；语速、口头禅、时长和视觉指标均通过断言；未进行问答时问答分保持为空。
- 真实性约束：ASR 无词级或分段时间戳，长停顿次数明确返回 `null`，不以无依据的 `0` 代替。
- 完整记录：[训练报告生成验证](training-report-generation.md)。

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

## 2026-09-25 Android 训练历史与趋势空态

- 环境：Android 15 / API 35 模拟器 `SpeechMirror_QA`，连接本地 Axum API 与 SQLite 调试库。
- 真实数据：当前项目有 2 条状态为 `recording` 的服务端训练记录，没有持久化训练报告；页面显示 2 次训练、0 次完成、0 份可比较报告。
- 界面核验：四个趋势维度均不填充示例数据，明确显示“暂无可比较报告”；两条训练记录显示服务端已有的创建时间和“尚无时长”。
- 接口实现：趋势点只从已经持久化的报告生成，包含时长偏差、每分钟口头禅次数、内容分和问答分；问答或视觉数据缺失时保留为空值。
- 测试边界：指标切换、趋势图和报告跳转由合成测试夹具覆盖，不把这些测试值作为真实用户结果；真实趋势图仍需等待至少两份真实 ASR 报告。
- 自动化验证：Rust 12 项测试和 Flutter 14 项测试全部通过，`flutter analyze` 无问题，OpenAPI YAML 可解析。
- 构建验证：Android Debug APK SHA-256 为 `7dd9b71d336d27476ff6646e3d9d0ea56651f18a7864305b2ec29739450db069`；iOS Simulator Debug ZIP SHA-256 为 `51c5c1670a3efc8d9b2d651e85f40620676ab1cd78a84c57d6790e88ab6ddab4`。iOS 构建在不含全角括号的临时路径完成，以规避 CocoaPods 1.16.2 对当前中文项目路径执行 NFKC 规范化的问题。
- 界面证据：[训练历史与真实空态](android-training-history-empty.png)。

## 2026-09-25 HarmonyOS 6 工程导入与首个 HAP

- 路径修复：仓库目录已从中文竞赛名称改为 `SpeechMirror`，消除 Hvigor 与 CocoaPods 对中文及全角字符路径的兼容问题。
- 环境：DevEco Studio `6.0.1.251`，IDE 内置 HarmonyOS SDK `6.0.1.112`、API 21；项目 `compatibleSdkVersion` 与 `targetSdkVersion` 均为 `6.0.0(20)`。
- IDE 核验：Ohpm Install、Build Init 与 `entry:compileNative` 均显示 successful，原生编译日志以 exit code 0 结束。
- 构建核验：正式仓库路径下执行干净构建成功，ArkTS 生成 `ets/modules.abc`，原生层生成 `libs/arm64-v8a/libspeechmirror_edge_napi.so`。
- 产物：`output/harmony/SpeechMirror-debug-unsigned.hap`，SHA-256 为 `54bb76862e67400a52ecffe26ca4172e64c3f9d8e38ec24dd7163b341272ae76`。
- 当时的验证边界：该提交只完成未签名 HAP 构建；后续模拟器运行结果见下一节。

## 2026-09-25 HarmonyOS 6 模拟器账号与项目闭环

- 环境：DevEco Studio `6.0.1.251`、HarmonyOS 6.0.1/API 21 手机镜像，ARM64 模拟器 `SpeechMirror_Harmony_QA`；系统版本命令返回 `emulator 6.0.0.112(SP3DEVC00E112R4P11)`。
- 连接：HDC 目标为 `127.0.0.1:5557`，通过 `rport tcp:8080 tcp:8080` 将模拟器内的 `127.0.0.1:8080` 映射到本机 Axum 服务；服务健康接口返回 `status: ok`。
- 安装：Debug HAP 通过 HDC 安装成功，应用包名为 `cn.speechmirror.harmony`，`EntryAbility` 启动成功。模拟器允许安装未签名调试包，本记录不据此声称真机签名已完成。
- 流程：使用专用测试账号登录本地 Axum/SQLite，项目列表读取成功；在 HarmonyOS 端创建 5 分钟项目并进入详情页，项目说明为“`HarmonyOS 6 端创建`”。
- 回归修复：首次实测发现详情页返回后列表未刷新；将项目列表加载绑定到 `onPageShow` 后重新构建、覆盖安装并复测，返回列表能够显示真实项目卡片。
- 构建核验：Hvigor 类型检查、ArkTS、C++ N-API 与 HAP 打包均通过；最新 `output/harmony/SpeechMirror-debug-unsigned.hap` SHA-256 为 `e34965dab7d2c8c81939f0ae01318bbbc8daeb7976c18fa83705b80243ff92f4`。
- 未验证边界：尚未配置 HarmonyOS 真机调试签名，也未完成真机安装、摄像头录制或 MindSpore Lite 推理，因此不作对应声明。
- 界面证据：[HarmonyOS 6 登录页](harmony-login-screen.png)、[真实登录后的项目列表](harmony-auth-projects.png)。
