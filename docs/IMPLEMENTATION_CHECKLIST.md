# SpeechMirror 逐项实施清单

本文件只记录尚未完成或需要现实输入的事项，不纳入竞赛论文。按编号顺序执行；每完成一项，将证据归档后再进入下一项。

## 01. 开发环境与调试界面

- [x] 推送仓库基线到 GitHub `main` 分支。
- [x] 使用 Xcode/iOS Simulator 构建并启动 Flutter 登录页，确认 Xcode Debugger 已附加。
- [x] 安装 Flutter 87.1 与 Dart 251.25410.28 插件，使用 Android Studio Debug 在 `SpeechMirror_QA` 模拟器启动登录页并保存截图。
- [x] 完成注册、登录、令牌刷新、退出撤销与移动端安全存储闭环。
- [x] 完成项目创建、读取、编辑、永久删除及返回列表刷新，并在 Android Studio 与 Xcode 中实测。
- [x] 安装 DevEco Studio 6.0.1 与内置 HarmonyOS 6/API 21 SDK。
- [x] 用 DevEco Studio 从英文仓库路径导入 `apps/harmony`，完成 IDE 同步、ArkTS/C++ 编译并生成首个未签名 HAP。
- [x] 用户确认 HarmonyOS 软件许可协议，下载 HarmonyOS 6.0.1/API 21 手机镜像并创建 `SpeechMirror_Harmony_QA` 模拟器。
- [x] 在 HarmonyOS 6.0.1 模拟器安装并运行 Debug HAP，完成真实登录、项目创建和项目列表回退刷新验证。
- [ ] 配置调试签名，在 HarmonyOS 6 真机安装并运行 HAP。

验收证据：IDE 构建日志、模拟器或真机登录页截图、安装包 SHA-256。

## 02. AI 供应商配置

- [x] 确定 LLM 使用 DeepSeek，VPS 实测模型为 `deepseek-flash`，并与其他AI能力拆分地址和密钥。
- [x] 实测并确定 Embedding 使用 `qwen3.7-text-embedding-flash`、ASR 使用 `qwen3-asr-flash-2026-02-10`、OCR 使用 `qwen3.8-omni-flash`。
- [x] 将凭据写入 VPS 私有 `services/api/.env`，权限为 `600` 且不提交到 Git；本地开发机不保留重复副本。
- [x] 健康接口逐项返回 LLM、Embedding、ASR 和 OCR 为 `true`，四项齐备后总览字段 `ai_configured` 为 `true`。
- [x] 保存一次不含密钥的真实 DeepSeek 调用记录，见 `docs/evidence/ai-jury-question-generation.md`。

验收证据：模型名、调用时间、HTTP 状态、脱敏响应和费用记录。

## 03. 五类材料闭环

- [x] 分别准备 PDF、PPTX、DOCX、TXT/Markdown 和 PNG/JPEG 样本。
- [x] 上传每类材料，确认状态由 `processing` 转为 `ready`。
- [x] 检查提取文本和分块数量是否落库；当前 6 份材料各生成 1 个文本分块。
- [x] 使用阿里云百炼 `qwen3.7-text-embedding-flash` 验证向量生成、SQLite 落库和项目内相似度检索，见 `docs/evidence/embedding-retrieval.md`。
- [x] 使用扫描 PDF 和图片检查本地 OCR 并完成一次文本纠正与重新索引；另实测百炼图片 OCR、分块和向量入库，见 `docs/evidence/ocr-material-ingestion.md`。

验收证据：材料列表截图、提取文本、数据库片段记录和处理日志。

## 04. 一次完整训练

- [ ] 在 iOS 或 Android 设备完成 5 分钟录制。
- [x] 在 Android 15 模拟器完成 28 秒真实录制，确认音频、视频与恢复清单均写入应用沙箱。
- [x] 确认原始视频只保存在手机本地，服务端存储目录没有 MP4/MOV 文件。
- [x] 完成训练历史与趋势页面；无真实报告时仅显示训练记录和明确空态，不生成示例分数。
- [x] 通过训练音频接口上传 7.55 秒合成中文语音，获得真实 ASR 转写并写回训练记录；真机 5 分钟录音仍由本节第一项单独验收。
- [x] 使用合成答辩文本和合成端侧指标生成真实后端报告，核对语速、口头禅、时长、视觉时间线和材料证据，见 `docs/evidence/training-report-generation.md`。
- [ ] 接入带词级或分段时间戳的 ASR 数据后计算并验收长停顿；当前报告明确返回 `null`，不使用无依据的 `0`。
- [ ] 获得至少两份真实报告后，核对时长偏差、口头禅频率、内容和问答四条趋势。
- [x] 音频提交失败后强制结束并冷启动应用，确认本地视频不丢失、待分析状态自动恢复并可重试。

验收证据：本地视频文件信息、转写、报告截图、服务端临时音频清理记录。

## 05. AI 评委闭环

- [x] 从当前项目生成技术、应用、创新、风险和质疑类问题；缺失或无效类别最多定向补问两次。
- [x] 逐条核对 `chunk_id` 和连续原文引文确实属于当前项目，真实响应见 `docs/evidence/ai-jury-question-generation.md`。
- [x] 使用合成文本回答和 10.9985 秒合成中文语音完成真实接口回答；语音经百炼 ASR 转写，临时文件处理后清零，见 `docs/evidence/ai-jury-conversation.md`。
- [x] 完成两轮材料约束评价与连续追问，确认第二轮问题逐字来自首轮 `follow_up`，跨问题复用父回答返回 HTTP 400，问答分同步写入报告。

验收证据：问题、回答、引文、评价 JSON 与界面截图。

## 06. MindSpore Lite 端侧推理

- [ ] 确定有合法来源和授权的 `.ms` 模型。
- [ ] 记录输入尺寸、张量布局、量化方式和四个输出含义。
- [ ] 使用 `SM_WITH_MINDSPORE=ON` 构建 C++ 核心并通过契约测试。
- [ ] 分别完成 Swift、Kotlin/JNI 和 ArkTS/N-API 桥接。
- [ ] 确认只上传派生指标，不上传原始画面。

验收证据：模型授权说明、构建命令、三端日志和结构化指标样例。

## 07. HarmonyOS 6 媒体与系统能力

- [ ] 将 XComponent surface 绑定 CameraKit 前置摄像头。
- [ ] 使用 AVRecorder 把视频保存到应用沙箱。
- [ ] 接入振动超时提醒、报告完成通知和可恢复后台任务。
- [ ] 在 HarmonyOS 6 真机完成登录、材料、录制、报告和评委闭环。

验收证据：HAP、签名信息、设备版本、录屏和完整运行日志。

## 08. 三端性能和能耗

- [ ] 在三台已记录型号与系统版本的设备上运行同一测试材料。
- [ ] 记录抽帧 FPS、P95 推理延迟、峰值内存、15 分钟温升和电量变化。
- [ ] 对异常运行保留日志，不从统计中删除失败样本。

验收证据：原始 CSV、设备截图、日志和统计脚本。

## 09. VPS 和域名部署

- [x] 在 `vastsea` 的 `/home/snowball_233/SpeechMirror` 部署 Axum 调试服务，使用独立端口 `48180` 并通过外部健康检查。
- [ ] 准备域名和 DNS 解析；当前调试端口为 HTTP，不作为最终生产入口。
- [ ] 配置生产环境变量与至少 32 字符的随机 JWT 密钥。
- [ ] 使用 Docker Compose 启动 Axum 与 Caddy，确认 HTTPS 证书正常。
- [ ] 配置 SQLite、材料与日志持久卷，执行一次备份和恢复。

验收证据：脱敏 Compose 配置、HTTPS 健康检查、备份文件和恢复日志。

## 10. 论文与竞赛材料

- [x] 定位方正字库官方下载方案，官方公文写作字体包包含方正小标宋简体与仿宋_GB2312。
- [x] 用户提供方正小标宋简体、仿宋_GB2312和楷体_GB2312字体文件；已核对内部名称并放入Git忽略的本地论文目录。
- [ ] 归档与竞赛论文提交用途相符的字体授权凭证；字体文件不提交到 Git。
- [x] 从 iOS、Android 和 HarmonyOS 模拟器实际运行应用采集无隐私信息截图。
- [ ] 从 HarmonyOS 6 真机采集安装、登录和核心流程截图。
- [ ] 仅将有原始记录的 AI、性能和能耗数据写入论文。
- [ ] 是否进行问卷或用户访谈由参赛要求决定；若开展，必须保留知情同意与匿名原始记录。
- [ ] 在不重复内容、不使用空白页和无意义大图的前提下整理 95 至 105 页终稿。
- [ ] 执行 XeLaTeX、字体嵌入、参考文献、书签与全页 PNG 检查。
- [ ] 按不超过 5 分钟的脚本录制真实演示视频。

验收证据：最终 PDF、全页渲染图、字体清单、引用检查和演示视频。
