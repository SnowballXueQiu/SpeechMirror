class Project {
  const Project({
    required this.id,
    required this.name,
    required this.durationSeconds,
    this.description,
  });
  final String id;
  final String name;
  final String? description;
  final int durationSeconds;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    durationSeconds: json['defense_duration_seconds'] as int? ?? 300,
  );
}

class ProjectDocument {
  const ProjectDocument({
    required this.id,
    required this.filename,
    required this.status,
    required this.mediaType,
    this.error,
    this.text,
  });
  final String id;
  final String filename;
  final String status;
  final String mediaType;
  final String? error;
  final String? text;

  factory ProjectDocument.fromJson(Map<String, dynamic> json) =>
      ProjectDocument(
        id: json['id'] as String,
        filename: json['filename'] as String,
        status: json['status'] as String,
        mediaType: json['media_type'] as String,
        error: json['error'] as String?,
        text: json['extracted_text'] as String?,
      );
}

class RehearsalSession {
  const RehearsalSession({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.targetSeconds,
    this.actualSeconds,
    this.transcript,
    this.createdAt,
    this.completedAt,
  });
  final String id;
  final String projectId;
  final String title;
  final String status;
  final int targetSeconds;
  final int? actualSeconds;
  final String? transcript;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory RehearsalSession.fromJson(Map<String, dynamic> json) =>
      RehearsalSession(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        targetSeconds: json['target_seconds'] as int,
        actualSeconds: json['actual_seconds'] as int?,
        transcript: json['transcript'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      );
}

class TrainingTrendPoint {
  const TrainingTrendPoint({
    required this.sessionId,
    required this.createdAt,
    required this.targetSeconds,
    required this.actualSeconds,
    required this.durationDeviationSeconds,
    required this.charactersPerMinute,
    required this.fillerCount,
    required this.fillerPerMinute,
    this.deliveryScore,
    this.timingScore,
    this.visualScore,
    this.contentScore,
    this.qaScore,
  });

  final String sessionId;
  final DateTime createdAt;
  final int targetSeconds;
  final int actualSeconds;
  final int durationDeviationSeconds;
  final double charactersPerMinute;
  final int fillerCount;
  final double fillerPerMinute;
  final int? deliveryScore;
  final int? timingScore;
  final int? visualScore;
  final int? contentScore;
  final int? qaScore;

  factory TrainingTrendPoint.fromJson(Map<String, dynamic> json) =>
      TrainingTrendPoint(
        sessionId: json['session_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        targetSeconds: json['target_seconds'] as int,
        actualSeconds: json['actual_seconds'] as int,
        durationDeviationSeconds: json['duration_deviation_seconds'] as int,
        charactersPerMinute: (json['characters_per_minute'] as num).toDouble(),
        fillerCount: json['filler_count'] as int,
        fillerPerMinute: (json['filler_per_minute'] as num).toDouble(),
        deliveryScore: json['delivery_score'] as int?,
        timingScore: json['timing_score'] as int?,
        visualScore: json['visual_score'] as int?,
        contentScore: json['content_score'] as int?,
        qaScore: json['qa_score'] as int?,
      );
}

class TrainingTrends {
  const TrainingTrends({required this.projectId, required this.points});

  final String projectId;
  final List<TrainingTrendPoint> points;

  factory TrainingTrends.fromJson(Map<String, dynamic> json) => TrainingTrends(
    projectId: json['project_id'] as String,
    points: (json['points'] as List<dynamic>? ?? const [])
        .map(
          (item) => TrainingTrendPoint.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );
}

class DimensionReport {
  const DimensionReport({
    required this.score,
    required this.summary,
    this.evidence = const [],
  });
  final int? score;
  final String summary;
  final List<EvidenceRef> evidence;

  factory DimensionReport.fromJson(Map<String, dynamic> json) =>
      DimensionReport(
        score: json['score'] as int?,
        summary: json['summary'] as String? ?? '',
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .map((item) => EvidenceRef.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class EvidenceRef {
  const EvidenceRef({required this.chunkId, required this.quote});
  final String chunkId;
  final String quote;

  factory EvidenceRef.fromJson(Map<String, dynamic> json) => EvidenceRef(
    chunkId: json['chunk_id'] as String? ?? '',
    quote: json['quote'] as String? ?? '',
  );
}

class RehearsalReport {
  const RehearsalReport({
    required this.sessionId,
    required this.actualSeconds,
    required this.characterCount,
    required this.charactersPerMinute,
    required this.fillerCounts,
    this.longPauseCount,
    required this.content,
    required this.delivery,
    required this.timing,
    required this.visual,
    required this.qa,
    required this.suggestions,
    required this.timeline,
    this.modelConfidence,
  });
  final String sessionId;
  final int actualSeconds;
  final int characterCount;
  final double charactersPerMinute;
  final Map<String, int> fillerCounts;
  final int? longPauseCount;
  final DimensionReport content;
  final DimensionReport delivery;
  final DimensionReport timing;
  final DimensionReport visual;
  final DimensionReport qa;
  final List<String> suggestions;
  final List<Map<String, dynamic>> timeline;
  final double? modelConfidence;

  factory RehearsalReport.fromJson(Map<String, dynamic> envelope) {
    final json = envelope['report'] as Map<String, dynamic>;
    return RehearsalReport(
      sessionId: json['session_id'] as String,
      actualSeconds: json['actual_seconds'] as int? ?? 0,
      characterCount: json['character_count'] as int? ?? 0,
      charactersPerMinute:
          (json['characters_per_minute'] as num?)?.toDouble() ?? 0,
      fillerCounts: (json['filler_counts'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, (value as num).toInt())),
      longPauseCount: (json['long_pause_count'] as num?)?.toInt(),
      content: DimensionReport.fromJson(
        json['content'] as Map<String, dynamic>,
      ),
      delivery: DimensionReport.fromJson(
        json['delivery'] as Map<String, dynamic>,
      ),
      timing: DimensionReport.fromJson(json['timing'] as Map<String, dynamic>),
      visual: DimensionReport.fromJson(json['visual'] as Map<String, dynamic>),
      qa: DimensionReport.fromJson(json['qa'] as Map<String, dynamic>),
      suggestions: (json['suggestions'] as List<dynamic>? ?? const [])
          .cast<String>(),
      timeline: (json['timeline'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      modelConfidence: (json['model_confidence'] as num?)?.toDouble(),
    );
  }
}

class JuryQuestion {
  const JuryQuestion({
    required this.id,
    required this.category,
    required this.question,
    this.sessionId,
    this.evidence = const [],
  });
  final String id;
  final String category;
  final String question;
  final String? sessionId;
  final List<EvidenceRef> evidence;

  factory JuryQuestion.fromJson(Map<String, dynamic> json) => JuryQuestion(
    id: json['id'] as String,
    category: json['category'] as String,
    question: json['question'] as String,
    sessionId: json['session_id'] as String?,
    evidence: (json['evidence'] as List<dynamic>? ?? const [])
        .map((item) => EvidenceRef.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class JuryAnswer {
  const JuryAnswer({
    required this.id,
    required this.questionId,
    required this.sessionId,
    required this.askedQuestion,
    required this.answerText,
    required this.evaluation,
    this.parentAnswerId,
  });

  final String id;
  final String questionId;
  final String sessionId;
  final String askedQuestion;
  final String? parentAnswerId;
  final String answerText;
  final Map<String, dynamic> evaluation;

  String? get followUp {
    final value = (evaluation['follow_up'] as String?)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  factory JuryAnswer.fromJson(Map<String, dynamic> json) => JuryAnswer(
    id: json['id'] as String,
    questionId: json['question_id'] as String,
    sessionId: json['session_id'] as String,
    askedQuestion: json['asked_question'] as String,
    parentAnswerId: json['parent_answer_id'] as String?,
    answerText: json['answer_text'] as String,
    evaluation: Map<String, dynamic>.from(
      json['evaluation'] as Map<String, dynamic>,
    ),
  );
}
