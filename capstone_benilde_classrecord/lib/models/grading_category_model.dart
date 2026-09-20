class GradingCategoryModel {
  final String id;
  String name;
  double weight;

  String? parentId;

  final bool isAttendance;

  GradingCategoryModel({
    required this.id,
    required this.name,
    required this.weight,
    this.parentId,
    this.isAttendance = false,
  });

  factory GradingCategoryModel.fromJson(Map<String, dynamic> json) =>
      GradingCategoryModel(
        id: '${json['id']}',
        name: json['name'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0,
        parentId: json['parentId'] == null ? null : '${json['parentId']}',
        isAttendance: json['isAttendance'] as bool? ?? false,
      );

  static List<GradingCategoryModel> listFromJson(List<Map<String, dynamic>> rows) {
    final result = <GradingCategoryModel>[];
    for (final row in rows) {
      result.add(GradingCategoryModel.fromJson(row));
      final children = row['children'];
      if (children is List) {
        for (final child in children.whereType<Map<String, dynamic>>()) {
          result.add(GradingCategoryModel.fromJson(child));
        }
      }
    }
    return result;
  }
}