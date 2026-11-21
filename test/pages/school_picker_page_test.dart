import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/school_picker_page.dart';
import 'package:xiaoma_timetable/services/school_catalog_service.dart';
import 'package:xiaoma_timetable/utils/web_schedule_parser.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  final String jsonContent;
  _FakeAssetBundle(this.jsonContent);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => jsonContent;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  const sampleJson = '''
  [
    {"name": "浙江师范大学", "url": "https://jwxt.zjnu.edu.cn/", "system": null},
    {"name": "示例科技大学", "url": "https://jwxt.demo.edu.cn/", "system": "正方教务"}
  ]
  ''';

  /// wb231 同款手动泵法：先给真实异步留窗口，再逐帧 pump。
  /// 注意：结尾不用 pumpAndSettle——enterText 后搜索框获得焦点，
  /// 光标闪烁动画会让 pumpAndSettle 永远等不到 settle。
  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();
  }

  Future<SchoolCatalogService> buildService(Directory tempDir) async {
    return SchoolCatalogService(
      bundle: _FakeAssetBundle(sampleJson),
      getAppDocDir: () async => tempDir,
    );
  }

  testWidgets('选校器：搜索过滤、搜索态隐藏最近使用、无结果空态、手动行存在', (tester) async {
    // testWidgets 里真实 IO 必须走 runAsync，直接 await 会卡死（假时钟不驱动真实事件循环）。
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('picker_widget_test'),
    ))!;
    addTearDown(() => tempDir.delete(recursive: true));

    final service = await buildService(tempDir);
    await tester.runAsync(
      () => service.saveLastUsedUrl('https://jwxt.zjnu.edu.cn/'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchoolPickerPage(
          semesterId: 1,
          catalogService: service,
          enableStartDateConfirm: false,
        ),
      ),
    );
    await drain(tester);

    // 最近使用置顶，且下方列表仍保留该校
    expect(find.text('★ 最近使用'), findsOneWidget);
    expect(find.text('浙江师范大学'), findsNWidgets(2));
    expect(find.text('示例科技大学'), findsOneWidget);
    expect(find.text('正方教务'), findsOneWidget);
    expect(find.text('不在列表里？手动输入教务网址'), findsOneWidget);

    // 搜索过滤：隐藏最近使用，只剩匹配项
    await tester.enterText(find.byType(TextField), '示例');
    await drain(tester);
    expect(find.text('★ 最近使用'), findsNothing);
    expect(find.text('示例科技大学'), findsOneWidget);
    expect(find.text('浙江师范大学'), findsNothing);

    // 无结果空态
    await tester.enterText(find.byType(TextField), '不存在的大学');
    await drain(tester);
    expect(find.text('没找到这所学校，试试手动输入网址'), findsOneWidget);
  });

  testWidgets('选校器：点选学校链式进入并回传结果', (tester) async {
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('picker_pop_test'),
    ))!;
    addTearDown(() => tempDir.delete(recursive: true));

    final service = await buildService(tempDir);
    String? receivedUrl;
    SchoolWebImportResult? poppedResult;

    // WebScheduleResult 是位置参数 (courses, errors)
    final fakeSchedule = WebScheduleResult(const [], const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                poppedResult = await Navigator.of(context)
                    .push<SchoolWebImportResult>(
                  MaterialPageRoute(
                    builder: (_) => SchoolPickerPage(
                      semesterId: 1,
                      catalogService: service,
                      enableStartDateConfirm: false,
                      webImportPageBuilder: (initialUrl) {
                        receivedUrl = initialUrl;
                        return Scaffold(
                          body: ElevatedButton(
                            onPressed: () =>
                                Navigator.of(context).pop(fakeSchedule),
                            child: const Text('模拟导入完成'),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              child: const Text('打开选校器'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选校器'));
    await drain(tester);

    await tester.tap(find.text('浙江师范大学'));
    await drain(tester);

    expect(receivedUrl, 'https://jwxt.zjnu.edu.cn/');

    await tester.tap(find.text('模拟导入完成'));
    await drain(tester);

    expect(poppedResult, isNotNull);
    expect(poppedResult!.school?.name, '浙江师范大学');
    expect(poppedResult!.scheduleResult, same(fakeSchedule));
  });
}
