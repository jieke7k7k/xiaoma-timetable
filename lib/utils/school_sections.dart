import 'package:xiaoma_timetable/models/school_entry.dart';

/// 选校器拍平列表各条目固定高度（与渲染强约束 100% 对齐）。
const double kRecentHeaderHeight = 28.0;
const double kSchoolRowHeight = 56.0;
const double kRecentDividerHeight = 16.0;
const double kLetterHeaderHeight = 28.0;

/// 按首字母分组后的单个分组。
class SchoolSection {
  const SchoolSection({
    required this.letter,
    required this.schools,
  });

  final String letter;
  final List<SchoolEntry> schools;
}

/// 拍平列表条目类型。
enum SchoolPickerListItemType {
  recentHeader,
  recentSchool,
  recentDivider,
  letterHeader,
  school,
}

/// 拍平后的单个列表条目，携带固定高度与起始偏移（prefix sum）。
class SchoolPickerListItem {
  const SchoolPickerListItem({
    required this.type,
    required this.height,
    required this.offset,
    this.letter,
    this.school,
  });

  final SchoolPickerListItemType type;
  final double height;
  final double offset;
  final String? letter;
  final SchoolEntry? school;
}

/// 按 initial 分组：
/// - initial 为 null 时归入 "#"；
/// - 组按 A-Z 排序，"#" 组在最后；
/// - 组内保持传入顺序；
/// - 空列表返回空。
List<SchoolSection> groupSchoolsByInitial(List<SchoolEntry> schools) {
  if (schools.isEmpty) {
    return const [];
  }

  final Map<String, List<SchoolEntry>> buckets = {};
  for (final school in schools) {
    final key = school.initial ?? '#';
    buckets.putIfAbsent(key, () => <SchoolEntry>[]).add(school);
  }

  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a == '#' && b == '#') return 0;
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });

  return keys
      .map((letter) => SchoolSection(
            letter: letter,
            schools: List<SchoolEntry>.unmodifiable(buckets[letter]!),
          ))
      .toList(growable: false);
}

/// 将最近使用区（可选）与字母分组拍平为带起始偏移的列表。
List<SchoolPickerListItem> flattenSchoolPickerItems({
  required List<SchoolSection> sections,
  SchoolEntry? lastUsedSchool,
}) {
  final items = <SchoolPickerListItem>[];
  double currentOffset = 0.0;

  if (lastUsedSchool != null) {
    items.add(
      SchoolPickerListItem(
        type: SchoolPickerListItemType.recentHeader,
        height: kRecentHeaderHeight,
        offset: currentOffset,
      ),
    );
    currentOffset += kRecentHeaderHeight;

    items.add(
      SchoolPickerListItem(
        type: SchoolPickerListItemType.recentSchool,
        height: kSchoolRowHeight,
        offset: currentOffset,
        school: lastUsedSchool,
      ),
    );
    currentOffset += kSchoolRowHeight;

    items.add(
      SchoolPickerListItem(
        type: SchoolPickerListItemType.recentDivider,
        height: kRecentDividerHeight,
        offset: currentOffset,
      ),
    );
    currentOffset += kRecentDividerHeight;
  }

  for (final section in sections) {
    items.add(
      SchoolPickerListItem(
        type: SchoolPickerListItemType.letterHeader,
        height: kLetterHeaderHeight,
        offset: currentOffset,
        letter: section.letter,
      ),
    );
    currentOffset += kLetterHeaderHeight;

    for (final school in section.schools) {
      items.add(
        SchoolPickerListItem(
          type: SchoolPickerListItemType.school,
          height: kSchoolRowHeight,
          offset: currentOffset,
          school: school,
        ),
      );
      currentOffset += kSchoolRowHeight;
    }
  }

  return items;
}

/// 提取每个字母节头的起始偏移（仅含字母节头）。
Map<String, double> indexOffsets(List<SchoolPickerListItem> items) {
  final offsets = <String, double>{};
  for (final item in items) {
    if (item.type == SchoolPickerListItemType.letterHeader &&
        item.letter != null) {
      offsets[item.letter!] = item.offset;
    }
  }
  return offsets;
}