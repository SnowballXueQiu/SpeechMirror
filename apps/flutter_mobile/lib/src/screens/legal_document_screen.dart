import 'package:flutter/material.dart';

import '../theme.dart';

enum LegalDocumentType { privacy, terms }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final privacy = type == LegalDocumentType.privacy;
    final sections = privacy ? _privacySections : _termsSections;
    return Scaffold(
      appBar: AppBar(title: Text(privacy ? '隐私政策' : '用户协议')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          children: [
            Text(
              privacy ? '言镜隐私政策' : '言镜用户协议',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '生效日期：2026年9月29日',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 28),
            for (final section in sections) ...[
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                section.body,
                style: const TextStyle(fontSize: 15, height: 1.72),
              ),
              const SizedBox(height: 26),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}

const _privacySections = <_LegalSection>[
  _LegalSection(
    '一、我们处理的信息',
    '为提供账号与跨设备服务，我们处理用户名、加密后的登录凭据、用户ID和令牌。你主动填写时，我们还会处理头像、简介、身份、训练场景和训练目标。为形成训练记录，我们保存项目名称、上传材料、材料解析文本、训练转写、派生表达指标、问答记录和分析报告。',
  ),
  _LegalSection(
    '二、摄像头、麦克风与文件权限',
    '摄像头用于训练画面和端侧姿态、视线等粗粒度判断；麦克风用于录音、语音识别和语音回答；文件权限仅在你选择材料或头像时使用。权限由系统控制，你可以随时在设备设置中关闭，但对应功能可能无法使用。',
  ),
  _LegalSection(
    '三、本地与云端处理',
    '原始训练视频保存在你的设备应用目录，不作为常规数据上传。语音识别所需音频会经加密传输至服务端并交由已配置的语音服务处理，临时音频和解析中间文件按系统清理策略删除，最长保留30分钟。服务器保存转写文本、结构化指标和报告，以便你查看历史结果。',
  ),
  _LegalSection(
    '四、AI服务提供方',
    '材料理解、提问、评价、语音识别或文字识别可能由部署时配置的国产模型服务提供方完成，包括 DeepSeek 或阿里云百炼相关服务。系统仅发送完成相应功能所需的信息。第三方服务的处理同时受其公开规则约束。',
  ),
  _LegalSection(
    '五、产品调研授权',
    '匿名产品调研默认关闭。只有你主动开启后，系统才会汇总使用身份、训练场景和训练目标，用于分析产品人群与功能方向。论文材料、录音、视频、答辩回答和报告内容不在该项授权范围内。你可以在“训练偏好”中随时关闭，关闭不影响核心功能。',
  ),
  _LegalSection(
    '六、保存、安全与删除',
    '我们采用访问令牌、密码哈希、权限校验和传输保护等措施降低未授权访问风险。资料保留至你删除相应项目或账号服务终止；项目删除时同步删除其材料、索引、训练记录和报告。清理缓存只删除设备临时文件，不删除待重试训练和正式项目资料。',
  ),
  _LegalSection(
    '七、你的权利',
    '你可以查看和修改个人资料、撤回调研授权、清理本地缓存，并删除项目及其关联数据。若需处理当前界面未提供的访问、更正或删除请求，可通过 SpeechMirror GitHub 仓库发起联系。为保护账号安全，我们可能需要先核验身份。',
  ),
  _LegalSection(
    '八、未成年人保护与政策更新',
    '未满14周岁的用户应在监护人同意和指导下使用。政策发生重大变化时，我们会通过应用内更新后的文本或必要提示告知；未经新的明确同意，不会扩大可选调研授权的范围。',
  ),
];

const _termsSections = <_LegalSection>[
  _LegalSection(
    '一、服务内容',
    '言镜提供材料整理、模拟陈述、AI评委问答、表达分析和训练历史等辅助功能。具体功能可能随设备能力、网络状态和服务配置而不同。',
  ),
  _LegalSection(
    '二、账号与使用责任',
    '你应妥善保管账号凭据，并对账号内的操作负责。不得利用本服务上传违法内容、侵害他人权利、攻击系统、绕过访问控制或从事其他违反法律法规的行为。',
  ),
  _LegalSection(
    '三、材料权利',
    '你应确保对上传的论文、演示文稿、图片及其他材料具有合法使用权。材料权利仍归原权利人所有；你仅授权系统在提供当前训练功能所必需的范围内处理。',
  ),
  _LegalSection(
    '四、AI结果说明',
    'AI生成的提问、评价和分数用于训练参考，不构成学校、赛事、教师或评审机构的正式意见，也不保证与真实答辩结果一致。模型可能出现遗漏或错误，你应结合原始材料和专业意见判断。',
  ),
  _LegalSection(
    '五、服务可用性',
    '我们会合理维护服务，但网络、设备、模型提供方或维护可能造成延迟或中断。重要材料应由你自行保留备份；在提交或正式答辩前，应自行核验内容准确性。',
  ),
  _LegalSection(
    '六、功能变更与终止',
    '为改善体验、安全或合规要求，功能与规则可能调整。严重违反协议、危害服务安全或侵害他人权益时，相关访问可能被限制。你可以停止使用并删除项目数据。',
  ),
  _LegalSection(
    '七、联系与开源信息',
    '产品问题、数据权利请求和协议意见，可通过 SpeechMirror GitHub 仓库提交。开源组件分别遵循其许可证，本协议不改变第三方软件的授权条款。',
  ),
];
