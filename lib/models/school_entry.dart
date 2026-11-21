import 'time_slot.dart';

/// 选校器中的单条学校入口配置
/// 唯一键为 [url]（同一学校本科/研究生入口 name 可相同，靠 url 区分）
class SchoolEntry {
  final String name;
  final String? system;
  final String url;
  final String? note;
  final List<TimeSlot>? timeSlots;

  const SchoolEntry({
    required this.name,
    required this.url,
    this.system,
    this.note,
    this.timeSlots,
  });

  /// 从 JSON Map 解析；必填字段缺失或 url 无法解析时返回 null（调用方静默跳过）
  static SchoolEntry? tryFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;

    final rawName = raw['name'];
    final rawUrl = raw['url'];
    if (rawName is! String || rawUrl is! String) return null;

    final name = rawName.trim();
    final url = rawUrl.trim();
    if (name.isEmpty || url.isEmpty) return null;

    // 不强制 https，允许纯 http，只校验能被正常解析为带 host 的 http/https 地址
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    final rawSystem = raw['system'];
    final system = (rawSystem is String && rawSystem.trim().isNotEmpty)
        ? rawSystem.trim()
        : null;

    final rawNote = raw['note'];
    final note = (rawNote is String && rawNote.trim().isNotEmpty)
        ? rawNote.trim()
        : null;

    final timeSlots = _parseTimeSlots(raw['timeSlots']);

    return SchoolEntry(
      name: name,
      url: url,
      system: system,
      note: note,
      timeSlots: timeSlots,
    );
  }

  /// 解析可选的作息时间列表；格式无效或为空时返回 null
  static List<TimeSlot>? _parseTimeSlots(dynamic raw) {
    if (raw is! List) return null;

    final result = <TimeSlot>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final section = item['section'];
      final startTime = item['startTime'];
      final endTime = item['endTime'];
      if (section is int &&
          section > 0 &&
          startTime is String &&
          startTime.trim().isNotEmpty &&
          endTime is String &&
          endTime.trim().isNotEmpty) {
        result.add(
          TimeSlot(
            section: section,
            startTime: startTime.trim(),
            endTime: endTime.trim(),
          ),
        );
      }
    }
    return result.isEmpty ? null : result;
  }

  /// 行内展示标题：有 note 时拼在括号里（如「浙江师范大学（研究生）」）
  String get displayName => note == null ? name : '$name（$note）';
}
