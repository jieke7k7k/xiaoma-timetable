import '../models/note.dart';

/// 备注常驻通知的文案构建（纯逻辑，不依赖通知插件/数据库）
///
/// 规则（由用户指定）：
/// - 有今天备注 → 显示今天的；同时有明天备注 → 一并带上，每行前缀「明天：」；
/// - 条数多时合并成多行文本（一条一行，交给通知的大文本样式展开）；
/// - 今天明天都没有 → 返回 null，调用方取消这条常驻通知。
///
/// 单独抽成纯函数是为了可测：单测直接喂 [Note] 列表断言文案，
/// 不用碰平台通道（与 reminder_plan / ongoing_notice 同一套路）。
class NoteNotice {
  const NoteNotice({required this.title, required this.text});

  /// 通知标题：今日备注 / 明日备注
  final String title;

  /// 通知正文（多行，'\n' 分隔）
  final String text;
}

/// 本地日期键 yyyy-MM-dd（与 Note.date、小组件 widgetDayKey 同格式）
String noteDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// 构建备注常驻通知；今天与明天都没有备注时返回 null（表示「该取消通知」）。
///
/// [notes] 可以是任意顺序的全部备注，这里只挑今天/明天的；
/// [maxLines] 是行数上限（超过时末尾补「…等 N 条」），防止通知被撑爆——
/// 常驻通知是「瞥一眼」的场景，堆 20 行没有意义。
NoteNotice? buildNoteNotice({
  required DateTime now,
  required List<Note> notes,
  int maxLines = 8,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final todayKey = noteDayKey(today);
  final tomorrowKey = noteDayKey(today.add(const Duration(days: 1)));

  final todayNotes = <Note>[];
  final tomorrowNotes = <Note>[];
  for (final n in notes) {
    final content = n.content.trim();
    if (content.isEmpty) continue;
    if (n.date == todayKey) {
      todayNotes.add(n);
    } else if (n.date == tomorrowKey) {
      tomorrowNotes.add(n);
    }
  }
  if (todayNotes.isEmpty && tomorrowNotes.isEmpty) return null;

  final all = <String>[
    for (final n in todayNotes) n.content.trim(),
    for (final n in tomorrowNotes) '明天：${n.content.trim()}',
  ];
  final shown = all.take(maxLines).toList();
  if (all.length > maxLines) {
    shown.add('…等 ${all.length - maxLines} 条');
  }
  return NoteNotice(
    title: todayNotes.isEmpty ? '明日备注' : '今日备注',
    text: shown.join('\n'),
  );
}
