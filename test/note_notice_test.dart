import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/utils/note_notice.dart';

/// 备注常驻通知文案（纯逻辑）
///
/// 规则：今天的备注优先显示；有明天的就一起带上（每行前缀「明天：」）；
/// 今天明天都没有 → null（调用方据此取消通知）。
void main() {
  final now = DateTime(2026, 10, 22, 15, 30);

  Note note(String date, String content, {int id = 1}) => Note(
        id: id,
        date: date,
        content: content,
        createdAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      );

  test('只有今天备注：标题「今日备注」，正文就是内容', () {
    final n = buildNoteNotice(
      now: now,
      notes: [note('2026-10-22', '下午交实验报告')],
    );
    expect(n, isNotNull);
    expect(n!.title, '今日备注');
    expect(n.text, '下午交实验报告');
  });

  test('今天多条：每行一条，合并成多行文本', () {
    final n = buildNoteNotice(
      now: now,
      notes: [
        note('2026-10-22', '带实验服'),
        note('2026-10-22', '交作业'),
      ],
    );
    expect(n!.text, '带实验服\n交作业');
  });

  test('今天 + 明天：明天的行带「明天：」前缀', () {
    final n = buildNoteNotice(
      now: now,
      notes: [
        note('2026-10-22', '今天的事'),
        note('2026-10-23', '明天的事'),
      ],
    );
    expect(n!.title, '今日备注');
    expect(n.text, '今天的事\n明天：明天的事');
  });

  test('只有明天备注：标题「明日备注」', () {
    final n = buildNoteNotice(
      now: now,
      notes: [note('2026-10-23', '明天带课本')],
    );
    expect(n!.title, '明日备注');
    expect(n.text, '明天：明天带课本');
  });

  test('今天明天都没有 → 返回 null（通知该取消）', () {
    expect(
      buildNoteNotice(
        now: now,
        notes: [
          note('2026-10-21', '昨天的事'),
          note('2026-10-25', '后天的事'),
        ],
      ),
      isNull,
    );
  });

  test('空内容备注被忽略；跨天（23:59）时明天仍按本地日期算', () {
    expect(buildNoteNotice(now: now, notes: [note('2026-10-22', '  ')]), isNull);
    final lateNight = buildNoteNotice(
      now: DateTime(2026, 10, 22, 23, 59),
      notes: [note('2026-10-23', '零点后的备忘')],
    );
    expect(lateNight!.title, '明日备注');
    expect(lateNight.text, '明天：零点后的备忘');
  });

  test('条数超上限时截断并补「…等 N 条」', () {
    final n = buildNoteNotice(
      now: now,
      notes: [
        for (var i = 1; i <= 5; i++) note('2026-10-22', '第$i 条', id: i),
      ],
      maxLines: 3,
    );
    expect(n!.text, '第1 条\n第2 条\n第3 条\n…等 2 条');
  });

  test('noteDayKey 恒为 yyyy-MM-dd（与 Note.date 同格式）', () {
    expect(noteDayKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(noteDayKey(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
