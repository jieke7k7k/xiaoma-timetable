import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
