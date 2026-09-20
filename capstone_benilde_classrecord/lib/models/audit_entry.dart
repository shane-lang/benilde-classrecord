class AuditEntry {
  final int id;
  final String action;
  final String? target;
  final String? oldValue;
  final String? newValue;
  final String by;
  final DateTime at;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.by,
    required this.at,
    this.target,
    this.oldValue,
    this.newValue,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        action: json['action'] as String? ?? '',
        target: json['target'] as String?,
        oldValue: json['oldValue'] as String?,
        newValue: json['newValue'] as String?,
        by: json['by'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  String get change {
    final from = oldValue;
    final to = newValue;
    if (from == null && to == null) return '';
    if (from == null) return to!;
    if (to == null) return '$from → cleared';
    return '$from → $to';
  }
}