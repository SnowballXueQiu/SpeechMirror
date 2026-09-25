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
  });
  final String id;
  final String projectId;
  final String title;
  final String status;
  final int targetSeconds;
  final int? actualSeconds;
  final String? transcript;

  factory RehearsalSession.fromJson(Map<String, dynamic> json) =>
      RehearsalSession(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        targetSeconds: json['target_seconds'] as int,
        actualSeconds: json['actual_seconds'] as int?,
        transcript: json['transcript'] as String?,
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
    this.evidence = const [],
  });
  final String id;
  final String category;
  final String question;
  final List<EvidenceRef> evidence;

  factory JuryQuestion.fromJson(Map<String, dynamic> json) => JuryQuestion(
    id: json['id'] as String,
    category: json['category'] as String,
    question: json['question'] as String,
    evidence: (json['evidence'] as List<dynamic>? ?? const [])
        .map((item) => EvidenceRef.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}
