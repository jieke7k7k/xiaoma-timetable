# WB_SPEC_260：状态条跑马灯

## 1. 用户原话

- 「这个信息一下子显示不完全，改成滚动的」（2026-11-25，附周视图截图）
- 截图：顶部状态条文字被省略号截断——「正在上课 · 实验室 14:00 - 17:10 | 下一节 药物化学 明天 08…」

## 2. 现状（源码核实）

- `lib/pages/week_view_page.dart` 的 `_ClassFocusBar`（约 :2787–2871，StatelessWidget）。
- 文字由 `focus.current` / `focus.next` 拼成：
  - 上课中：「正在上课 · 摘要 ｜ 下一节 X HH:MM」
  - 课前/课间：「下一节 · 摘要 · 还有多久」
  - 无课：「近期暂无课程」
- 渲染：`Material` + `InkWell`（onTap = 点击回到本周）+ `Row[Icon(16), SizedBox(8), Expanded(Text, fontSize 13, maxLines 1, overflow ellipsis)]`，padding 横 16 纵 7。
- 页面每 30 秒计时器重算重建（`computeClassFocus` 与常驻通知共用）。

## 3. 方案（Neon，2026-11-25，全文见 `~/workspace/goals/app/hidden_files/neon_260_marquee.md`）

新增可复用 widget `MarqueeText`（`lib/widgets/marquee_text.dart`），`_ClassFocusBar` 的 `Expanded` 里把 `Text` 换成它，其余布局与点击事件不动。

机制：

- **溢出判断**：`LayoutBuilder` 取可用宽 + `TextPainter` 实测单行文本宽（`textWidth > maxWidth + 0.5` 才滚动，否则静止 `Text` + ellipsis）。测量后立即 `painter.dispose()`。
- **无缝循环**：不用 `SingleChildScrollView` / `ListView`（避免与外层 `InkWell` 手势竞争、`jumpTo(0)` 掉帧）。`SizedBox` 锁可见区 + `ClipRect` + `OverflowBox(maxWidth: double.infinity)` 摆两份相同文本，中间间隔 `gap`（默认 48.0）；`AnimationController` 以恒定速度（默认 36.0 px/s）驱动 `Transform.translate` 从 0 到 `-cycleWidth`（`cycleWidth = textWidth + gap`），到 1.0 时第二份文本刚好对齐起点，`repeat()` 回 0 无缝衔接。第二份文本包 `ExcludeSemantics`，避免读屏重复播报。
- **30 秒重建保活**：`MarqueeText` 是 `StatefulWidget`，父重建时 State 复用、`didUpdateWidget` 触发。文字未变：`_scheduleSync` 直接返回，动画丝毫不动。文字变了：只标记 `_needsReset = true`（不在 build 里改 controller 值，避免 setState during build），当前帧先以偏移 0 渲染，`addPostFrameCallback` 里把 controller 重置为 0 并按新文本宽重开。
- **点击**：跑马灯只动文字，`InkWell` 在外层，点击回到本周不受影响。
- **无新依赖**：只用 SDK API（`MediaQuery.textScalerOf`、`TextPainter`、`AnimationController`）。

参数：`MarqueeText(text, {style, velocity = 36.0, gap = 48.0})`。本次 `_ClassFocusBar` 用默认速度与间隔，样式沿用原 `TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)`。

不做的：左右边缘渐隐、每轮开始前停顿 1–2 秒（Neon 问要不要加，用户没提，不做）。

## 4. 文件清单

- 新增 `lib/widgets/marquee_text.dart`（Neon 代码原样落盘）。
- 改 `lib/pages/week_view_page.dart`：加 `import '../widgets/marquee_text.dart';`；`_ClassFocusBar` 的 `Expanded(child: Text(...))` 换成 `Expanded(child: MarqueeText(text, style: ...))`。
- 新增 `test/wb260_marquee_test.dart`。

## 5. 测试计划

- 超长文本：给定 300px 宽容器 + 超长文本，断言跑马灯滚动结构出现（`ClipRect` + `OverflowBox`），且静止 `Text` 不再是唯一渲染。
- 短文本：给定 300px 宽容器 + 短文本，断言直接渲染静止 `Text`，无滚动结构。
- 文字变化：先超长文本，pump 后换短文本，断言回到静止渲染，不抛异常。
- 文字不变重建：同一超长文本重建两次，断言动画 controller 不重置（不抛、不闪）。
- 点击：包在 `InkWell` 里点一下，断言 onTap 触发一次。
- 全量回归：`flutter test --no-pub` 全部通过；`flutter analyze` 无新增问题。

## 6. 已知局限

- 速度与间隔是固定值（36 px/s、48 px），未做可配开关；用户后续觉得快/慢再调。
- 跑马灯只处理单行文本；状态条文案本身仍是单行拼接，不扩展。
