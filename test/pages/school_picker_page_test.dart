import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/school_entry.dart';
import 'package:xiaoma_timetable/pages/school_picker_page.dart';
import 'package:xiaoma_timetable/services/school_catalog_service.dart';
import 'package:xiaoma_timetable/utils/school_sections.dart';
import 'package:xiaoma_timetable/utils/web_schedule_parser.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  final String jsonContent;
  _FakeAssetBundle(this.jsonContent);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => jsonContent;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

/// 不走真实 assets 与磁盘的目录服务替身（供 254 分组测试用）。
class _FakeSchoolCatalogService extends SchoolCatalogService {
  _FakeSchoolCatalogService({
    required this.schools,
    this.lastUsedUrl,
  });

  final List<SchoolEntry> schools;
  String? lastUsedUrl;

  @override
  Future<List<SchoolEntry>> loadSchools({
    String assetPath = SchoolCatalogService.defaultAssetPath,
  }) async =>
      schools;

  @override
  Future<String?> loadLastUsedUrl() async => lastUsedUrl;

  @override
  Future<void> saveLastUsedUrl(String url) async {
    lastUsedUrl = url;
  }
}

List<SchoolEntry> _build30Schools() {
  final list = <SchoolEntry>[];
  for (var i = 1; i <= 15; i++) {
    list.add(
      SchoolEntry(
        name: '安徽学校$i',
        url: 'https://a$i.edu.cn/',
        initial: 'A',
      ),
    );
  }
  for (var i = 1; i <= 10; i++) {
    list.add(
      SchoolEntry(
        name: '浙江学校$i',
        url: 'https://z$i.edu.cn/',
        initial: 'Z',
      ),
    );
  }
  for (var i = 1; i <= 5; i++) {
    list.add(
      SchoolEntry(
        name: '100学院$i',
        url: 'https://h$i.edu.cn/',
        initial: '#',
      ),
    );
  }
  return list;
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

  testWidgets('254：30 所学校分组、索引栏跳转与搜索态隐藏索引栏/最近使用区',
      (tester) async {
    final schools = _build30Schools();
    final service = _FakeSchoolCatalogService(
      schools: schools,
      lastUsedUrl: schools.first.url,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SchoolPickerPage(
          semesterId: 1,
          catalogService: service,
          enableStartDateConfirm: false,
          webImportPageBuilder: (initialUrl) =>
              const Scaffold(body: Text('web')),
        ),
      ),
    );
    await drain(tester);

    // 最近使用与分组内各有一处 (key 区分)
    expect(
      find.byKey(ValueKey('recent_${schools.first.url}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('list_${schools.first.url}')),
      findsOneWidget,
    );

    // 索引栏只显示有学校的字母 (A、Z、#)，不显示 B/C 等；
    // 用 descendant 限定在索引栏内断言，避免列表节头干扰计数。
    final indexBar = find.byKey(const ValueKey('school_index_bar'));
    expect(indexBar, findsOneWidget);
    expect(
      find.descendant(of: indexBar, matching: find.text('A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: indexBar, matching: find.text('Z')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: indexBar, matching: find.text('#')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: indexBar, matching: find.text('B')),
      findsNothing,
    );
    // 初始 Z/# 节头在视口外，全局只剩索引栏里的那一处
    expect(find.text('Z'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);
    expect(find.text('B'), findsNothing);

    // 计算预期的 Z 节头偏移：
    // 最近使用区 28 + 56 + 16 = 100
    // A 组：28 + 15 * 56 = 868
    // Z 节头起始偏移 = 968.0
    final expectedZOffset = kRecentHeaderHeight +
        kSchoolRowHeight +
        kRecentDividerHeight +
        kLetterHeaderHeight +
        15 * kSchoolRowHeight;

    await tester.tap(find.text('Z'));
    await drain(tester);

    final listView = tester.widget<ListView>(find.byType(ListView));
    final controller = listView.controller!;
    final clampedExpected =
        expectedZOffset.clamp(0.0, controller.position.maxScrollExtent);
    expect(controller.offset, closeTo(clampedExpected, 1.0));
    // Z 节头已滚入可见 (此时索引栏 + 列表节头共 2 处)
    expect(find.text('Z'), findsNWidgets(2));
    expect(find.text('浙江学校1'), findsOneWidget);

    // 进入搜索态：隐藏索引栏与最近使用区
    // 注意：搜索框里输入的查询文本本身也会被 find.text 命中，
    // 所以断言列表里的那行时要限定在 ListView 内找。
    await tester.enterText(find.byType(TextField), '浙江学校1');
    await drain(tester);

    expect(find.text('★ 最近使用'), findsNothing);
    // 索引栏本身已不在树上：直接断言容器缺失，而非某个字母缺失——
    // 后者在搜索态下恒真（过滤结果里本来就没有那个字母）。
    expect(find.byKey(const ValueKey('school_index_bar')), findsNothing);
    expect(find.text('Z'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('浙江学校1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('259：按住索引栏拖动快速选择，气泡显示与松手消失', (tester) async {
    final schools = _build30Schools();
    final service = _FakeSchoolCatalogService(
      schools: schools,
      lastUsedUrl: schools.first.url,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolPickerPage(
          semesterId: 1,
          catalogService: service,
          enableStartDateConfirm: false,
          webImportPageBuilder: (initialUrl) =>
              const Scaffold(body: Text('web')),
        ),
      ),
    );
    await drain(tester);

    final indexBar = find.byKey(const ValueKey('school_index_bar'));
    expect(indexBar, findsOneWidget);

    final aFinder = find.descendant(of: indexBar, matching: find.text('A'));
    final zFinder = find.descendant(of: indexBar, matching: find.text('Z'));
    expect(aFinder, findsOneWidget);
    expect(zFinder, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(aFinder));
    await tester.pump();
    // 按下即跳 A 组，气泡显示 A
    expect(find.text('A'), findsWidgets);

    await gesture.moveTo(tester.getCenter(zFinder));
    await tester.pump();

    final controller = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    final expectedZOffset = kRecentHeaderHeight +
        kSchoolRowHeight +
        kRecentDividerHeight +
        kLetterHeaderHeight +
        15 * kSchoolRowHeight;
    final clampedExpected =
        expectedZOffset.clamp(0.0, controller.position.maxScrollExtent);
    expect(controller.offset, closeTo(clampedExpected, 1.0));

    // 气泡显示 Z（按 key 定位气泡容器，避免 IgnorePointer 祖先误匹配列表节头）
    final bubble = find.byKey(const ValueKey('school_index_bubble'));
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.text('Z')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump();
    // 松手后气泡消失
    expect(find.byKey(const ValueKey('school_index_bubble')), findsNothing);
  });

  testWidgets('259：拖到索引栏底部之外不崩，停在最后一个字母', (tester) async {
    final schools = _build30Schools();
    final service = _FakeSchoolCatalogService(
      schools: schools,
      lastUsedUrl: schools.first.url,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolPickerPage(
          semesterId: 1,
          catalogService: service,
          enableStartDateConfirm: false,
          webImportPageBuilder: (initialUrl) =>
              const Scaffold(body: Text('web')),
        ),
      ),
    );
    await drain(tester);

    final indexBar = find.byKey(const ValueKey('school_index_bar'));
    final aFinder = find.descendant(of: indexBar, matching: find.text('A'));
    final barRect = tester.getRect(indexBar);

    final gesture = await tester.startGesture(tester.getCenter(aFinder));
    await tester.pump();

    // 拖到栏底下方（超出 Column 范围）
    await gesture.moveTo(Offset(barRect.center.dx, barRect.bottom + 200));
    await tester.pump();

    // 触点 clamp 到最后一个字母 #：气泡显示 #（按 key 定位）
    final bubble = find.byKey(const ValueKey('school_index_bubble'));
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.text('#')),
      findsOneWidget,
    );

    final controller = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    // 最后一组已到达：# 节头滚入可见（限定在 ListView 内找，栏内 # 与气泡 # 不计）。
    // 注意：不直接断言 offset == maxScrollExtent——jumpTo 按
    // SliverChildBuilderDelegate 的预估 maxScrollExtent 做 clamp，
    // 该预估在列表未全量布局时偏小（本用例里跳 # 时按 1381 落点，
    // 随后才收敛到 1445），这是 _jumpToLetter 原有行为，259 未改；
    // 拖到 # 能看到 # 组即满足需求。
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('#'),
      ),
      findsOneWidget,
    );
    expect(controller.offset, greaterThan(0));

    await gesture.up();
    await tester.pump();
  });
}
