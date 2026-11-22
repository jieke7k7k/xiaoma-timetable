import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/school_entry.dart';
import 'package:xiaoma_timetable/utils/school_sections.dart';

SchoolEntry _makeSchool(String name, String url, {String? initial}) {
  return SchoolEntry(
    name: name,
    url: url,
    initial: initial,
  );
}

void main() {
  group('groupSchoolsByInitial', () {
    test('空列表返回空', () {
      expect(groupSchoolsByInitial(const []), isEmpty);
    });

    test('分组按 A-Z 排序，S 在 Z 前，# 在最后，null 归入 #，组内保持传入顺序', () {
      final schools = [
        _makeSchool('浙江大学', 'https://zju.edu.cn', initial: 'Z'),
        _makeSchool('MIT', 'https://mit.edu', initial: null),
        _makeSchool('上海交通大学', 'https://sjtu.edu.cn', initial: 'S'),
        _makeSchool('浙江师范大学', 'https://zjnu.edu.cn', initial: 'Z'),
        _makeSchool('101学院', 'https://101.edu.cn', initial: '#'),
        _makeSchool('四川大学', 'https://scu.edu.cn', initial: 'S'),
      ];

      final sections = groupSchoolsByInitial(schools);
      expect(sections.map((s) => s.letter).toList(), ['S', 'Z', '#']);
      expect(
        sections[0].schools.map((s) => s.name).toList(),
        ['上海交通大学', '四川大学'],
      );
      expect(
        sections[1].schools.map((s) => s.name).toList(),
        ['浙江大学', '浙江师范大学'],
      );
      expect(
        sections[2].schools.map((s) => s.name).toList(),
        ['MIT', '101学院'],
      );
    });
  });

  group('flattenSchoolPickerItems & indexOffsets', () {
    test('含最近使用区 + 两组各两校的 prefix sum 手算核对', () {
      final s1 = _makeSchool('上海交通大学', 'https://sjtu.edu.cn', initial: 'S');
      final s2 = _makeSchool('四川大学', 'https://scu.edu.cn', initial: 'S');
      final z1 = _makeSchool('浙江大学', 'https://zju.edu.cn', initial: 'Z');
      final z2 = _makeSchool('浙江师范大学', 'https://zjnu.edu.cn', initial: 'Z');

      final sections = groupSchoolsByInitial([s1, s2, z1, z2]);
      final items = flattenSchoolPickerItems(
        sections: sections,
        lastUsedSchool: z2,
      );

      // 最近使用区：
      // 0: recentHeader  offset=0.0,   height=28.0
      // 1: recentSchool  offset=28.0,  height=56.0
      // 2: recentDivider offset=84.0,  height=16.0
      // S 组：
      // 3: letterHeader(S) offset=100.0, height=28.0
      // 4: school(s1)      offset=128.0, height=56.0
      // 5: school(s2)      offset=184.0, height=56.0
      // Z 组：
      // 6: letterHeader(Z) offset=240.0, height=28.0
      // 7: school(z1)      offset=268.0, height=56.0
      // 8: school(z2)      offset=324.0, height=56.0
      expect(items.length, 9);
      expect(items[0].type, SchoolPickerListItemType.recentHeader);
      expect(items[0].offset, 0.0);
      expect(items[1].type, SchoolPickerListItemType.recentSchool);
      expect(items[1].offset, 28.0);
      expect(items[2].type, SchoolPickerListItemType.recentDivider);
      expect(items[2].offset, 84.0);
      expect(items[3].type, SchoolPickerListItemType.letterHeader);
      expect(items[3].offset, 100.0);
      expect(items[4].offset, 128.0);
      expect(items[5].offset, 184.0);
      expect(items[6].type, SchoolPickerListItemType.letterHeader);
      expect(items[6].offset, 240.0);
      expect(items[7].offset, 268.0);
      expect(items[8].offset, 324.0);

      final offsets = indexOffsets(items);
      expect(offsets, {'S': 100.0, 'Z': 240.0});
    });

    test('无最近使用区时，不计入 28.0 节头与 16.0 分隔线', () {
      final s1 = _makeSchool('上海交通大学', 'https://sjtu.edu.cn', initial: 'S');
      final s2 = _makeSchool('四川大学', 'https://scu.edu.cn', initial: 'S');
      final z1 = _makeSchool('浙江大学', 'https://zju.edu.cn', initial: 'Z');
      final z2 = _makeSchool('浙江师范大学', 'https://zjnu.edu.cn', initial: 'Z');

      final sections = groupSchoolsByInitial([s1, s2, z1, z2]);
      final items = flattenSchoolPickerItems(
        sections: sections,
        lastUsedSchool: null,
      );

      // S 组：0 (header 28) -> 28 (s1 56) -> 84 (s2 56)
      // Z 组：140 (header 28) -> 168 (z1 56) -> 224 (z2 56)
      expect(items.length, 6);
      expect(items[0].type, SchoolPickerListItemType.letterHeader);
      expect(items[0].offset, 0.0);
      expect(items[3].type, SchoolPickerListItemType.letterHeader);
      expect(items[3].offset, 140.0);

      final offsets = indexOffsets(items);
      expect(offsets, {'S': 0.0, 'Z': 140.0});
    });
  });
}