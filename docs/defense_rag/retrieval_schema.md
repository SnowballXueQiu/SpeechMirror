# 双库检索与证据结构

## 运行时上下文

每次生成问题或评价回答时，模型上下文按下面顺序组织：

```text
<competition_criteria>
  作品赛六维评分和本次训练目标
</competition_criteria>
<defense_methodology>
  提问、追问和评分顺序；只作为方法，不作为项目事实
</defense_methodology>
<project_knowledge>
  [chunk_id]
    - 完整材料语义单元
</project_knowledge>
<presentation_transcript>
  本次现场陈述、当前问题、上一轮问题和回答
</presentation_transcript>
```

现在的 SQLite 表仍以 `document_chunks` 保存项目知识，采用向量相似度在单项目范围检索；答辩方法论通过后端共享系统提示词固定注入。这样可以先保证项目事实和规则不混库，后续如果需要管理大量方法论文件，再新增 `methodology_chunks` 表而不改变项目材料表。

## 证据单元

```json
{
  "chunk_id": "原始项目材料片段ID",
  "quote": "材料中的连续原文，优先完整句或连续两句",
  "source_type": "project_knowledge",
  "source_locator": "文档名/页码或段落（可选）"
}
```

模型不得自行填写不存在的 `source_locator`。服务端至少验证 `quote` 是 `chunk.content` 的连续子串，并去重；验证失败的 evidence 会被丢弃并触发保守 fallback。

## 候选问题结构

```json
{
  "category": "技术|应用|创新|风险|质疑",
  "question": "只问一件事，包含项目专有事实",
  "target": "核查的事实或缺口",
  "evidence": [{"chunk_id": "...", "quote": "完整原文"}]
}
```

候选问题必须满足：问题和证据有可解释的关键词联系；不是通用开场问题；没有复用当前场次已经问过的事实；问题长度适合语音朗读。服务器端校验不通过时不保存。

## 回答评价结构

```json
{
  "score": 0,
  "score_band": "严重不足|部分回答|基本合格|较好|优秀",
  "question_target": "本轮真正核查的点",
  "expected_points": ["问题要求回答的事实"],
  "covered_points": ["回答已经覆盖的事实"],
  "missing_points": ["具体遗漏，必须可执行地补救"],
  "unsupported_claims": ["无法从材料定位的说法"],
  "evidence": [{"chunk_id": "...", "quote": "连续原文"}],
  "suggestions": ["针对一个缺口的下一次说法"],
  "follow_up": "首轮最多一个；第二轮为null"
}
```

报告页可以继续使用原有 `evaluation` 扩展字段，不需要破坏客户端；客户端若没有展示新字段，服务端仍会保存并用于总分校准。
