# WB_SPEC_241：整学期单图导出风格与 App 内一致

## §0 背景与目标
- 2.7.0 真机反馈（2026-11-17 23:41，四张截图）：导出整学期课表的背景风格和软件内不一致，要求风格一致（按钮风格、配色、圆角等）。
- 根因：整学期单图导出（`SemesterSingleImageSheet`，`lib/pages/share_image_page.dart`）用了一套硬编码颜色与圆角，与 App 内周视图、本周导出图（`_ExportSheet`，已走 `buildAppColorScheme` + 主题）不是同一口径。
- 目标：整学期单图导出与 App 内周视图、本周导出图共用同一套设计 token——背景、分隔带、网格线、课卡圆角、文字色、周次胶囊全部对齐；不改布局尺寸（标题栏 54dp、行高 36dp、1080×1920 等均不动）。

## §1 现状对照（以浅色、默认种子为例）

| 元素 | App 内周视图 / 本周导出图 | 整学期单图导出（现状） | 对齐后 |
|---|---|---|---|
| 画布背景 | `colorScheme.surface`（中性 0xFFFAFAF8 + 4% 种子倾向） | 硬编码 0xFFFAF9F5 | `colorScheme.surface` |
| 分隔带背景 | `colorScheme.surfaceContainer`（0xFFF0EBE3 + 4% 种子） | 硬编码 0xFFF2EFE9 | `colorScheme.surfaceContainer` |
| 分隔带文字 | `colorScheme.onSurfaceVariant` | 硬编码 0xFF78716C | `colorScheme.onSurfaceVariant` |
| 网格线 | `colorScheme.outlineVariant` / surfaceContainer | 硬编码 0xFFEBE8E0 | 与 `_ExportSheet` 同口径 |
| 课卡圆角 | `ui.cornerRadius`（默认 12） | 硬编码 `height>=30 ? 7 : 5` | `ui.cornerRadius`（按卡高微调时仍以它为基准，不另起硬编码） |
| 课名文字 | `colorScheme.onSurface`（课卡上） | 硬编码 0xFF1F2937 | `colorScheme.onSurface` |
| 教室/教师文字 | `colorScheme.onSurfaceVariant` | 硬编码 0xFF374151 | `colorScheme.onSurfaceVariant` |
| 周次胶囊 | App 内 chip：`AppRadii.chip`（10）+ 主题色 | 白底 0.65 + 圆角 3 + 0xFF374151 | `AppRadii.chip` 缩比（按 7.5sp 字号等比）+ `colorScheme.surfaceContainerHighest` 底 |
| 标题栏 | AppBar 风格：标题 + 副标题，`colorScheme.onSurface` | 硬编码标题色 | 与 `_ExportSheet` 标题同口径 |

注：深色模式下整学期单图导出固定浅色（239 定案：卡片用存储色原色，深色也不发灰），所以对齐口径统一取**浅色** colorScheme（`buildAppColorScheme(seed, Brightness.light)`），与 `_ExportSheet` 的导出 Theme 一致；不随系统深色走。

## §2 改动点（`lib/pages/share_image_page.dart`，只动 `SemesterSingleImageSheet` 相关）
1. `sheetBg` / `bandBg` / `bandTextColor` / `gridLineColor` 四个硬编码色改为从浅色 `colorScheme` 取值（`surface` / `surfaceContainer` / `onSurfaceVariant` / `outlineVariant`），与 `_ExportSheet` 同口径。
2. `_SingleMasterCard` 的 `borderRadius: height >= 30 ? 7 : 5` 改为 `ui.cornerRadius`（`SemesterSingleImageSheet` 已有 `ui` 入参；若卡高很小需微调，仍以 `ui.cornerRadius` 为上限向下取，不得另起硬编码数）。
3. 课名 / 教室教师 / 周次胶囊文字色改为 `colorScheme.onSurface` / `onSurfaceVariant`；胶囊底色改为 `colorScheme.surfaceContainerHighest`（不透明度与 App 内 chip 一致），圆角按 `AppRadii.chip` 等比缩比。
4. 标题栏（学期名 + 日期范围）文字色与字重与 `_ExportSheet` 标题同口径。
5. 不动：布局尺寸（标题栏 54dp、行高 36dp、周次胶囊 7.5sp、冲突块标签 7sp、1080×1920、底部补白逻辑）、冲突块渐变、单双周半格、卡高公式（241 不动 2.7.0 同版修的 `topOf(end)+行高` 公式）。

## §3 验收
- 导出整学期单图与 App 内周视图并排对比：背景、分隔带、课卡圆角、文字色、胶囊肉眼一致；深色模式下导出仍为浅色（与本周导出一致）。
- 全量测试 + analyze 全绿；现有 239/240 导出测试不受影响（只改颜色与圆角，不改尺寸）。
- 不发版口径：241 与 242（编辑模式浮窗 + 拖动提示，待 Argon 回复）合批，修 bug 不升版，同版 2.7.0 重发。

## §4 待 Argon（另案，不进本规格）
- 编辑模式：常驻 26dp 横栏改上方提示飘窗；编辑模式更明显方案。
- 长按选区框：下拉动画提示；拖动热区加大（拇指好按）。
