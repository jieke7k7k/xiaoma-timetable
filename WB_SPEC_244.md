# WB_SPEC_244：整学期导出按本周导出效果对齐（2.9.1）

## §0 背景

2.9.0（WB_SPEC_243）发版后他真机对比两张导出图：图1 整学期导出 vs 图2 本周导出（第 11 周），风格还是不一样。他要的是图2这种效果。

已读代码核实（2026-11-18 14:0x）：根因不是颜色没对齐——底色已核实是同一 token（`buildAppColorScheme`，App 主题 main.dart:293 与整学期离屏 Overlay 同函数同种子同 `surface`；图1 看着偏白是缺网格线和描边衬出来的）。真正的原因是**本周导出直接复用 App 的 `CourseCard` 和主页网格线画法，整学期导出是手写的一套**（`_SingleMasterCard` + 无网格线），243 只对齐了颜色 token、带子和行数口径，没动卡片和网格。

## §1 差异对照（代码实测，文件均为 lib/pages/share_image_page.dart，除非注明）

| 方面 | 本周导出 `_ExportSheet`（图2） | 整学期导出 `SemesterSingleImageSheet`（图1） |
|---|---|---|
| 课卡 | 直接用 App 的 `CourseCard`（lib/widgets/course_card.dart），`borderWidth: ui.borderWidth`、`cornerRadius: ui.cornerRadius`、`textScale: ui.cardTextScale`、`displayColorValue: mapCourseColor(...)` 全传（_ExportSheet._slotWidget，约 740 行） | 自写 `_SingleMasterCard`（约 1153 行）：**无描边**；圆角走 `ui.cornerRadius` 但无 border |
| 课卡文字 | CourseCard：名 12sp w600、教室/老师 10sp（默认字重）；`maxLines` 单节 4、多节 **8**，长教室自然换行显示全 | _SingleMasterCard：名 10sp w700、教室/老师 8.5sp w500；总行数上限 **4 行**（243 公式：名最多 2 + 教室/老师各 1），长教室截断成「12-分析…」，老师跟着没了 |
| 课卡内边距 | CourseCard：横 6、纵 4 | _SingleMasterCard：横 3、纵 padV（3 / 1.5 / 0.5） |
| 课卡文字色 | CourseCard：`MorandiPalette.textColor` / `subTextColor`（浅字模式走 darkTextColor / darkSubTextColor，按 B4 亮度规则 `cardColor.computeLuminance() < 0.42` 切换） | _SingleMasterCard：`scheme.onSurface` / `onSurfaceVariant`（241 当时按错了参照——周视图卡片走的本就是 Morandi 色，不是 scheme 色） |
| 网格线 | 每节底边通栏横线 + 带子底边线 + 按节次段分段的纵向列线（跳过带子），`outlineVariant` 0.5，与 App 主页 `_FullWidthLinesPainter` / `verticalLineSegments` 同一份口径（_ExportSheet 约 546–590 行） | **没有**通栏横线和纵向列线；只有时间轴列的右/底边框 + 星期表头上下边框，空白格全是底色 |
| 星期表头 | `surfaceContainerLow` 底条；月 + 星期（10sp）+ 日期圆点，今天 primary 色圆点高亮（高 46dp，`kGridHeaderHeight`） | 无底条（透明）；只有「节次」+ 星期名 12sp w600，无日期、无今日高亮（高 34dp，`kWeekBarHeight`） |
| 分隔带高度 | `kBandHeight = 24`（lib/ui/grid_metrics.dart:16） | `kSemesterBandHeight = 20`（本文件约 816 行）——带子比图2 矮 4dp |
| 底色 | `Theme.of(context).colorScheme.surface`（App 主题） | `buildAppColorScheme(seed, light).surface`——**同一 token，颜色本身一样，不动** |
| 标题栏 | 17sp 加粗 + 11sp 日期范围 outline | 同口径（243 已对齐），不动 |

## §2 课卡对齐 CourseCard（改 `_SingleMasterCard`）

**不直接复用 `CourseCard` widget**：`CourseCard` 的 `maxLines` 按课程原始节次算（单节 4、多节 8），不认单双周半格、叠排三分等实际渲染高度；52dp 半格按 8 行排会超出卡高被拦腰切。且周次胶囊要另挂在卡片下方，`CourseCard` 没有胶囊位。做法是**同款渲染、各自预算**：`_SingleMasterCard` 的渲染参数逐项对齐 `CourseCard`，行数仍按卡片实际高度预算。

1. **描边**：照抄 `CourseCard` 的 border 逻辑——`borderWidth > 0 ? BorderSide(color: useLightText ? lightenColor(cardColor) : darkenColor(cardColor), width: borderWidth) : BorderSide.none`，其中 `useLightText = cardColor.computeLuminance() < 0.42`（B4 规则），`borderWidth = ui.borderWidth`（用他界面设置里的值，不硬编码）；`lightenColor` / `darkenColor` 在 lib/utils/color_schemes.dart（本文件已 import）。
2. **字号分档**（`textScale = ui.cardTextScale`，默认 1.0，全档乘它）：
   - `height >= 70`：名 `12 * textScale` w600、教室/老师 `10 * textScale`（默认字重），与 `CourseCard` 同口径；行高名 1.15、元数据 1.1。
   - `40 <= height < 70`：名 10、元数据 8.5（243 口径不动），保 52dp 单双周半格仍显示 3 行。
   - `height < 40`：现状小档（名 8.5 / 7.5，无元数据），不动。
3. **文字色**：与 `CourseCard` 同口径——`MorandiPalette.textColor` / `subTextColor`（浅字模式走 darkTextColor / darkSubTextColor，按 B4 亮度规则切换），不再用 `scheme.onSurface` / `onSurfaceVariant`。胶囊文字色不动（仍走 scheme 色，与 243 一致）。
4. **内边距**：横 6（`CourseCard` 口径）；纵向按高度分档——`height >= 70` 纵 4，`40 <= height < 70` 纵 3（现状 padV），`height < 40` 现状小档（1.5 / 0.5）。（Argon 确认意见 2026-11-18：纵 4 一刀切会挤压 52dp 半格——52−8−11=33dp，对低档 3 行 32.06dp 只剩约 1dp 容错，textScale > 1.0 即掉回 2 行；故低档维持 padV。）
5. **行数预算**：分档算（Argon 确认意见 2026-11-18：原 P0-1 公式用 `.clamp(0, metaLines)` 把元数据行数锁死在字段个数（最多 2），高档卡即使把总上限改成 8 也只能算出 4 行，长教室仍会截掉老师）：
   - **高档（height ≥ 70）**：按可用高度直接预算 `totalMaxLines = (1 + floor((availTextH − nameLineH) / metaLineH)).clamp(1, 8)`，不再用字段个数封顶，让长课名、长教室自然折行。144dp 卡 availTextH = 125dp，算出来 clamp 到 8。
   - **低档（height < 70）**：沿用 243 的 P0-1 结构（课名至少 1 行，剩余高度放元数据行，放不下时老师先被截；胶囊预留 11dp），行高按分档字号再乘 `textScale`（高档名行 `12 * 1.15 * textScale`、元数据行 `10 * 1.1 * textScale`；低档名行 `10 * 1.2 * textScale`、元数据行 `8.5 * 1.18 * textScale`），**总行数上限由 4 改为 8**（`CourseCard` 多节卡口径）。52dp 半格（低档）仍得 3 行，P0-1 测试不断言改。
6. **不动**：周次胶囊（位置、样式、`showCapsule >= 30` 阈值）、`showMeta >= 40` 阈值、卡片配色（`mapCourseColor` 存储色原色）、圆角（`ui.cornerRadius`）。

## §3 网格线（改 `SemesterSingleImageSheet` 的 Stack）

补 `_ExportSheet` 同款，层级在最底层（先画），带子、卡片在上（与 `_ExportSheet` 的 Stack 顺序一致）：

1. **通栏横线**：每节底边一条（`for r in 1..<maxSection`，`top: topOf(r) + kRowHeight`，`left: 0, right: 0, height: 0.5`）+ 每条带子底边一条（`top: topOf(b.after + 1)`），颜色 `scheme.outlineVariant`（不加 alpha，与 `_ExportSheet` 一致）。
2. **纵向列线**：复用 `verticalLineSegments(rowHeight: kRowHeight, sectionCount: maxSection, activeBands: bands)`（与 `_ExportSheet` / 主页共用同一份口径，带子内不画竖线），按列画（`left: kAxisWidth + c * colW`），画在网格区 Stack 内（星期表头下方），`top` 以 `seg.start` 为准（相对于网格区顶部），不穿透表头。（Argon 确认意见：须与 `_ExportSheet` 同锚点；已核实学期图结构是 Column[标题, 星期栏 34dp, 网格区 Stack]，网格区 Stack 在星期栏下方，`topOf`/`bandTop` 均相对于网格区顶部，故按此画法天然不穿透。）
3. **轴列边框同步**：现有时间轴格子的右/底边框改回无 alpha 的 `outlineVariant`（与网格线同口径；现在是 `alpha: 0.5`）。

## §4 表头与带子高度

1. **表头加底条**：星期表头 Container 加 `color: scheme.surfaceContainerLow`（与 `_ExportSheet` 表头同口径）。「节次」与星期名样式不动（12sp w600），高度 34dp 不动（`_ExportSheet` 表头 46dp 是因为有两行星期+日期，学期图一行所以 34dp 保留）。
2. **无日期、无今日高亮**：整学期无单周日期，设计上做不到，不做。
3. **带子高度对齐**：删 `kSemesterBandHeight = 20`，改用 `kBandHeight = 24`；`topOf` / `bandTop` / `gridH` / `slotHeight` 公式同步改。**联动**：跨带卡高随之变（5–6 节跨午间带由 `72+20-2=90dp` 变 `72+24-2=94dp`），`test/wb239_p1_fix_test.dart` 的 P1-3 断言 `90.0` 同步改 `94.0`，并注明原因；周视图的带高本就是 24，不受影响（`test/wb240_cross_band_height_test.dart` 不用改）。

## §5 不动

- 布局尺寸（标题栏 54dp、行高 36dp、1080×1920、底部补白）、标题栏文案与样式、冲突块（`ConflictBlock`，与 `_ExportSheet` 同款）、单双周半格与叠排分高、卡高公式（除带高 24 的联动）、周次胶囊、卡片配色、底色 token、保存到本地功能（243 的双按钮与保存行）。

## §6 验收

- 真机并排对比图1/图2：卡片有描边、字号一致、长教室完整显示不截断、网格线齐全、表头有底条、带子同高；深色模式导出仍浅色。
- 全量测试 + analyze 全绿。新增/更新测试：
  1. 144dp 长教室卡完整显示（`RichText` 含「药物分析实验\n12-分析化学实验室（二）\n老师名」全量文本，`maxLines == 8`，渲染高度足以容纳，不截断）。
  2. 52dp 单双周半格仍 3 行（P0-1 测试不改，继续通过）。
  3. 网格线存在（通栏横线与纵向列线 finder 能找到）。
  4. 带子高 24（band `Positioned` 高度断言或 `gridH` 算术断言）。
  5. wb239 P1-3 跨带卡高 90→94dp 同步改。
- 发版前 DeepSeek 只读复审，P0/P1 修完。

## §7 版本

纯视觉修复，无新功能，升小号：**2.9.1**（versionCode +44）。
