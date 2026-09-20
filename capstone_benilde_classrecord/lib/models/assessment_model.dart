enum GradingPeriod { prelim, midterm, finals }

class AssessmentModel {
  final String id;
  final String name;
  final String categoryId;
  final GradingPeriod gradingPeriod;
  final double maxScore;

  AssessmentModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.gradingPeriod,
    required this.maxScore,
  });

  factory AssessmentModel.fromJson(Map<String, dynamic> json) => AssessmentModel(
        id: '${json['id']}',
        name: json['name'] as String? ?? '',
        categoryId: '${json['categoryId']}',
        gradingPeriod: _periodFromApi(json['gradingPeriod'] as String?),
        maxScore: (json['maxScore'] as num?)?.toDouble() ?? 100,
      );

  static GradingPeriod _periodFromApi(String? value) => switch (value?.toLowerCase()) {
        'midterm' => GradingPeriod.midterm,
        'finals' => GradingPeriod.finals,
        _ => GradingPeriod.prelim,
      };

  String get periodLabel {
    switch (gradingPeriod) {
      case GradingPeriod.prelim:
        return 'Prelim';
      case GradingPeriod.midterm:
        return 'Midterm';
      case GradingPeriod.finals:
        return 'Finals';
    }
  }
}