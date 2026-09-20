class ScoreRecord {
  final String studentId;
  final String assessmentId;
  double score;

  ScoreRecord({
    required this.studentId,
    required this.assessmentId,
    required this.score,
  });

  factory ScoreRecord.fromJson(Map<String, dynamic> json) => ScoreRecord(
        studentId: '${json['enrollmentId']}',
        assessmentId: '${json['assessmentId']}',
        score: (json['score'] as num?)?.toDouble() ?? 0,
      );
}