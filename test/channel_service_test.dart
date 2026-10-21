import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/services/channel_service.dart';

/// 公开通道（1.2.4）：channel.json 解析兜底与版本比较
void main() {
  group('parseChannel', () {
    test('完整 JSON 正确解析', () {
      final info = parseChannel('''
{
  "schema": 1,
  "latest": {
    "versionName": "1.2.4",
    "versionCode": 2010,
    "notes": "要点",
    "downloadUrl": "https://example.com/a.apk",
    "releaseUrl": "https://example.com/release"
  },
  "announcements": [
    {"id": "a1", "title": "标题", "body": "正文", "date": "2026-10-21", "level": "important"},
    {"id": "a2", "title": "普通", "body": "正文2", "date": "2026-10-20", "level": "normal"}
  ]
}
''');
      expect(info, isNotNull);
      expect(info!.latest!.versionName, '1.2.4');
      expect(info.latest!.versionCode, 2010);
      expect(info.announcements, hasLength(2));
      expect(info.announcements.first.isImportant, isTrue);
      expect(info.announcements.last.isImportant, isFalse);
    });

    test('字段缺失兜底：无 latest、无 level 的公告不崩', () {
      final info = parseChannel('{"announcements": [{"id": "x"}]}');
      expect(info, isNotNull);
      expect(info!.latest, isNull);
      expect(info.announcements.single.level, 'normal');
      expect(info.announcements.single.title, '');
    });

    test('坏 JSON / 非对象返回 null；无 id 的公告被跳过', () {
      expect(parseChannel('不是 json'), isNull);
      expect(parseChannel('[1,2]'), isNull);
      final info = parseChannel('{"announcements": [{"title": "没id"}, {"id": "ok"}]}');
      expect(info!.announcements, hasLength(1));
    });
  });

  group('hasNewerVersion', () {
    test('按 versionCode 比较', () {
      final info = parseChannel(
          '{"latest": {"versionName": "1.2.4", "versionCode": 2010}}')!;
      expect(hasNewerVersion(info, 2009), isTrue);
      expect(hasNewerVersion(info, 2010), isFalse);
      expect(hasNewerVersion(info, 2011), isFalse);
      expect(hasNewerVersion(parseChannel('{}')!, 1), isFalse);
    });
  });
}
