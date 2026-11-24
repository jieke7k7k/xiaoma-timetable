import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/school_entry.dart';
import 'package:xiaoma_timetable/services/school_catalog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assets/data/schools.json 数据校验', () {
    test('所有条目字段齐全、URL 可解析、无重复 url', () async {
      final rawText = await rootBundle.loadString(
        SchoolCatalogService.defaultAssetPath,
      );
      final decoded = jsonDecode(rawText) as List<dynamic>;
      expect(decoded, isNotEmpty);

      final seenUrls = <String>{};
      for (final item in decoded) {
        expect(item, isA<Map<String, dynamic>>());
        final map = item as Map<String, dynamic>;
        final name = map['name'];
        final url = map['url'];

        expect(name, isA<String>());
        expect((name as String).trim(), isNotEmpty);

        expect(url, isA<String>());
        final trimmedUrl = (url as String).trim();
        expect(trimmedUrl, isNotEmpty);

        final uri = Uri.tryParse(trimmedUrl);
        expect(uri, isNotNull);
        expect(uri!.scheme == 'http' || uri.scheme == 'https', isTrue);
        expect(uri.host, isNotEmpty);

        // 唯一键是 url，不允许重复
        expect(seenUrls.add(trimmedUrl), isTrue, reason: '存在重复 url: $trimmedUrl');
      }
    });
  });

  group('SchoolCatalogService 容错与持久化', () {
    test('JSON 含坏条时不崩，跳过坏条保留有效条', () {
      const brokenJson = '''
      [
        {"name": "浙江师范大学", "url": "https://jwxt.zjnu.edu.cn/"},
        {"name": "缺网址学校"},
        {"name": "坏网址学校", "url": "not-a-valid-url"},
        {"name": "纯HTTP老系统", "url": "http://jwxt.old.edu.cn/", "system": "强智教务"}
      ]
      ''';

      final list = SchoolCatalogService.parseSchoolsJson(brokenJson);
      expect(list.length, 2);
      expect(list[0].name, '浙江师范大学');
      expect(list[1].name, '纯HTTP老系统');
      expect(list[1].system, '强智教务');
    });

    test('JSON 整体损坏时返回空列表不抛异常', () {
      final list = SchoolCatalogService.parseSchoolsJson('{broken json');
      expect(list, isEmpty);
    });

    test('最近使用 url 写入与读取正常', () async {
      final tempDir = await Directory.systemTemp.createTemp('school_picker_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final service = SchoolCatalogService(
        getAppDocDir: () async => tempDir,
      );

      expect(await service.loadLastUsedUrl(), isNull);

      await service.saveLastUsedUrl('https://jwxt.zjnu.edu.cn/');
      expect(await service.loadLastUsedUrl(), 'https://jwxt.zjnu.edu.cn/');
    });
  });

  group('initial 字段与全量资产校验', () {
    test('tryFromJson 解析 initial：合法 A-Z、#、非法值、缺失', () {
      final validAz = SchoolEntry.tryFromJson({
        'name': '浙江师范大学',
        'url': 'https://jwxt.zjnu.edu.cn/',
        'initial': ' z ',
      });
      expect(validAz?.initial, 'Z');

      final validHash = SchoolEntry.tryFromJson({
        'name': '101学院',
        'url': 'https://101.edu.cn/',
        'initial': '#',
      });
      expect(validHash?.initial, '#');

      final invalidValue = SchoolEntry.tryFromJson({
        'name': '坏值学校',
        'url': 'https://bad.edu.cn/',
        'initial': 'AB',
      });
      expect(invalidValue, isNotNull);
      expect(invalidValue!.initial, isNull);

      final missingValue = SchoolEntry.tryFromJson({
        'name': '缺失学校',
        'url': 'https://missing.edu.cn/',
      });
      expect(missingValue, isNotNull);
      expect(missingValue!.initial, isNull);
    });

    test('parseSchoolsJson 按 url 去重仍有效', () {
      const rawJson = '''
      [
        {"name": "学校A", "url": "https://dup.edu.cn/", "initial": "X"},
        {"name": "学校B", "url": "https://dup.edu.cn/", "initial": "X"}
      ]
      ''';
      final parsed = SchoolCatalogService.parseSchoolsJson(rawJson);
      expect(parsed.length, 1);
      expect(parsed.first.name, '学校A');
    });

    test('assets/data/schools.json 每条 initial 合法且浙师大/大连海洋大学正确', () async {
      final service = SchoolCatalogService();
      final schools = await service.loadSchools();
      expect(schools, isNotEmpty);

      final initialPattern = RegExp(r'^[A-Z#]$');
      for (final school in schools) {
        if (school.initial != null) {
          expect(
            initialPattern.hasMatch(school.initial!),
            isTrue,
            reason: '非法 initial: ${school.name} -> ${school.initial}',
          );
        }
      }

      final zjnu = schools.firstWhere(
        (s) => s.url == 'https://jwxt.zjnu.edu.cn/',
      );
      expect(zjnu.initial, 'Z');

      final dlou = schools.firstWhere(
        (s) =>
            s.url ==
            'https://portal.dlou.edu.cn/auth/cas/login?service=https%3A%2F%2Fjwxt.dlou.edu.cn%2Fsso%2Fddlogin',
      );
      expect(dlou.initial, 'D');
    });

    test('大连海洋大学 timeSlots 预设为 12 节且第 3 节 09:50-10:35', () async {
      final service = SchoolCatalogService();
      final schools = await service.loadSchools();
      final dlou = schools.firstWhere(
        (s) => s.url.contains('portal.dlou.edu.cn'),
      );
      final slots = dlou.timeSlots;
      expect(slots, isNotNull);
      expect(slots!.length, 12);
      expect(slots[2].section, 3);
      expect(slots[2].startTime, '09:50');
      expect(slots[2].endTime, '10:35');
      expect(slots[11].section, 12);
      expect(slots[11].startTime, '19:45');
      expect(slots[11].endTime, '20:30');
    });
  });
}
