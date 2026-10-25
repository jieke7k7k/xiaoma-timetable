# 简课表 · 开发状态备忘（给下一阶段 / 真机验收用）

> 更新时间：2026-10-25（2.0.9+24：WB_SPEC_210 上下栏紧凑 + 网格线跳过休息带）

## 做到哪了

## 2026-10-25（2.0.9+24：WB_SPEC_210 上下栏紧凑 + 网格线跳过休息带，已本地验过）

规格见仓库根 `WB_SPEC_210.md`（两件：上下栏紧凑 / 网格线跳过休息带）。沿用 Riverpod 手写 Notifier / 中文文案注释；本地已跑 `flutter analyze`（零问题）与 `flutter test`（416 项全绿，含新增 6 项）。另注意：规格里写的带子高度 20px 是网页样品值，代码中 kBandHeight 自 1.2.1 起就是 24，未改动。

### 第 1 节 上下栏紧凑

- `lib/ui/grid_metrics.dart`：`kBottomBarHeight` 72 → 56（底栏高度唯一入口，改前改后见该常量注释）。
- `lib/main.dart`：`_HomeBottomBar` / `_SideButton` 三键图标 26 → 22、文字 11 → 10、图标与文字间距 2 → 1，随底栏一起收紧；`theme` / `darkTheme` 增全局 `appBarTheme`——`toolbarHeight: 48`（默认 56 → 48）+ `systemOverlayStyle`（`statusBarColor: transparent` 贴顶，浅色 `statusBarIconBrightness.dark`、深色 `.light` 保证可辨）。
- 顶部栏「贴到屏幕顶端」：AppBar 默认 `primary: true` 背景本已铺到状态栏后，`statusBarColor: transparent` 让状态栏露出 AppBar 同背景色，消除顶部空白带；周数标题、下拉箭头、铅笔/加号/更多三按钮的顺序/图标/功能不变（`week_view_page.dart` 顶栏本体零改动，高度由全局 appBarTheme 生效）。
- 底栏底部手势区 `SafeArea` 保留（`HomeShell` 的 `bottomNavigationBar` 外层）；三键等大平铺、选中态主题色+加粗、像素小马图标、长按无气泡均不变。
- 省出高度还给中间课表：网格区 `Expanded` 继续吃剩余高度，未改行高/格子高度/作息分段。

### 第 2 节 网格线跳过休息带

- `lib/ui/grid_metrics.dart`：新增纯函数 `verticalLineSegments`——按节次切纵向分段、休息带区间不产生分段即跳过（返回 `[start,end)` 区间列表，主页与导出图共用）。
- `lib/pages/week_view_page.dart`：`_GridPainter.paint` 竖线由「整条」改为按 `verticalLineSegments` 分段绘制（带子内不再有竖线穿过）；`_GridPainter.shouldRepaint` 补 `old.activeBands != activeBands`（此前竖线不用带子、漏比较；本轮竖线依赖带子故必须补）；横线 `_FullWidthLinesPainter` 本已「每节底边 + 带子底边、带内无线」，原样保留。
- `lib/pages/share_image_page.dart`：横线由「跳过分隔带处」改为「每节底边（含带子顶边）+ 带子底边」，与主页同口径（修掉导出图此前在带子位置把节次分隔线一并跳过的旧不一致）；竖线由整条 `Positioned` 改为按 `verticalLineSegments` 分段。
- 设置页实时预览为 3 行示例网格、不画分隔带，不适用本节，未改。

### 测试与文档

- `test/grid_metrics_test.dart`（新增）：`kBottomBarHeight == 56` 常量断言；`verticalLineSegments` 纯函数单测（无带子连续、单带/双带跳带、带子 after 越界、分段纵向跨度守恒）。
- `pubspec.yaml` 2.0.8+23 → 2.0.9+24；`CHANGELOG.md` 新增 2.0.9 两条（用户口吻）；本文件与 `ARCHITECTURE.md` 同步。

### 未覆盖处（真机复测项）

- 顶部栏贴顶后，浅色/深色下状态栏图标是否清晰可辨（systemOverlayStyle 已按亮度显式指定，真机观感待验）；
- 底栏压矮后文字（10 号）是否拥挤、三键触控区是否仍好点（SafeArea 手势区保留）；
- 网格线跳过带子后，带子上下边界那条节次分隔线是否仍清晰；
- 导出图与主页的横线/竖线是否完全一致（含带子底边）。

## 2026-10-25（2.0.8+23：WB_SPEC_209 六件合一，未跑命令）

规格见仓库根 `WB_SPEC_209.md`（六件：周日弹窗 / 回到本周竖条悬浮按钮 / 设置删聊天入口 / 左上角只显示周数 / 编辑模式锁滑动与空白新建修复 / 午休晚休自定义）。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由用户代跑（本环境无命令权限）。

### 第 1 节 周日提醒改小弹窗

- `lib/pages/week_view_page.dart`：删 `_SundayEndBanner` 横幅类与 Column 里的占位；新增 `_showSundayDialog`（AppDialog 小弹窗，文案「今天是周日，本周已结束」，按钮「知道了」/「看下周」——最后一周不显示看下周）；新增 `_sundayDialogShown` 布尔，每启动会话最多弹一次，点弹窗外关闭与「知道了」等效。网格恢复完整高度，其他横幅（新版/公告）不动。

### 第 2 节 回到本周竖条悬浮按钮

- `lib/pages/week_view_page.dart`：删顶栏 `if (displayWeek != todayWeek) TextButton.icon(...)`；新增 `_BackToWeekRail`（竖排文字 + 日历图标，宽 30、圆角只在左侧、secondaryContainer），挂在网格区 `Expanded` 的 Stack 右缘中间，非本周视图才渲染、本周自动隐藏；顶栏编辑/新建/更多三按钮顺序位置固定。

### 第 3 节 设置页删聊天入口

- `lib/pages/settings_page.dart`：删「和智能助手聊聊」ListTile、其与「智能助手设置」之间的 1px `Divider`、以及不再使用的 `_XiaomaIcon`；智能助手设置入口、顺序、副标题、跳转不变，首页入口 10 行 → 9 行。

### 第 4 节 左上角只显示周数

- `lib/pages/week_view_page.dart`：删标题 Column 里 fontSize 11 的日期范围 Text，只留周数（单双周开关开时仍显示单/双周标题）；下拉箭头与周次跳转条不动。

### 第 5 节 编辑模式锁滑动 + 空白新建修复

- `lib/pages/week_view_page.dart`：`_GridArea` 的 PageView physics 编辑模式改 `NeverScrollableScrollPhysics`（否则 `DeliberatePagePhysics`）；SingleChildScrollView physics 由 `scrollLocked` 改 `scrollLocked || editMode`，退出编辑模式恢复。
- `_WeekGrid` 根 GestureDetector 加 `behavior: HitTestBehavior.opaque`，空白格可命中，点/长按空白进处理函数；父级 onTapUp/onLongPressStart 原有「非空 cell 直接返回」守卫原样保留（课程卡片点详情/长按菜单不被抢走，需真机复测）。

### 第 6 节 午休/晚休自定义 + 显隐开关

- `lib/ui/grid_metrics.dart`：新增 `BandSettings`（lunchVisible/dinnerVisible 默认开、起止 12:00–14:00 / 17:10–18:00）+ 纯函数 `bandTimeToMinutes` / `bandRangeValid` / `computeActiveBands`（关闭的带子不进入结果、interval 用自定义时间、after 越界过滤）。
- `lib/providers/providers.dart`：新增 `BandSettingsNotifier` + `bandSettingsProvider`（app_settings 键 band_lunch_visible / band_dinner_visible / band_lunch_start / band_lunch_end / band_dinner_start / band_dinner_end；setLunchTime/setDinnerTime 校验开始早于结束，不合法返回 false 不保存）。
- `lib/pages/time_settings_page.dart`：作息页「分段设置」下新增「休息时段」卡片——午休/晚间显示开关 + 起止时间选择器（showTimePicker），改完校验开始早于结束否则 SnackBar「开始时间必须早于结束时间」。
- `lib/pages/week_view_page.dart` / `lib/pages/share_image_page.dart`：分隔带改由 `computeActiveBands` 统一计算，主页与导出图同源，隐藏/自定义时间一致；删掉两处各自按前后节次推导 interval 的局部函数。

### 测试与文档

- `test/settings_page_test.dart`：入口 10 → 9（删聊天入口）、新增聊天行 `findsNothing` 断言、Divider 断言由 findsWidgets 改 findsNothing。
- `test/band_settings_test.dart`（新增）：BandSettings 默认值、computeActiveBands 显隐/越界/interval、bandRangeValid/bandTimeToMinutes 纯函数、Notifier 默认值/开关持久化/开始晚于结束不保存/合法保存（FFI 内存库）。
- `pubspec.yaml` 2.0.7+22 → 2.0.8+23；`CHANGELOG.md` 新增 2.0.8 六条（用户口吻）；本文件与 `ARCHITECTURE.md` 同步。

### 未覆盖处（真机复测项）

- 周日小弹窗与「回到本周」竖条悬浮按钮的真机观感（尺寸/贴边/竖排排版）；
- 编辑模式空白新建的真机复测（opaque 后点/长按空白、课程卡片详情与长按菜单是否仍正常）；
- 分隔带隐藏后导出图与主页是否严格一致。

## 2026-10-25（2.0.7+22：WB_SPEC_208，未跑命令）

规格见仓库根 `WB_SPEC_208.md`（只改设置界面，按 Taste 改、颜色不改黑、其他界面一律不动）。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由用户代跑（本环境无命令权限）。

背景：2.0.7 双版本（WB_SPEC_207，经典/简约切换、首次选择页、重启生效）在待发版复查时被叫停，其改动已收进 git stash（stash 说明：`2.0.7 dual-version paused 2026-10-24, scope changed to settings-only`），本版不包含它、stash 不删，以后想恢复还能找回。

### 第 1 节 设置首页（settings_page.dart）

- `lib/pages/settings_page.dart`：组与组间距由 `AppSpacing.l` 统一为 `AppSpacing.group`（24）；智能助手组内两行（和智能助手聊聊 / 智能助手设置）之间改用 1px 分隔线（`Divider(height: 1, thickness: 1)`，现有主题 dividerColor），不再用 `SizedBox(AppSpacing.s)` 空隙硬隔；`_EntryTile` 与智能助手行标题字重 medium（`FontWeight.w500`）。入口行、顺序、副标题、图标、跳转一个不改；颜色（图标/标题/副标题/背景/分隔线）不动。
- 测试：`test/settings_page_test.dart` 加断言——首页存在分隔线（`find.byType(Divider)` findsWidgets）；原 10 入口 + 无 Switch/Slider + 同名文字各只出现一次不变。

### 第 2 节 设置子页（settings_sections.dart）

- `lib/ui/app_styles.dart`：`AppSpacing` 新增 `group = 24` 常量（组/节间距共享口径），不改全局主题、不影响其他页。
- `lib/pages/settings_sections.dart`：新增私有 `_divideRows`（连续行之间插 1px 分隔线，现有主题 dividerColor）。学期子页 3 行、提醒子页 4 项、学期与数据子页 6 行改用分隔线隔开；外观子页「格子外观」「卡片显示」两组及尾部四行（显示非本周课程/周末收起/立即刷新/部件状态）同款分隔线；节次时间入口与外观组之间、节与节之间间距统一 24（`_Header` 上边距 18→24）。节标题 `_Header` 改主文字色 `onSurface` + semibold（`w600`）、字号仍 13 不放大；行标题（`_InfoTitle`、各 ListTile/SwitchListTile 标题、滑杆行 label、部件状态）字重 medium。预览、下拉、色板、字体区等内容与逻辑一律不动，控件类型与颜色一律不动。
- 测试：`test/settings_sections_test.dart` 新增「学期与数据子页 6 行 → 5 条分隔线」断言；原外观/提醒/预览断言不变。

### 第 3 节 版本与文档

- `pubspec.yaml` 2.0.6+21 → 2.0.7+22；`CHANGELOG.md` 新增 2.0.7 两条（用户口吻）；本文件与 `ARCHITECTURE.md` 同步追加 2.0.7 变更。

## 2026-10-24（2.0.6+21：WB_SPEC_206 第 1~5 节，未跑命令）

规格见仓库根 `WB_SPEC_206.md`（共五节）。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由主会话代跑。

### 第 1 节 设置首页去掉重复分组小标题

- `lib/pages/settings_page.dart`：删除 `_SectionHeader` 组件与全部 9 处分组小标题（小标题与入口行同名，纯重复），首页只留入口行；组与组之间用 `SizedBox(AppSpacing.l)` 分隔，智能助手组内两行用 `SizedBox(AppSpacing.s)`。入口行本身、顺序、副标题、跳转全不动。
- 测试：`test/settings_page_test.dart` 改断言——9+1 个入口行各 `findsOneWidget`；新增「学期设置/外观/提醒」等 8 个同名文字在首页各只出现一次；无 Switch/Slider 不变。

### 第 2 节 指令定位参数容错

- `command_executor.dart`：新增私有共用方法 `_locateTargetCourses`（set_course_color / set_course_remark / add_exam 三处共用）+ 私有 `_locateName` 别名读取。courseId 别名 `courseId`/`id`；courseName 别名 `courseName`/`name`/`course`/`course_name`/`课程名`；courseId 优先、精确匹配同名全改，精确落空做一次按名模糊匹配（课程名与给定名互为包含：恰好 1 个用它、多个报错并列候选、0 个维持「当前学期没有名为《X》的课程」）。别名只在这三条「定位已有课程」指令生效——add_course 的 `name` 是新课名，绝不走这里、不受影响。其余行为（快照/操作记录/结果文案）不变。
- 测试：`command_executor_test.dart` 新增组「定位参数别名与按名模糊匹配（2.0.6）」7 例。

### 第 3 节 上下文补全学期课程清单 + 指令示例

- `ai_context.dart`：`buildTimetableContext` 加可选参数 `allCourses`，非空时输出【全部课程（定位用）】节（每行《课程名》（id 编号、周X 第A-B节），按课程名排序）；新增公开 `buildCourseListContext` 复用同一格式（纠错提示也用它）。系统提示 `buildSystemPrompt` 补 set_course_remark 两条完整 JSON 示例与「courseName 必须从清单原样复制、不要改字/简称/编 id」硬规矩。
- `ai_chat_page.dart`：`_contextNow` 传 `allCourses: courses`（coursesProvider 即当前学期 getCoursesBySemester 结果）。
- 测试：`ai_context_test.dart` 新增全部课程清单（含排序/格式）、示例与硬规矩断言。

### 第 4 节 失败自动纠错重试一次

- `ai_context.dart` 新增纯函数：`isParameterFailure`（认缺少参数/缺少定位参数/没有名为/没有 id 为/课程名能对上多门课/不支持的指令类型）、`shouldRetryForParameterError`（`alreadyRetried` 为 true 一律不重试，硬上限一次）、`buildCorrectionPrompt`（用户原话 + 失败指令 JSON + 报错原文 + 课程名单，要求只回改好的指令）。
- `ai_chat_page.dart`：`_runCommands` 执行完若 `shouldRetryForParameterError` 为真且本轮未重试过，置 `_retriedThisRound = true` 后调 `_autoCorrectCommands`——追加提示行「刚才的指令参数不对，我让它照着课程名单改一次」→ 再调一次模型（纠错提示作为 user 消息）→ 解析回指令照常走原有确认卡片路径；纠错后仍失败如实展示、不再重试。新用户消息（`_send` 且 retryText==null）重置 `_retriedThisRound`。桥侧不加这层重试——对端外部 AI 自己会看 results 纠错。
- 测试：`ai_context_test.dart` 新增纠错判定纯函数单测；页面级 widget 测试因假异步 / HTTP 替身成本过高未做（判定逻辑已抽成纯函数覆盖，见汇总说明）。

### 第 5 节 版本与文档

- `pubspec.yaml` 2.0.5+20 → 2.0.6+21；`CHANGELOG.md` 新增 2.0.6 两条（用户口吻）；本文件与 `ARCHITECTURE.md` 同步追加 2.0.6 变更。

## 2026-10-24（2.0.5+20：WB_SPEC_205 第 9 节，未跑命令）

承接前八节（已通过 382 项测试），本轮补齐第 9 节（设置项 ⓘ 说明按钮）。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由主会话代跑。

### 第 9 节 设置项 ⓘ 说明按钮

- `lib/pages/settings_sections.dart`：新增私有 `_InfoTitle`（标题旁 `Row` 挂 `AppInfoIconButton`，点开 `showAppInfoDialog` 显示原文）；把各子页里「说明性副标题」从行内删掉、收进标题旁 ⓘ，行内只剩标题 + 控件，共 18 处——学期与数据 6 行、提醒 3 开关、外观组 8 项、外观子页节次时间入口 1 项。弹窗正文用原副标题文字一字未改。
- 保留未动的副标题：学期子页三行当前值（学期名/开学日期/总周数）、提醒「提前 X 分钟」、各「加载中…/加载失败」与权限状态摘要/部件状态等状态类、设置首页 9+1 入口导航摘要、桌面小组件子页添加说明（说明页本体）。
- 测试：`test/settings_sections_test.dart` 增断言——外观子页出现 `AppInfoIconButton` 且点开「行高自适应一屏」看到对应弹窗；提醒子页点开「上课提醒」看到「每节课提前提醒…」弹窗。

## 2026-10-24（2.0.5+20：WB_SPEC_205 第 2/3/4 节，未跑命令）

承接上一轮第 1/5/6/7 节，本轮落地剩下三节：第 2（AI 指令补全）、3（智能助手历史记录）、4（撤回操作）。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由主会话代跑。

### 第 2 节 AI 指令补全

- `command_executor.dart`：新增 `set_course_remark`（courseId/courseName 定位、同名全改、空字符串清除，整对象重建写 note）；`delete_note` 扩展为「按 id / 按 date / 按 date+content 关键词」删除，命中多条全删并报条数，定位不到给中文原因（不再报「缺少参数 id」）；注册表补 `set_course_remark`（非破坏性）。
- `command_describe.dart`：补 `set_course_remark` 人话描述；`delete_note` 描述支持 id/日期/关键词三种定位。
- `ai_context.dart`：备注清单改为列**全部**日期备注（每条带 `[id=N] 日期 内容`）+ 单列「课程备注（长期有效）」节，与日期备注明确区分；课程行不再内嵌备注；系统提示词补 `set_course_remark` 参数与「给 XX 课加备注默认指课程备注、某天加备注才用 add_note」的默认语义。
- 测试：`command_executor_test.dart` 增 set_course_remark（按名/同名全改/清除/失败路径）、delete_note 按日期/关键词/定位不到中文原因；`ai_context_test.dart` 改全部备注 + 课程备注节 + 提示词新断言。

### 第 3 节 智能助手历史记录

- 新表 `chat_sessions`（v4）：一段对话一行，messagesJson 整段存消息（角色/文本/时间/指令原文/执行结果状态）。模型 `lib/models/chat_session.dart`；`db_helper.dart` 版本 3→4 补建表；`dao.dart` 增会话列/存/删。
- 服务 `lib/services/chat_session_service.dart`：列（更新时间倒序）/存（id 更新或插入）/删。
- `ai_chat_page.dart`：AppBar 加「历史记录」「新对话」入口（替换原清空按钮）；聊天过程中 `_persistSession` 落库（首条定标题与 createdAt，之后更新）；`_ChatItem` 加 `time` 字段与 `fromMessage/toMessage` 往返；历史页选中会话 `pop` 回来恢复续聊。
- 新页 `lib/pages/ai_history_page.dart`（路由 `/ai-history`）：Tab「对话」（列表/点开恢复/长按或左滑删除/空状态中文）+ Tab「操作记录」。
- 测试：`chat_session_test.dart`（存取/更新/倒序/删除/消息指令往返）、`ai_history_page_test.dart`（对话列表存在性、空状态、操作记录 Tab 撤回按钮）。

### 第 4 节 撤回操作

- 新表 `operation_log`（v4）：时间/来源/中文摘要/执行前快照 JSON/是否已撤回。模型 `lib/models/operation_log.dart`；`dao.dart` 增操作记录列/插/标撤回。
- `command_executor.dart`：`execute`/`executeAll` 加 `CommandSource? source`（ai/bridge），每条成功改数据指令在执行前取快照并落一条操作记录（新增类记新 id、删除类记全文、修改类记旧值）；撤回本身走 Dao、不再进执行器（防套娃）。
- 服务 `lib/services/operation_log_service.dart`：`undo` 按快照还原（add_course 删课 / add_note 删备注 / delete_note 加回 / 修改类改回旧值），尽力还原、还原不了给中文提示不崩，并标已撤回。
- 桥服务 `bridge_service.dart`：`_processBatch` / `resolvePending` 执行时传 `CommandSource.bridge`；AI 聊天页传 `CommandSource.ai`。
- 测试：`operation_undo_test.dart`（add_course / delete_note / set_course_remark 三类执行→撤回往返 + 撤回不新增记录）。

## 2026-10-24（2.0.5+20：WB_SPEC_205 第 1/5/6/7 节，未跑命令）

规格见仓库根 `WB_SPEC_205.md`；本轮只落地第 1（设置页 QQ 式整顿）、5（像素小马图标）、6（实时预览今天列高亮修复）、7（桥登录 Custom Tab）四节，第 2/3/4 节（AI 指令 / 历史记录 / 撤回）未动、下一轮再派。沿用 Riverpod 手写 Notifier / 中文文案注释；`flutter analyze` / `flutter test` 由主会话代跑。

### 第 1 节 设置页 QQ 式整顿（本版主项）

- 新增 `lib/pages/settings_sections.dart`：6 个设置分类子页 + 从 settings_page.dart **原样搬来**的组件与逻辑——`SemesterSettingsPage`（/settings-semester，学期名称只读 / 开学日期 / 总周数）、`AppearanceSettingsPage`（/settings-appearance，实时预览 + `_AppearanceGroup` 整体 + 节次时间入口）、`RemindersSettingsPage`（/settings-reminders，上课提醒 / 上课播报 / 常驻通知 / 提前提醒，含三开关一选择）、`DataSettingsPage`（/settings-data，导入 / 学期管理 / 备份 / 恢复 / 导出 ICS / 数据管理 6 行）、`PermissionsSettingsPage`（/settings-permissions，原 `_PermissionSummaryTile` 内容）、`WidgetSettingsPage`（/settings-widget，小组件说明）。搬家原则：Consumer/回调/逻辑原样复用，不许丢项、不许改行为。
- `lib/pages/settings_page.dart` 重写为纯入口首页：只保留 9 个分组标题 + 每类一行入口行（图标 + 名称 + 一行副标题 + ›），首页**无任何 Switch/Slider**；`_SectionHeader` / `_EntryTile` / `_XiaomaIcon` 留本文件，其余组件与全部业务方法（改开学日期/总周数/提醒开关/提前分钟/备份恢复/导出 ICS 等）迁到 settings_sections.dart。
- `lib/main.dart` 注册 6 条新路由 /settings-semester、/settings-appearance、/settings-reminders、/settings-data、/settings-permissions、/settings-widget。
- 长期规范改写：2.0.3 的「外观平铺首页」（设置类条目优先平铺在首页当场可改）被本节取代——设置首页只放分类入口，点进分类才看到该组的开关/滑杆等设置项（QQ 式分级）。
- 测试：`test/settings_page_test.dart`（9 个分类入口 + 首页无 Switch/Slider）；`test/settings_sections_test.dart`（外观子页实时预览与主要外观项存在）。

### 第 5 节 像素小马图标

- `pubspec.yaml` assets 声明 `assets/icons/`（xiaoma_assistant_selected.png 玫红 / xiaoma_assistant_unselected.png 灰，文件已备好未动）。
- 替换三处 `Icons.smart_toy(_outlined)`：main.dart 底栏智能助手 Tab（`_SideButton` 改 `iconBuilder`，选中玫红/未选灰 `Image.asset` 26dp，与文字标签状态同步）；ai_chat_page.dart 两处空状态（`EmptyState` 新增可选 `iconImage` 参数，玫红版）；settings_page.dart「和智能助手聊聊」入口（`_XiaomaIcon` 灰版 24dp）。

### 第 6 节 实时预览今天列边框高亮

- `Preview`（由 `_Preview` 改公开以便测试）改为展示「今天起连续三天」（列头真实星期 + 日期，今天第一列，日期圆点高亮）；`ui.highlightTodayColumn` 开时给第一列画整列边框（主页同款：主题色描边、线宽 1.5、圆角 6），关时不画；覆盖层 Key `kPreviewTodayHighlightKey` 供测试断言。预览随第 1 节迁入外观子页，效果在子页生效。
- 测试：`test/settings_sections_test.dart` 断言 `Preview` 开/关时今天列边框覆盖层出现/消失。

### 第 7 节 桥登录 Custom Tab

- `bridge_page.dart`：`_openInBrowser` 改 `LaunchMode.inAppBrowserView`（Chrome Custom Tab，与用户默认浏览器共享登录态）；按钮文案「在浏览器打开（手动输码）」→「在浏览器打开（共享登录，手动输码）」；设备码卡三步说明下补一句要点（浏览器方式已登录、手输 8 位码即可；粘贴只能填一格，不想手输就用 App 内自动填码）。设备码申请/轮询/自动复制逻辑未动。
- 测试：`test/bridge_page_test.dart` 同步更新按钮文案与新增要点句断言。

### 版本

- `pubspec.yaml` 版本 2.0.4+19 → 2.0.5+20。

## 2026-10-23（2.0.4+19：WB_SPEC_204，未跑命令）

规格见仓库根 `WB_SPEC_204.md`；`flutter analyze` / `flutter test` 由主会话代跑。沿用 Riverpod 手写 Notifier / 中文文案注释，未动规格无关文件。

- 新增 `lib/pages/bridge_web_login_page.dart`：WebView 内嵌打开 GitHub 设备码页（`WebViewController` + `JavaScriptMode.unrestricted` + 主流 Chrome Android UA，仿 `web_import_page.dart` 写法）；AppBar 标题「GitHub 授权」，右侧刷新 / 在浏览器打开（url_launcher 同一地址），左上角关闭；底部小字「授权完成后关闭本页返回，App 会自动完成连接。」。轮询换令牌仍归桥页，本页不碰令牌。
- 自动填码：`onPageFinished` 每次页面加载完后 `runJavaScriptReturningResult` 注入一段 JS（设备码以字面量带入）。触发条件：页面里「可见的、单字符文本输入框」（type 为 text/tel 或无 type、有 maxlength 且 <=2、有实际尺寸且未隐藏）**恰好 8 个**才填，否则什么都不做（登录页/选账号页等下一次页面加载再触发）。填法：去连字符取 8 字符，逐格用 `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set` 原生 setter 赋值，并依次派发 `input`(bubbles) 与 `change` 事件。防重复填：Dart 侧 `Set<String> _filledKeys` 记「页面 URL + 设备码」，且只有 JS 回传 `filled`（真填上）才记 key——没填上不记，下一次页面加载还会再试；已记 key 的同一 URL 再次 onPageFinished 直接跳过，不覆盖用户手改。JS 全段 try/catch 回传状态串，Dart 侧注入异常也静默吞掉，不影响手动输入。
- `lib/pages/bridge_page.dart`：设备码卡主按钮改「在 App 内打开并自动填码」（push `BridgeWebLoginPage`，带当前码与 verificationUri）；原「去 GitHub 粘贴」降为次要按钮并改名「在浏览器打开（手动输码）」；三步文案换新流程（① 点「在 App 内打开并自动填码」② 登录/确认账号，码已自动填好，点 Continue 并授权 ③ 关闭页面返回，App 自动完成连接）；2.0.3 的自动复制与「复制代码」按钮保留（复制成功 SnackBar 改为「已复制，可作为手动输码备用」）。类注释补 2.0.4 说明，`_openVerification` 改名 `_openInBrowser`。
- 测试：新增 `test/bridge_page_test.dart`（桥页按钮存在性/文案）：sqflite_common_ffi 内存库 + `DbHelper.useDatabaseForTest` + `HttpOverrides` 假 GitHub（设备码申请返回 ABCD-1234、轮询恒 pending），断言新主按钮/次要按钮/「复制代码」/大字码/三步新文案存在、旧文案「去 GitHub 粘贴」消失；末尾点「取消登录」收掉轮询定时器。WebView 内嵌页按规格不测（平台限制）。仓库原先没有任何断言桥页按钮文案的测试，故无旧断言需要同步改。
- `pubspec.yaml` 版本 2.0.3+18 → 2.0.4+19；webview_flutter 依赖已在（^4.14.1），未动。

## 2026-10-23（2.0.3+18：桥登录一键粘贴 + 设置页单页平铺）

- 桥登录（bridge_page.dart）：设备码生成即自动复制剪贴板（_copiedUserCode 码值守卫，只触发一次、失败静默）；卡片加「复制代码」按钮与三步文案；原「打开 GitHub 输码」改名「去 GitHub 粘贴」。实测依据：GitHub 输码页第一个格粘贴整串可自动分格，链接带码不预填。
- 设置页（settings_page.dart）：「外观」二级页 ui_settings_page.dart 已删，全部条目平铺进设置首页外观组（_AppearanceGroup）；首页重复的「自动备份」行删除（数据管理页保留）。长期规范补充：设置类条目优先平铺在首页当场可改，不再新设二级设置页；编辑器/管理页才点进。（2.0.5 起该「外观平铺首页」规范被 QQ 式分级取代，见 WB_SPEC_205 第 1 节）
- 复审：step-5-preview 只读复审「可发布」；旧外观页 15 个标题文本已与新首页逐项对账，无遗漏。analyze 零问题、357 测试全绿。

## 2026-10-22（WB-202 第二批：第 2 项 + 第 4 项 + 第 3 项补充，未跑命令）

目标版本 2.0.2+17（版本号 / CHANGELOG / 提交发布由小马统一做，WB 未动）。只落地规格第 2、4 项与第 3 项补充；沿用 Riverpod 手写 Notifier / Dao 单例 / 中文文案注释。`flutter analyze` / `flutter test` 由你执行。

### 第 2 项 设置页按 A 方案重组

- `lib/pages/settings_page.dart` 重排（条目一个不能丢、路由尽量复用）：**学期设置**（学期名称 / 开学日期 / 总周数；学期管理移出）/ **外观**（原「界面设置」改名；主题三档、显示非本周、周末收起、刷新小部件、部件状态、节次时间原样）/ **提醒**（原「提醒设置」改名；上课播报开关从外观页移入本组）/ **课表工具**（一行入口）/ **智能助手**（「和智能助手聊聊」+「智能助手设置」两行，表单收进二级页）/ **学期与数据**（导入课表、学期管理、备份到文件、从备份恢复、导出课表 ICS、自动备份只读行、数据管理）/ **权限**（单列一行）/ **关于小马课表**（单列一行）/ 桌面小组件说明（原样保留）。
- 新增 `lib/pages/course_tools_page.dart`（路由 `/course-tools`，main.dart 注册）：课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 / 日期备注五个功能入口，路由全部复用原页面（`/course-search` `/free-time` `/exam-countdown` `/share-image` `/notes`）。
- 拆解「高级与数据」：AI 桥入口并入智能助手二级页；备份 / 恢复 / 导出 ICS / 数据管理与教务导入、学期管理同组为「学期与数据」；权限、关于上浮一级页单列。`advanced_page.dart` 内容全部迁出、`/advanced` 路由移除，文件已清空为占位说明（提交时 `git rm lib/pages/advanced_page.dart`）；`_PermissionSummaryTile` 与备份 / 恢复 / ICS 导出实现随迁 `settings_page.dart`。
- `lib/pages/ui_settings_page.dart`：删「上课播报」开关（移设置页提醒组）；页面标题「界面设置」→「外观」。

### 第 4 项 说明卡片改小图标弹窗 + 弹窗风格统一

- 新增 `lib/widgets/app_dialog.dart`：全 App 统一弹窗组件 `AppDialog`（标题 / 正文 / 按钮区的圆角、内边距、排版同一套规范，圆角取 `AppRadii.dialog`）+ `showAppInfoDialog`（ⓘ 信息弹窗，单按钮「知道了」）+ `showAppConfirmDialog`（确认弹窗，取消 TextButton / 主动 FilledButton，破坏性 `destructive: true` 标红）+ `AppInfoIconButton`（条目标题旁 18 号小 ⓘ）。
- `lib/ui/app_styles.dart`：新增 `AppRadii.dialog = 20`。
- `lib/pages/ai_settings_page.dart`：「怎么领一个免费的 Key」长说明卡片移入表单标题旁 ⓘ 弹窗（正文一字未改，见顶部常量 `kFreeKeyGuide`）；新增「测试对话」区放页面最底部（发一句话验证接口连通，不进聊天历史、不带课表上下文）；AI 桥入口并入本页；原卡片底部的密钥安全小注保留为小字。
- `lib/pages/bridge_page.dart`：桥页顶部说明（原 `_ConnectCard` 平铺文案）同法改 ⓘ 弹窗（正文一字未改），卡片只留标题与「连接 GitHub」主按钮。
- 设置区与主页高频弹窗已切统一组件：settings_page（设置总周数 / 开启精确闹钟 / 确认恢复备份 / 恢复进度遮罩）、ui_settings_page（删除导入字体 / 自定义主题色）、data_manage_page（确认恢复备份 / 恢复出厂两步）、week_view_page（重要公告 / 考试详情 / 删除课程）。其余页面（course_edit / notes / semester_manage / import / about / time_settings 等）不在本批范围，后续迁移也必须用它。
- **长期规范（WB-202 第 4 项，本轮起执行）**：① 新弹窗一律用 `lib/widgets/app_dialog.dart`，不再各页面手搓 AlertDialog；② 长说明不再以卡片平铺——条目标题旁放小 ⓘ（`AppInfoIconButton`）+ `showAppInfoDialog` 显示全文；③ 确认弹窗用 `showAppConfirmDialog`，破坏性操作传 `destructive: true`。

### 第 3 项补充 冷启动标题周与网格周不一致

- 根因（第一批遗留观察已记）：PageController 在 initState 里创建，那一刻学期还没加载完（todayWeek 读成 0、总周数读成 0），initialPage 只能停第 1 周；而 displayWeekProvider 的首值要到 build 里才第一次求值、ref.listen 不因首值触发，出现「标题第 6 周、网格第 1 周」，切一下周才同步。
- 修法：PageController 延迟到学期就绪后的首次 build 里懒创建，initialPage 直接取钳制后的显示周（新增纯函数 `weekViewInitialPage(displayWeek, totalWeeks)`，与 `DisplayWeekNotifier` 同一套 `clampForPage` 口径），标题与网格首帧即一致，无跳转、无闪烁；initState 不再读 todayWeek。
- 测试：新增 `test/week_view_initial_page_test.dart`（5 例：第 6 周 → 第 6 页、第 1 周、学期已结束钳最后一周、未开学钳第 1 周、总周数未知不封顶）。
- 真机验证方式：杀进程冷启动 → 首帧标题周与网格周一致（第 6 周的标题就是第 6 周的内容），不需要切周；切周 / 回到本周 / 换学期等原有交互不变。

## 2026-10-22（WB-202 第一批：第 1 项 + 第 3 项，未跑命令）

目标版本 2.0.2+17（版本号 / CHANGELOG / 提交发布由小马统一做，WB 未动）。只落地规格第 1、3 项，第 2、4 项未碰；沿用 Riverpod 手写 Notifier / Dao 单例 / 中文文案注释。`flutter analyze` / `flutter test` 由你执行。

### 第 1 项 底部留白 + 主页按钮等大
- `lib/main.dart`：`_HomeBottomBar` 去掉 Stack 与凸起大圆按钮，中间「主页」改用与左右完全一致的 `_SideButton`（图标 26、文字 11 号常显、同高度），三键等大平铺；选中态沿用主题色 + 加粗即可辨。顺带删除 `_HomeButton` 类，更新 HomeShell / _HomeBottomBar / _SideButton 的注释（凸起相关描述移除，「不用 NavigationBar、不包 Tooltip」的理由保留）。
- `lib/pages/week_view_page.dart` `_GridArea`：删掉 2.0.1 加的 `padding: bottom kBottomBarHeight` 与 `bottomPad` 扣除——autoFit 行高与 contentHeight 恢复直接用 `constraints.maxHeight`，课表区恢复贴合到底栏（与 2.0.0 一致，不再空一大截）。
- `lib/ui/grid_metrics.dart`：`kBottomBarHeight = 72` 保留（底栏自身高度仍引用它），注释改为「网格不再按它留底部内边距」。

### 第 3 项 冷启动显示「本周没有课程」
- 根因：课程数据链路没有加载门闩。冷启动（杀进程后重进）时 `currentSemesterProvider` 先就绪、`coursesProvider` 的 DB 查询还在 AsyncLoading，旧代码一句 `ref.watch(coursesProvider).value ?? []` 把「加载中」的 null 当成空列表，`_WeekGrid` 的 `visible.isEmpty` 直接渲染「本周没有课程」空状态；且启动瞬间的通知重排 / 小部件刷新 / AI 桥同步还在抢同一条 DB 连接，这个窗口被拉得更长，足以被用户看到并截图（第 6 周实际满周有课）。
- 修法（链路根因，非延时糊弄）：`week_view_page.dart` 新增纯函数门闩 `weekDataNotReady`（AsyncLoading 且无值 → 未就绪）；`WeekViewPage.build` 在学期门闩后补课程 / 调课 / 作息三个 provider 的门闩，未就绪一律转圈；数据一到 provider 推 AsyncData，Riverpod 自动重建周视图呈现真实课程，不需要用户切周或重启。数据就绪后的空列表仍是合法空状态（本周真没课才显示）。
- 测试：新增 `test/week_view_load_gate_test.dart`，覆盖「加载中无值 → 未就绪」「有数据 / 空列表 → 已就绪」「错误不算未就绪」四种情形。

### 遗留观察（不在本批规格内，真机验收时留意）
- 冷启动页码疑似不同步：`displayWeekProvider` 的首值要到 build 里才第一次求值（build #1 学期未就绪早返回，没读过它），求出来即「本周」；而 `ref.listen(displayWeekProvider)` 只在值变化时触发、不因首值触发，PageController 又停在 initState 按「学期未加载」算出的 initialPage=0（第 1 周）——冷启动后可能出现「标题第 6 周、网格第 1 周内容」，切一下周才同步。本批只修规格内的空状态问题，未动页码逻辑；真机如能复现，建议下一批单独修（别在 build 里直接 jumpToPage，会和用户滑动打架）。

## 2026-10-22（2.0.1 真机反馈修复包：P1–P7，未跑命令）

目标版本 2.0.1+16。逐项修 2.0.0 真机反馈，未改规格之外的功能；沿用 Riverpod 手写 Notifier / Dao 单例 / 中文文案注释。`flutter analyze` / `flutter test` 由你执行。

### P1 单双周重复显示 + 开关默认关
- `lib/models/ui_settings.dart`：`showWeekParity` 默认 `true → false`（构造默认 + `fromEncoded` 的 `bl('showWeekParity', false)`），注释改为「标题是否显示单双周后缀」；`showParityLabel` 字段保留仅兼容旧数据、不再参与显示。
- `lib/pages/week_view_page.dart`：删掉标题旁那枚「单周/双周」药丸与 `parityText` 计算；标题后缀由 `showParityLabel` 改读 `showWeekParity`。
- `lib/pages/ui_settings_page.dart`：删「左上角单双周小标识」开关；「标题显示单双周」开关改绑 `showWeekParity`，副标题注明默认关。

### P2 上课播报开关（默认关）
- `UiSettings` 新增 `showClassBroadcast`（默认关，JSON 键 `showClassBroadcast`）。
- `lib/pages/ui_settings_page.dart` 加「上课播报」开关；`week_view_page.dart` 状态条 `_ClassFocusBar` 改由 `ui.showClassBroadcast` 控制显隐（常驻通知不受影响）。

### P3 主页按钮过大遮挡课表
- `lib/ui/grid_metrics.dart` 新增 `kBottomBarHeight = 72`。
- `lib/main.dart`：主页圆按钮 56→48、图标 30→26；底栏高度改引 `kBottomBarHeight`。
- `lib/pages/week_view_page.dart` `_GridArea`：滚动体加 `padding: bottom kBottomBarHeight`，autoFit 与 contentHeight 计算同步扣除该内边距，保证任何状态最后一排课程卡不被底栏/按钮遮挡。

### P4 AI 按钮改名
- 底栏「AI」→「智能助手」（`main.dart`）；聊天页标题「AI 助手」→「智能助手」、空态「还没配置 AI」→「还没配置智能助手」、「去 AI 设置」→「去智能助手设置」（`ai_chat_page.dart`）；设置页标题「AI 助手设置」→「智能助手设置」（`ai_settings_page.dart`）。服务名/类名不动。

### P5 设置页分组 + 低频收二级
- 新增 `lib/pages/advanced_page.dart`（路由 `/advanced`，`main.dart` 注册）：收 AI 桥 / 权限 / 数据管理（备份、恢复、导出 ICS、数据管理）/ 关于小马课表。
- `lib/pages/settings_page.dart` 重排为：学期设置 / 界面设置（含主题三档、显示非本周、周末收起、小部件刷新与状态、节次时间）/ 提醒设置 / 课程与工具（含导入课表）/ 备注 / AI 设置（智能助手）/ 高级与数据。入口一个不少、路由不变。

### P6 AI 桥设备码登录
- `lib/services/bridge_service.dart`：新增 `githubClientId = 'Ov23liosvFFdJSTw827b'` 常量与设备码流程方法 `requestDeviceCode` / `pollDeviceToken` / `fetchGithubLogin` / `checkMailboxRepo` / `createMailboxRepo` / `saveDeviceLogin` / `disconnect` / `testConnection` 及 `DeviceCodeResponse` / `DeviceTokenStatus` / `DeviceTokenResponse` 类型。信箱协议、同步逻辑、执行器一律未动。
- `lib/pages/bridge_page.dart` 重写：未连接只显示一句话 + 「连接 GitHub」；点后大字展示 user_code + verification_uri + 「打开 GitHub 输码」（url_launcher）+ 取消；按 interval 轮询（pending 继续、slow_down 加长、expired/denied 给人话并允许重试）；成功存 `bridge_token`、`bridge_owner` 自动取 login、`bridge_repo` 默认 `xiaoma-app-bridge`；查仓 404 给「一键创建信箱仓」（POST /user/repos + 三个 .gitkeep）；已连接显示「已连接为 @login · 仓库」+ 同步/待确认（位置下移）+ 断开连接；底部「高级」折叠区保留手动令牌方式（保存 + 测试连接=只读列 commands）。

### P7 小米负一屏仍无小部件（按调研结论执行，未改元数据）
- 未动 `course_widget_info.xml` 与 Manifest 部件声明。结论：本应用部件元数据完整（widgetCategory=home_screen、previewImage/previewLayout、targetCell 4×3、description、receiver+APPWIDGET_UPDATE+meta-data 均在），桌面小部件选择器能正常列出并添加，AppWidgetManager 侧无问题；小米智能助理的添加列表按服务器下发目录 + 已安装应用匹配，-1 屏若设为「Google 发现」则没有添加入口，应用侧不存在能保证被负一屏收录的元数据。
- 手机侧排查清单：① 设置 → 主屏幕，确认 -1 屏选的是「智能助理」而非「Google 发现」；② 把智能助理更新到最新版；③ 重启手机后，进负一屏编辑页 → 添加小部件 → 在「安卓小部件」分类里找「今日课程」。

### 测试
- `test/ui_settings_test.dart`：`showWeekParity` 默认断言 `isTrue → isFalse`；新增 `showClassBroadcast` 默认关断言；往返用例补 `showWeekParity` / `showClassBroadcast` 字段。

## 2026-10-22（2.0.0 收官大包：内置 AI + 底栏三键 + 首次权限，307 → 340 测试基线，未跑命令）

**新增 9 个文件、改 9 个文件**；无新增 pub 依赖（HTTP 复用 `dart:io`），无表结构变化（AI 配置与权限标记走 `app_settings`），未提交 git。

### 一、内置 AI 助手（设置 → AI 助手）

1. **服务层**（`lib/services/ai_service.dart`）：OpenAI 兼容 `chat/completions`，`dart:io` HttpClient（连接 10s / 响应 30s，异常一律兜成中文）。配置三键 `ai_base_url` / `ai_model` / `ai_api_key`，预设智谱 `https://open.bigmodel.cn/api/paas/v4` + `glm-4-flash`（模型名是可改的文本框，出了新 Flash 型号直接改）。**Key 留空表示不改**（输入框遮挡显示），与 AI 桥令牌同款处理。
2. **上下文现取**（`lib/utils/ai_context.dart`）：每次发送重新读学期 / 本周有效课程（经 `effectiveCoursesForWeek` 应用调课）/ 备注，拼出「学期名 + 总周数 + 当前第几周（单/双周）+ 今天明天日期星期 + 本周课程精简列表 + 临近考试（带倒计时）+ 今天/明天备注」。所以「我明天有什么课」「哪天有空」能直接答。
3. **动手能力与桥同源**：模型回复里的 fenced json 块 `{"commands":[...]}` 被解析出来后**先渲染成确认卡片**——非破坏指令「一键执行」、破坏指令标红单独「仍要执行」（另给「忽略」）；点执行才走 `CommandExecutor`，结果回填聊天，并失效 `coursesProvider/notesProvider` + 重排提醒 + 刷新备注通知/常驻通知/小部件（与 BridgePage / HomeShell 同一份口径）。代码块**不会原样显示**（解析阶段就从正文摘掉）。人话描述复用 `describeCommand`，桥的 `describePendingCommand` 已改为委托它（行为逐字不变，35 个桥用例不受影响）。
4. **页面**：`AiChatPage`（底栏左键 + 路由 `/ai-chat`）：消息列表 + 输入框 + 发送中转圈 + 失败「重试」；未配置时是引导空状态（说明智谱免费领 Key + 「去 AI 设置」按钮）。`AiSettingsPage`（路由 `/ai-settings`）与设置页内嵌的是**同一个** `AiSettingsForm`。

### 二、界面改版（底栏三键）

- **底栏**：左 AI / 中主页（56px 凸起圆按钮，明显大于两侧）/ 右设置；默认停在**主页**。**自绘 `_HomeBottomBar`，不用 NavigationBar**——中间要大按钮，而 `NavigationDestination` 长按会浮出 label 气泡（用户发过截图）。名称一律常显小字，**不包任何 Tooltip**，长按无反馈。
- **主页**：右上角新增「+」按钮，点开就是原来那套「手动新建 / 导入课表」选择框；左上角新增当前周的「单周 / 双周」小标识（口径 = `WeekCalc` 当前周，未开学或学期已结束不显示），开关在「界面设置 → 左上角单双周小标识」（`showWeekParity`，默认开）。
- **原页签 → 新去向**（一个都没丢）：

| 原目的地 | 新去向 |
|---|---|
| 课表（主页） | 底栏中间「主页」（默认页），不变 |
| 新建课程 / 导入课表 | **主页右上角「+」按钮**（底栏不再有「新建」键） |
| 学期管理 | 设置 → 学期设置 → 学期管理（**已有**） |
| 导入课表 | 设置 → 数据导入 → 导入课表（**已有**） |
| 数据管理（备份/恢复/导出 ICS/存储占用） | 设置 → 数据管理（**已有**） |
| 备注 | 设置 → 备注（**已有**） |
| 课程搜索 | 设置 → **课程与工具（本轮新增）** → 课程搜索 |
| 空闲时段 | 设置 → **课程与工具（本轮新增）** → 空闲时段 |
| 考试倒计时 | 设置 → **课程与工具（本轮新增）** → 考试倒计时 |
| 导出课表图片 | 设置 → **课程与工具（本轮新增）** → 导出课表图片 |
| AI 桥 | 设置 → AI 桥（**已有**） |
| 界面设置 / 外观 / 作息 / 提醒 / 关于 / 小组件 | 设置页原分区，**未动** |

### 三、首次权限索取

- `PermissionService` 是三项权限的**唯一入口**（此前散落在提醒开关里）。通知申请仍走插件 API；`MainActivity` 新增 `device` MethodChannel 负责**查状态**与跳系统页（通知设置 / 闹钟和提醒 / 电池优化 / 应用详情兜底）。
- 首次进入主页后依次引导：① 通知（系统授权框）→ ② 精确闹钟 → ③ 电池优化白名单。每步都能「跳过」；**标记 `permissions_asked_v1` 在引导开始前就落库**，所以拒绝/跳过/中途杀 App 都不会再弹。
- 设置页新增「权限」入口行：显示「已授权 x / 3」摘要，进页面可看到三项各自状态，未授权的项点进去跳对应系统页面，另有「应用详情页」兜底行。

### 四、测试（+33）

- `test/ai_context_test.dart`（20 例）：指令块解析（抽出/摘掉、多块合并、非 json 块保留、坏 JSON 提示、无 commands 不算、空回复）；指令人话描述与破坏性判定；课表上下文（学期/周次单双周、今天明天日期星期、课程行字段与排序、考试倒计时、今明备注、四类兜底文案、未开学不显示单双周、无学期提示）；系统提示含协议与「不会立刻执行」。
- `test/ai_service_test.dart`（8 例）：配置清理与「三项齐才算配好」、接口地址三种写法都补成 `…/chat/completions`、Key 留空沿用旧值；响应解析四种（标准 / content 数组 / 兼容 `choices[].text` / 坏数据返回 null）。
- `test/week_parity_test.dart`（5 例）：单双周、week ≤ 0 不显示、超过总周数不显示、总周数未知时按周次本身、与 `weekTypeText` 口径一致。
- 基线 307 → **340**。桥的 35 例因 `describePendingCommand` 改为委托 `describeCommand` 而重跑（三条旧断言逐字保持）。

**未跑命令**：本轮 Bash/Glob/Grep 仍被拒（ripgrep EACCES），`flutter analyze` / `flutter test` 由你执行（命令见文末「待执行的自检命令」，用例数已改 340）。

**analyze 风险点先看这几处**：① `lib/main.dart` 底栏自绘用了 `Stack + Positioned.fill + clipBehavior: Clip.none`，`scheme.shadow` / `withValues` 是 M3 标准 API；② `permission_service.dart` 里 `invokeMethod<Object?>('status')` 后 `raw is Map` 再按字符串键取值（`Map<Object?, Object?>` 的 `[]` 取 String 键合法）；③ `ai_chat_page.dart` 的 `_ChatItem` 是可变对象，在 `setState` 里改字段（不是 const 构造）；④ `IconButton.filled` 与 `FilledButton.tonal` 需要较新的 Material 支持（SDK 3.47 满足）；⑤ `week_view_page.dart` 的 `parityText` 是 `final` 局部变量，`if (parityText != null)` 内的提升合法。

**真机需看**：① 首次打开 App（清数据或卸载重装）→ 进主页后依次弹通知授权 → 精确闹钟说明 → 电池优化说明，每步「跳过」后不再弹；第二次打开不应再有任何权限弹窗；② 设置 → 权限：三项状态与实际系统一致，点未授权项能跳到对应系统页，回来状态刷新；③ 底栏：长按三个按钮都不应再出现名称气泡；中间主页按钮明显更大且凸起；④ 主页右上角「+」→ 手动新建课程 / 导入课表两条都通；⑤ 主页左上角「单周/双周」小标识：翻周时它仍指当前周；界面设置里关掉开关后消失；⑥ 设置 → AI 助手：填智谱 Key 保存 → 底栏 AI 里问「我明天有什么课」应基于真实课表回答；让它「帮我加一条明天交作业的备注」→ 应出现确认卡片，点执行后备注页能看到；删备注类指令应标红并要求单独确认。

## 2026-10-22（学期编辑：当前学期也能改，300 → 307 测试基线，未跑命令）

需求：学期管理页里默认（当前）学期没有编辑入口。本轮给**所有学期**（含当前学期）加上「编辑学期」，可改名称 / 开学日期 / 总周数；改到当前学期时保存后同步内存 + 走与其它数据变更一致的后处理。**改动 4 个文件、新增 1 个测试文件**，无新增依赖、不动表结构，未提交 git。

### 一、表单（lib/widgets/semester_form_dialog.dart）

- `showSemesterFormDialog(context, {Semester? initial})`：传 `initial` 即编辑模式，`initState` 回填名称 / 开学日期 / 总周数，标题「编辑学期」、按钮「保存」；返回 `initial.copyWith(...)`，**保留 id 与 isCurrent**（落库按 id 更新同一行）。不传就是原来的新建模式，导入页（import_page.dart:167）与学期管理页的新建调用点零改动。
- 校验抽成纯函数 `validateSemesterForm({name, weeks})`（名称非空 + 周数 1~30，中文提示文案与原来逐字一致），新建与编辑共用同一套；开学日期仍走 `WeekCalc.alignToMonday` 归一化。**没有另写一套表单或校验。**
- 开学日期确认弹窗（1.2.1 的 `showSemesterStartConfirmDialog`）**只在归一化后的日期与原值不同时才弹**——编辑常是只改名/改周数，每次都弹是噪音；改日期时防错等级与新建一致。

### 二、保存与内存同步（lib/providers/providers.dart）

- 新增 `SemestersNotifier.updateSemester(updated)`：`Dao.updateSemester` → 被改的是当前学期时 `currentSemesterProvider.setDirectly(updated)`（复用导入页改开学日期的现成写法，免 AsyncLoading）→ `reload()` → `displayWeekProvider.clampToTotalWeeks()` → `_notifyDataChanged()`。**非当前学期只改库 + 刷列表**，不多做一次服务联动（它的字段不参与当前数据的任何计算）。
- `_notifyDataChanged()` 是本轮把三处散落的「提醒重排 + 常驻通知 + 小组件」收敛成的一份库内函数；`switchTo` 与 `CourseOverridesNotifier._notifyServices` 改为调用它，行为逐字等价，杜绝将来漏挂某一项。**页面没有自己拼联动。**
- `DisplayWeekNotifier` 新增 `clampToTotalWeeks()`：总周数被改小时原浏览周可能超出范围，而它直接用作 PageView 页码（1.3.1 的教训：越界会崩）。只在越界时收敛，不越界不动用户当前浏览的周——不是「回到本周」那种跳页。

### 三、页面（lib/pages/semester_manage_page.dart）

每个学期的菜单都含「编辑学期」；当前学期仍然**只有这一项**（不给切换/删除，既有约束不变）。`_editSemester` → 表单 → `updateSemester` → 中文 SnackBar「已更新「xx」」/「保存失败：$e」。

### 四、测试（+7）

- `test/semester_manage_test.dart` 新增 2 例（ffi 内存库 + ProviderContainer）：① 编辑当前学期 → `currentSemesterProvider` 内存对象同步（名称/日期/总周数）、`todayWeekProvider` 按新日期重算为 1、浏览周从 20 被钳到 8、库与列表同步且 isCurrent 唯一；② 编辑非当前学期 → 目标学期已改、当前学期状态一字未动。开学日期用「本周周一」构造，与运行日期无关。
- `test/semester_form_dialog_test.dart`（新建，5 例）：`validateSemesterForm` 三组边界（空名/纯空格、非数字/0/-3/31/'20周'、合法含空格）；编辑模式 widget 测——回填 + 原样保存返回带 id 与 isCurrent（日期没改所以不弹确认框）、改名改周数后保存返回更新值。
- **说明**：编辑后的「周视图立刻按新日期/总周数工作」这一层是 Provider 级验证（内存对象 + 下游 todayWeek/displayWeek），没有做周视图的 widget 级渲染验证（该页没有现成的 widget 测试基建，本轮也不宜新建）。

**未跑命令**：本轮 Bash/Glob/Grep 仍被拒（ripgrep EACCES），`flutter analyze` / `flutter test` 由你执行（命令见文末「待执行的自检命令」，用例数已改 307）。

**analyze 风险点先看这几处**：① `SemesterFormDialog` 由 `const SemesterFormDialog()` 改为带可选参数的构造（无 const 要求），原 `const SemesterFormDialog()` 调用点在同文件内已同步；② `_Harness` 测试里的 `find.byType(TextField).first/.last` 依赖对话框里 TextField 的顺序（名称在前、总周数在后）；③ `find.text('20')` 只匹配周数输入框的 EditableText（日期副标题是完整日期串，不匹配）；④ `_notifyDataChanged()` 是库私有顶层函数，只在 providers.dart 内使用；⑤ `clampToTotalWeeks()` 里 `state` 是 `Notifier<int>` 的 state，读写合法。

**真机需看**：① 设置 → 学期管理 → 当前学期卡片右上角菜单只有「编辑学期」（没有切换/删除）→ 改名 + 改开学日期 + 改总周数保存 → 回主页周次与课表立刻按新值走（顶部「第 X 周」、日期范围都要变）；② 编辑一个非当前学期 → 主页课表与周次不应有任何变化，学期管理里那张卡片信息更新；③ 把当前学期总周数改小（如 20→8）且当时正在浏览第 15 周 → 不应闪退，应自动停在第 8 周；④ 编辑当前学期的开学日期后，当天的上课提醒与桌面小组件应按新周次重排（改完等几秒看小组件）；⑤ 只改名不改日期时，不应弹「确认开学日期」弹窗；改了日期才弹。

## 2026-10-22（小部件：HyperOS 预览图 + 尺寸自适应 + 负一屏复核，300 测试基线不变，未跑命令）

三项都做完，**只动 Android 原生 3 个文件**（`CourseWidgetProvider.kt`、`course_widget_info.xml`、`course_widget.xml` 仅加一行同步常量的注释），**Dart 零改动**（payload 仍最多 4 行，布局结构与既有 id 未动），未提交 git。

### 一、选择器预览图（HyperOS 不再回退应用图标）

`res/xml/course_widget_info.xml` 加了一行 `android:previewImage="@drawable/widget_preview"`，指向既有的 `res/drawable-nodpi/widget_preview.png`（400×300，仿真实部件）。`previewLayout` 保留、其余属性一个没动：AOSP / Android 12+ 继续用 `previewLayout`，HyperOS 的选择器与负一屏列表走 `previewImage`，两条路互不冲突。

### 二、尺寸自适应（最后一行不再被底边切一半）

- `CourseWidgetProvider.kt` 新增 `WidgetMetrics`：与 `course_widget.xml` 逐条对齐的 dp 常量——根 padding 28（14×2）、顶栏 22、单行 36（色条固定高）、行间距 12、footer 行 16 + 间距 8。**改布局必须同步这组常量**，注释里已写明。
- `onUpdate` 逐实例读 `AppWidgetManager.getAppWidgetOptions(id).getInt(OPTION_APPWIDGET_MAX_HEIGHT)`，`render` 按 `planRows` 先扣 padding/顶栏/footer（尾注 + 最多 2 行备注），剩下的除以行块高（48dp）得到能完整放下的行数；放不下的行 `GONE`，溢出节数并进 footer。
- footer 文案合并：Dart 本来就有「还有 N 节课」（总课次 >4 时），若裁行后直接追加会出现「还有 2 节课 还有 1 节课」；`mergeFooter` 认出这个格式时把数量相加，其它文案才原样追加「还有 X 节课」。
- **优先级**：footer/备注先占位（备注优先保留），空间不够先砍课程行；只有极端缩档（可用内容连「1 行 + footer」都放不下，约 110dp 最小高度）才反过来保 1 行课程、隐藏 footer，避免只剩标题的空壳。
- 新增 `onAppWidgetOptionsChanged`：手动拖拽尺寸后重渲染该 id。这里拿不到 `HomeWidgetProvider` 注入的 SharedPreferences，故发一条显式 `ACTION_APPWIDGET_UPDATE` 广播回自己，复用 `onReceive → onUpdate` 的取数链路（不硬编码插件偏好文件名），`dbg_widget_*` 自检记录照旧写入。
- **容错**：`maxHeightDp()` 全程 `runCatching`，options 缺失/为 0/id 失效一律返回 null → 回退升级前「4 行全显」；尺寸计算不参与任何 RemoteViews 必填动作，绝不因算尺寸变黑框。

### 三、负一屏可用性复核结论

- `AndroidManifest.xml` 的 provider receiver 是标准完整写法，**本轮未改**：`exported="true"`（宿主在别的进程，必须导出）、`intent-filter` 含 `android.appwidget.action.APPWIDGET_UPDATE`、`meta-data android.appwidget.provider` 指向 `@xml/course_widget_info`、`widgetCategory="home_screen"`。没有 `enabled=false`、权限限制或会把部件从标准列表排除的配置。
- **添加路径**：负一屏 → 添加小部件 → 安卓小部件 → 小马课表（列表显示名可能为「今日课程」，取决于宿主读 receiver label 还是 app label）。
- 不需要厂商审核或任何额外声明；HyperOS 的「小米小部件」精品画廊是另一套上架体系，与本路径无关。

**未跑命令**：本轮 Bash/Glob/Grep 被拒（ripgrep EACCES），连 pub cache 的 Read 也被拒，`flutter analyze` / `flutter test` 由你执行。Dart 零改动，300 个用例基线不变，预期全绿；Kotlin 未编译验证。

**analyze/build 风险点**：① `AppWidgetManager.ACTION_APPWIDGET_UPDATE` / `EXTRA_APPWIDGET_IDS` 是框架常量，拼写按 Android SDK 标准；② `Bundle.getInt(key, default)` 与 `getAppWidgetOptions` 均为 API 16+ 可用（项目 minSdk 远高于此）；③ `WidgetMetrics` 是类内嵌套 object、`const val` 合法；④ `onAppWidgetOptionsChanged` 重写的是 `AppWidgetProvider` 的公开回调，`newOptions` 未使用只会有未使用参数警告。

**真机需看**：① HyperOS 小部件选择器里「小马课表/今日课程」显示的是部件预览图而不是应用图标；② 添加后上下拖动高度：最后一行完整显示，不再被切一半；拉大后行数自动变多；③ 缩到最小时显示 1 行课程（footer/备注可能被隐藏，这是极端档的保底，属预期）；④ 当天有 5 节课时，4 行 + footer「还有 1 节课」；把高度缩到只放 2 行时 footer 应为「还有 3 节课」（数量合并，不是两句）；⑤ 老系统/取不到 options 时仍显示 4 行不裁（可用设置页「部件状态」确认更新到达）；⑥ 负一屏按上面的路径能添加并正常显示。

## 2026-10-22（AI 桥接上执行器，300 测试基线，未跑命令）

把 GitHub 私有仓当**命令信箱**接到上一包的 `CommandExecutor` 上：**新增 4 个文件、改 3 个文件**（`lib/utils/bridge_codec.dart`、`lib/services/bridge_service.dart`、`lib/pages/bridge_page.dart`、`test/bridge_codec_test.dart`；改 `lib/main.dart`、`lib/pages/settings_page.dart`、`ARCHITECTURE.md`）。**无新增 pub 依赖**（HTTP 复用 `dart:io` 的 HttpClient，与 ChannelService 同款写法），**未动表结构**（全部走既有 `app_settings` 键值表），未提交 git。

### 一、信箱协议（已写进 ARCHITECTURE「1.3.6」专节，外部 AI 照此对接）

- `commands/<id>.json`（外部 AI 写）：`{id, createdAt, note?, commands:[…执行器指令…]}`。
- `results/<id>.json`（App 写）：`{id, executedAt, status, results:[{index, type, success, message, state}]}`，state ∈ `executed/pending/rejected`，status ∈ `done/partial/awaiting_confirm`。
- `state/snapshot.json`（每次同步后重传）：当前学期 + 全部课程精简字段 + 按日期分组的备注 + 单独一份考试清单。**只有课表与备注数据，结构上不可能带出设置/令牌**。
- `<id>` 字符集收紧到 `[A-Za-z0-9][A-Za-z0-9._-]*`（≤64）：id 要被拼进 API 路径写回，含 `/` 或 `..` 就能改写仓库任意路径，一律拒绝并记录一条中文失败。
- 已处理 id 存 `processed_command_ids`（**最近 200 条**），避免重复执行。

### 二、服务层（lib/services/bridge_service.dart）

- `syncNow()` 六步：没配全 → 返回 unconfigured（不报错不弹 UI）；列 `commands/`（404 视为「空信箱」不算错）；过滤已处理；逐个读取解析后**按 createdAt 升序**；逐批 → `splitByDestructive` 拆分 → 非破坏立即交给执行器、破坏指令入本地队列 → 写回 results；最后上传快照（先 GET 取 sha 再 PUT 更新，没有则新建）；并把「时间 + 摘要」写进 `last_bridge_sync`。
- **并发只有一轮**：`syncNow` 内部共享 Future（同 `NotificationService.initialize` 的思路），页面点「立即同步」与启动静默同步相撞时不会各跑一遍重复写库。
- 写回 results 一律**先 GET 后 PUT**：GET 同时拿到 sha（已存在文件的 PUT 必须带）与旧条目，按 index 覆盖合并后再写——于是「整批首次写回」和「用户事后确认某几条」走同一条路径，后者不会冲掉先前的结果。
- 容错：每个文件/每批/快照上传各自 try/catch，错误进摘要（「处理 2 个指令批，执行 5 条，1 条待确认，2 个小错误」），不中断整轮。超时 15s、连接 10s。
- **副作用留调用方**：服务不碰 Riverpod/BuildContext，只回 `changed` 标记；provider 失效 + 提醒重排 + 常驻通知 + 小部件四处联动在 `BridgePage._applyBridgeChanges` 与 `HomeShell._applyBridgeChanges` 各一份（注释互指）。
- 令牌只在 `Authorization: Bearer` 请求头出现；错误文案只带状态码 + 截断 120 字的异常描述，不打印 URL。**已知边界：备份 JSON 走 `getAllSettings()`，会带上 `bridge_token`** —— 已在 BridgePage 底部明文写「别外发备份文件」，也在 ARCHITECTURE 的 app_settings 键说明里记了一行。

### 三、页面

- 设置页「备注」之后新增「AI 桥」分区 → `/bridge`。
- BridgePage 三块：配置区（owner/repo/token，token 遮挡 + 眼睛按钮，**留空表示不改令牌**）/ 状态区（上次同步时间 + 摘要，立即同步按钮同步中禁用并转圈，完成后刷新状态 + 触发联动）/ 待确认区（`describePendingCommand` 输出人话，如「删除备注 2026-10-23 交作业」，每条「执行」「拒绝」，两者都会再走一次写回并出队）。
- App 启动首帧后（`HomeShell._runStartupTasks` 并发列表）**静默同步一次**：未配置立即返回，失败只 debugPrint，不打扰用户。为此 `HomeShell` 改成 `ConsumerStatefulWidget`（要 ref 才能失效 Provider）。

### 四、测试

`test/bridge_codec_test.dart` **新增 35 例**（纯函数，不碰网络与数据库）：id 安全字符集（含 `../../etc/passwd` 被拒）、指令批解析与四种坏数据、文件名兜底 id、非对象元素丢弃、createdAt 排序（坏日期排最前）、destructive 拆分（含未知类型按非破坏、缺 type 兜底）、三种 status 判定 + 拒绝算失败、按 index 合并（新覆盖旧、其余保留、文档损坏兜底）、`buildResultsJson` 字段、队列往返与非法元素、人话描述三种、配置清理去斜杠 + 令牌兜底、快照字段/todayWeek=7/备注分组/**「不含 token」隐私断言**/无学期兜底。基线 265 → **300**。

**未跑命令**：本轮 Bash/Glob/Grep 全被拒（老问题，ripgrep EACCES），只有 Read/Write/Edit 可用，`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」，用例数已改 300）。

**analyze 风险点先看这几处**：① `lib/main.dart` 把 `HomeShell` 改成 `ConsumerStatefulWidget`（`ConsumerState<HomeShell>`），build 与若干处 `mounted` 判断沿用原写法，理论上零影响；② 页面里所有 Http 相关 API（`HttpClient.openUrl` / `req.headers.set` / `ContentType.json` / `client.close(force:)` / `Future.ignore()`）都是 dart:io 与 dart:async 的标准用法；③ `withValues` 之类新 API **没有用**（卡片底色改回 `surfaceContainerHighest`）；④ `AppSpacing` 只有 xs/s/m/l 四个常量，页面底部留白直接写 24（规范里允许的「微调档」）；⑤ 记录类型 `(status:, json:, error:)` 需要 Dart 3（SDK ^3.13.5，满足）。

**真机需看**：① 建一个私有仓 + 细粒度令牌（Contents 读写），App 里填好点「立即同步」→ 应提示「没有新指令」且仓里出现 `state/snapshot.json`；② 手写一个 `commands/hello-1.json`（add_note）→ 同步后应出现备注且 `results/hello-1.json` 状态 done；③ 混一条 delete_note → App 待确认区出现「删除备注 xxx」，点「执行」后备注消失、`results` 从 awaiting_confirm 变成 done；点「拒绝」→ state=rejected、status=partial；④ 同一个 id 再同步一次不应重复执行（看 processed_command_ids）；⑤ **打断网/写错令牌**同步：不应闪退，状态区显示失败摘要。

## 2026-10-22（AI 备注 + 指令执行器地基层，265 测试基线，未跑命令）

按两份配套需求做完：**新增 5 个文件、改 10 个文件**，唯一的表结构变化是 notes 表（走 v2→v3 版本升级），未提交 git。

### 一、备注功能

1. **数据层**：`lib/models/note.dart`（Note：id/date/content/createdAt）；`db_helper` 版本 2→3，新增 `_createNotesTableSql` + `idx_notes_date`，`createSchema`（新装）与 `onUpgrade(oldVersion<3)`（老库无感升级）都建这张表；`dao` 新增 `getAllNotes`（日期升序、同日按 id）/ `getNotesByDate` / `getNotesByDates(List)`（小部件一次取 7 天，空列表直接返回不拼非法 SQL）/ `insertNote` / `updateNote` / `deleteNote`（返回受影响行数）。
2. **备注页**：`lib/pages/notes_page.dart`（路由 `/notes`），日期倒序分组（标题「今天/明天/yyyy年M月d日 周X」）、右下角加号新增（日期选择器 + 内容必填校验）、点卡片编辑、删除按钮弹二次确认；空状态/加载失败走 EmptyState，圆角间距走 AppRadii/AppSpacing，与设置页风格一致。设置页在「数据管理」之后、「外观」之前加了「备注」分区一行入口。
3. **常驻通知**：新增 `lib/utils/note_notice.dart` 纯函数（`buildNoteNotice`：有今天的显示今天的、有明天的一并带「明天：」前缀、条数多合并多行、都没有返回 null）。`notification_service` 新增渠道 `note_ongoing_channel`（名「备注」，importance=low、不震动、不显角标）+ id `0x7FFFFFFE`（不与课程提醒/自举冲突）+ `refreshNoteNotice()`（ongoing=true、BigTextStyle 多行、无则 cancel）。**刷新时机**三条：备注增删改（NotesNotifier 末尾）、App 启动（HomeShell 首帧任务里的 `rescheduleAll` 内部末尾调用）、0 点自举重排那条链路同一进入口。跨天仍需打开一次 App 才刷新——与常驻通知/小部件同属已知限制，没假装做后台 0 点重排。
4. **小部件**：payload 新增可选 `notes`（字符串数组，最多 `kWidgetMaxNotes=3`），按**实际展示那天**取值（今天没课顺延到明天时备注也跟着换），逐日 payload 各带各日；WidgetService 用 `getNotesByDates` 一次取 7 天分桶，读失败吞掉按「无备注」继续（不让备注拖垮整份 payload）。Kotlin `CourseWidgetProvider` 新增 `notes` 字段 + `parseNotes`（最多读 3 条、非数组/缺字段都容错）+ `notesText`（最多 2 行、首行「备注：」前缀），把尾注与备注拼进现有 `widget_footer`，**没改任何 XML/没加布局**，老 payload 没有 notes 键时默认空列表、渲染逐字不变。

### 二、指令执行器（lib/services/command_executor.dart）

- `CommandExecutor.execute(Map)` / `executeAll(List<Map>)`：逐条执行并返回 `CommandResult`（type / success / message 中文摘要或原因 / destructive / data）；**只依赖 Dao，不依赖 Riverpod 与 BuildContext**，provider 刷新、通知重排、备注通知刷新、小部件刷新由调用方负责（已写进类注释）。
- 一期五条：`add_course`（全字段、周次支持「1-8单周」字符串与数组，落库前跑 `ConflictDetector`，**冲突只提示不拦截**）、`set_course_color`（courseId 或 courseName 定位，重名多门批量全改，限定当前学期）、`add_note`（date 默认今天 + content）、`delete_note`（按 id，registry 标 destructive=true）、`add_exam`（给指定课程写 `Course.examDate`，可带 HH:mm）。
- `CommandRegistry` 集中登记 destructive（只有 delete_note 为 true），供后续桥的确认策略读取；参数缺失/非法 → 该条失败给中文原因（`_CommandError` 内部抛、`execute` 兜），**单条失败不中断整批**。
- **停课/调课留给下一包**：仓库已有完整机制（`course_overrides` 表 + `CourseOverride.cancelFlag(-1)` 停课 + `Dao.upsertOverride/deleteOverride` + `CourseOverridesNotifier` 的四处联动），已在 ARCHITECTURE 记一笔，下一包直接加 `stop_course` / `move_course` 即可，本轮没新造。**另记**：仓库没有独立 Exam 模型/考试表，考试就是 `Course.examDate`，`add_exam` 按此对齐。

**测试**：新增 `test/note_dao_test.dart`（7 例，ffi 内存库跑真实 SQL）、`test/note_notice_test.dart`（8 例纯逻辑）、`test/command_executor_test.dart`（19 例，ffi 内存库覆盖五条指令正常/异常路径与批量容错）；`test/widget_data_test.dart` 改 1 例（JSON 字段清单多 `notes`）+ 新增 4 例当日备注。基线 227 → **265**。

**未跑命令**：本轮 Bash/Glob/Grep 全被拒（老问题，ripgrep EACCES），只有 Read/Write/Edit 可用，`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」，用例数已改 265）。**无新增 pub 依赖。**

**analyze 风险点先看这几处**：① `AndroidNotificationDetails` 的 `ongoing` / `BigTextStyleInformation(bigText, contentTitle:, summaryText:)` 签名凭 flutter_local_notifications 22.x 记忆写的，`autoCancel` 在 Android 明细类上是有的，若报未知参数按提示处理；② `AndroidNotificationChannel` 的 `enableVibration`/`showBadge` 与上一轮新增的自举渠道同款写法，若上一轮 analyze 通过则本轮同理；③ Kotlin 的 `arr.optString(i, "")` 是 org.json 的老用法、一直可用，`minOf(arr.length(), MAX_NOTES)` 正常；④ notes 表的列名（`date`/`content`/`createdAt`）与 `Note.toMap` 的键逐字一致。

**真机需看**：① 老用户升级 App 后打开「设置 → 备注」能直接用（说明表补建成功、没闪退）；② 加一条今天的备注 → 通知栏出现「今日备注」常驻通知且滑不掉，再删掉 → 通知消失；③ 开关一次「上课提醒」/切学期 → 备注通知还在（验证 cancelAll 后重建）；④ 桌面小部件今天有课时底部出现「备注：xxx」，明天有课则跨天后自动跟上，没有备注时与升级前一个样（重点：不黑框）；⑤ 备注页日期改到别的一天后立刻重新分组。

## 2026-10-22（通知窗口 30 天 + 自举静音渠道 + 小部件跨天切换，227 测试基线，未跑命令）

按他给的三项逐条改完，**改动文件 5 个**（无新增依赖、不动小部件布局 XML 与 payload 字段、未提交 git）：

1. **提醒窗口 7 → 30 天**（`lib/services/notification_service.dart`）：`_windowDays = 30`（今天 + 未来 29 天）。ID 安全性粗算：每次 `rescheduleAll` 先 `cancelAll` 再从 1 递增，上限 = 30 天 × 每天节次数（满课 12 节约 360），与 `kBootstrapNotificationId = 0x7FFFFFFF`（21.4 亿）差 6 个数量级，不会溢出/撞号/重复；AlarmManager 活跃闹钟上限约 500，360 仍在安全区（已写进常量注释）。课程提醒的循环与渠道/样式未动。
2. **0 点自举通知换独立静音渠道**（同文件）：新增常量 `kBootstrapChannelId = 'course_bootstrap_silent'` / `kBootstrapChannelName = '课程提醒自举'`，新增 `_ensureBootstrapChannel()`（importance=low、enableVibration=false、showBadge=false，初始化时创建），`_bootstrapDetails()` 改走新渠道并补 `channelShowBadge=false`（importance/priority=low、playSound/enableVibration=false 保留）。**未给渠道传 `playSound`**：该参数类型随插件版本在 bool / PlaySound 枚举间变动，而 importance=low 在 Android 8+ 本就不响铃；若 analyze 确认是 bool，直接补一行 `playSound: false` 即可。
3. **小部件跨天自动切换**：
   - Dart：`lib/utils/widget_data.dart` 新增纯函数 `widgetDayKey(d)`（yyyy-MM-dd）与 `buildWidgetPayloadDays(...)`（默认 7 天；offset=0 用真实 now → 与 `widget_payload` 逐字一致，未来某日用该日 00:00 作 now → 当天课程完整入选）。`lib/services/widget_service.dart` 在原有 `widget_payload` 写入 + 回读校验之后，再写 `widget_payload_days`（JSON 对象：日期键 → 该日 payload，值与 `widget_payload` 同结构）。原逻辑零改动。
   - Kotlin：`CourseWidgetProvider.onUpdate` 改调新增的 `resolvePayload(data)`——先按设备本地今天日期（SimpleDateFormat "yyyy-MM-dd" + Locale.US）从 `widget_payload_days` 取值，取不到（无键 / 日期不在范围 / 解析失败）回退 `widget_payload`；全程 `runCatching`，复用原 `parsePayload`。`dbg_widget_*` 自检写入与布局渲染未动。
4. **测试**：`test/widget_data_test.dart` 新增 6 例（键为今天起 7 天、今天那份与 buildWidgetPayload 逐字一致、未来某日 00:00 整天入选且顶栏该日、无课顺延次日、整体可 JSON 编码且字段齐全、无学期时 7 份兜底）。既有 221 例未动 → 227。
5. **文档**：ARCHITECTURE.md 新增「1.3.4」专节（文件表 + 6 条设计决策）+ 工具类补 WidgetData 一行；本文件顶部本节。

**未跑命令**：本轮 Bash/Glob/Grep/WebFetch 全被拒（同踩坑 #6/#12，ripgrep EACCES），`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」，用例数已改 227）。

**真机需看**：① 开提醒后设一节 20 分钟后的课能响；改课/删课后旧提醒不响；② 半夜 0 点不再被自举通知弹醒（系统通知设置里应出现「课程提醒自举」渠道且重要性=低）；③ 桌面小部件跨天：今晚看一眼明天的内容 → 不打开 App 直接改系统日期到明天（或等一天）→ 小部件应显示明天那份；④ 长假场景：连续几天不开 App，小部件内容随日期走；⑤ 升级后首次打开 App（widget_payload_days 还没写）小部件应仍按旧逻辑正常显示不黑框。

## 2026-10-22（导入周次推断 + 手动建课冲突检测，221 测试基线，未跑命令）

按他给的两项补强逐条改完，**改动文件**：

1. **导入时推断学期总周数**：新建纯函数 `lib/utils/week_infer.dart`（`WeekInfer.maxWeek` 取草稿里最晚周次、`inferredTotalWeeks` 超过总周数才返回建议值、否则 null）。`lib/pages/import_review_page.dart`：顶部新增提示条（仅推断值 > 目标学期总周数时出现，每次 build 重算，草稿被编辑/删除后自动出现或消失），文案「导入的课程最晚到第 X 周，超过当前学期的总周数 Y 周」+ 默认勾选的复选框「保存时把总周数调整为 X 周」（`_extendTotalWeeks` 默认 true）；`_importAll` 在课程落库 + `coursesProvider.reload()` 之后按勾选 `Dao.updateSemester` 改总周数，成功则在完成弹窗多一行「《学期名》的总周数已调整为 X 周（原 Y 周）」。同步内存状态沿用导入页改开学日期的现成写法：当前学期 `setDirectly(updated)`（todayWeekProvider 与周视图的钳制随之生效）+ `semestersProvider.reload()`；失败只 debugPrint，不回滚已导入课程。
2. **手动建课/改课冲突检测**：`lib/pages/course_edit_page.dart` 的 `_save()` 落库前新增预检——`ConflictDetector.detect(candidate, coursesProvider 课程, ignoreCourseId: _editId)`，语义与导入链路完全一致（同星期 + 周次有交集 + 节次重叠），候选课 weeks/weekType 直接取表单值不做换算。有冲突弹 AlertDialog 列出 `describe()`（课程名 + 周次 + 星期 + 节次），按钮「返回修改」（不落库）/「仍要保存」（照旧 addCourse/updateCourse）。无冲突路径零变化。
3. **测试**：新建 `test/week_infer_test.dart`（5 例：空草稿/空周次 0、多草稿取最大、单双周不改最晚周次、不超过总周数 null、超过返回推断值）；`test/conflict_detector_test.dart` 补 2 例（改课时池里含自身只检出对方、周次端点相交算冲突）。既有 214 例未动。
4. **文档**：ARCHITECTURE.md 新增「1.3.3」专节（文件表 + 5 条设计决策）；CHANGELOG.md 顶部加「未发布」两条用户可见说明。

**未跑命令**：本轮 Bash/Glob/Grep 全被拒（同踩坑 #6/#12，ripgrep EACCES），`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」）。无新增 pub 依赖、未动表结构。

**真机需看**：① 导入一份排到第 21 周及以后的课表 → 核对页顶部出现提示条且复选框默认勾选 → 保存后设置/学期管理里总周数变成推断值、周视图能翻到那一周；② 取消勾选后保存 → 学期总周数不变、超出周次的课不显示（预期行为）；③ 手动新建一门与已有课撞时间的课 → 弹冲突窗、点「返回修改」不落库、点「仍要保存」同格叠放；④ 编辑已有课程只改教室/颜色 → 不应弹冲突窗（自身被排除）。

## 2026-10-22（启动提速，214 测试基线不变，未跑命令）

用户反馈「打开 App 进主页慢」，授权必要时直接删掉启动动画。五项改动（**无新增依赖、不动课表数据与业务逻辑**）：

1. **删应用内启动页**：`lib/main.dart` 的 `initialRoute` `'/splash'` → `'/'`，删 `/splash` 路由与 `SplashPage` 的 import。**省掉 900ms 停留 + 400ms 淡入的人为延迟（合计约 1 秒）**。首屏窗口改由 Android 原生 `LaunchTheme` 的 `launch_background` 兜住（styles.xml 未动，不会白闪）；`'/'` → `_RootGate` 与 `WeekViewPage` 数据未就绪时本就各有加载态，首帧不是空白页。
2. **`lib/pages/splash_page.dart` 已无引用，需手工删除**：本轮 Bash 被拒，我删不了文件，请执行 `rm lib/pages/splash_page.dart`（`AppRadii.logo` 常量会随之无用，保留无害）。
3. **启动初始化瘦身**：`_initServices()` 只留 `FontsService.init()`（防首帧字体闪烁，必须在 runApp 前）；通知初始化拆成 `_initNotifications()`，挂在 `runApp` 之后的 `WidgetsBinding.instance.addPostFrameCallback` 里 `unawaited` 跑，try/catch + debugPrint 的容错风格与上一轮一致（失败只打日志、不阻断、不写 last_error_log）。
4. **通知初始化改共享 Future**（`lib/services/notification_service.dart`）：`initialize()` 由 bool 标记改 `_initFuture ??= _initialize()`。因为挪到首帧后，`rescheduleAll()` 可能先跑——旧写法会「标记已初始化但插件未就绪」就去排期、异常被吞导致提醒静默不排；共享 Future 后两者共用一次初始化，语义等价于原来的串行。
5. **主页启动联动并行化 + 挪后**：`HomeShell.initState` 的提醒重排 / 常驻通知 / 小组件刷新 / QuickActions 注册全部进 `addPostFrameCallback`，由 `_runStartupTasks()` 用 `Future.wait` 并发触发（外层 try/catch 兜底），不再与课表首帧抢 isolate；`WeekViewPage.initState` 的 `_loadChannel()`（公告/更新，读本地状态文件 + PackageInfo 通道）同样挪到首帧后，函数内 5 项读取改「一次发起、逐个 await」并行。

**未跑命令**：本轮 Bash/Glob/Grep 全被拒（同踩坑 #6/#12），`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」）。既有 214 个用例不涉及启动路径，`SplashPage` 无测试引用，预期全绿。

**真机需看**：① 冷启动到看见课表的耗时（对比改前，重点看是否还有肉眼可感的停顿）；② 启动瞬间无白闪/黑闪（原生启动背景覆盖）；③ 首次启动走引导页时课表首帧是加载圈不是白屏；④ 提醒仍会正常重排（通知初始化挪后是否真的排上了：进设置开提醒 → 看当天是否有通知；也可 `adb logcat` 搜「通知重排失败」确认无异常）。

## 2026-10-22（五项防御性修复，214 测试基线，未跑命令）

按他给的五项清单逐条改完，**改动文件**：

1. **周次越界钳制**：`lib/utils/week_calc.dart`（新增 `WeekCalc.clampForPage`）、`lib/pages/week_view_page.dart`（`initState` 的 `initialPage`、`_goToday`）、`lib/providers/providers.dart`（`DisplayWeekNotifier` 的 build/setWeek/goToday + `_totalWeeks()`）。`WeekCalc.currentWeek` 语义保留不变（允许 > totalWeeks），只在消费端钳到 [1, totalWeeks]；学期未加载（totalWeeks=0）保持原行为只保下限 1。
2. **编辑页防崩**：`lib/pages/course_edit_page.dart` 的 `_load()` —— `firstWhere` 改循环安全查找，找不到时 SnackBar「课程已不存在」+ `Navigator.pop(context)` 后 return。
3. **全局异常兜底**：`lib/main.dart` —— `main()` 改 `void main()` + `runZonedGuarded` 包住整个启动；`FlutterError.onError`（presentError 后记日志，不转发 zone 避免重复）；`ErrorWidget.builder` 换中文兜底界面 `_FriendlyErrorWidget`；两条路都写 `Dao.setSetting('last_error_log', '[时间] 摘要')`，写库失败吞掉；`NotificationService.initialize` / `FontsService.init` 抽进 `_initServices()` 各自 try/catch，失败只 debugPrint 不阻断 runApp。
4. **开学日期安全解析**：`lib/models/semester.dart` 新增 `startDateParsed`（`tryParse` 失败回退「今天所在周一」，理由已注释）。11 处 `DateTime.parse(<semester>.startDate)` 全换掉：providers(todayWeekProvider)、week_view_page(×2)、next_class、reminder_plan、widget_data、ics_export、share_image_page、free_time_page、import_page(×2)；与学期无关的 `DateTime.parse` 未动。
5. **导入落库事务**：`lib/database/dao.dart` 新增 `runInTransaction<T>()` 并给 `insertCourse/updateCourse/deleteCourse` 加可选 `DatabaseExecutor? txn`（不传时行为不变，旧调用点零影响）；`lib/pages/import_review_page.dart` 的删除+插入整段包进一个事务，计数以记录返回；事务后的 `coursesProvider.reload()` 与作息校准保持在事务之外原样。

**未跑命令**：本轮 Bash/Glob/Grep 全被拒（同踩坑 #6/#12），`flutter analyze` / `flutter test` 由他执行（命令见文末「待执行的自检命令」）。无新增 pub 依赖、未动表结构与 UI 文案风格。

## v1.3.0+14（2026-10-21，教务官网导入，214 测试）

- 新增 webview_flutter ^4.14.1；AndroidManifest 开 usesCleartextTraffic（部分学校教务走 http/混合内容）。
- WebImportPage（pages/web_import_page.dart）：地址栏（默认 https://jwxt.zjnu.edu.cn/ 可改，该域名未实证、他若打不开在地址栏改）+ 前进/后退/刷新 + 步骤提示 + 悬浮「抓取本页课表」。抓取脚本遍历主文档与同源 iframe 的 table，逐格回传 {t, rs, cs}；Android 回传是 JSON 编码字符串，页面里先解一层再 parse。账号密码只在学校网页输入，App 不碰。
- WebScheduleParser（utils/web_schedule_parser.dart）：展开 rowspan/colspan → 找含 ≥4 星期名的表头行 → 列=星期、行首标签或顺序推节次、单元格内 (N-M节) 优先 → 行状态机切分一格多课 → WeekParser 落周次（含单/双后缀）→ 字段行与残余文本拆地点/教师（地点词尾防误判）→ 去重。认不出时回 tables/cells 计数供定位。测试 5 项（浙师大式网格/一格两课/跨行/单行+双周/无表头）。
- 入口：import_page 原「即将上线」占位转正，走 _guardedImport → _importWeb → 核对页（与 ICS/OCR/PDF 同一管线）。
- 待真机验证：他登录浙师大教务实际抓一次（域名、登录页 WebView 兼容、课表页真实 DOM 三件套都没实证）；不适配就让他发课表页截图，按真实结构迭代解析器。


## v1.2.7+13（2026-10-21，小部件黑框救援，209 测试）

- 背景：他反馈桌面小部件 1.2.2 后变黑框报「载入窗口小部件时出现问题」、内置刷新无效；此前（≤1.2.1 简单版）正常。最初误传为负一屏问题，实为正常桌面。
- 改动：course_widget.xml 色条 View→ImageView(scaleType=fitXY)，分数 sp（12.5/14.5/11.5）→整数；Provider 去掉唯一的反射动作 setInt("setBackgroundColor")，改 setImageViewBitmap(6×54 纯色位图，按色缓存）。其余数据契约/结构不动。
- 自检：Provider 在 onUpdate 末尾把 dbg_widget_ts/ids/error 写回 HomeWidget 偏好；WidgetService.debugStatus() 读取，设置页刷新入口下有「部件状态」行。注意：宿主侧 apply 失败应用侧抓不到，error 只覆盖 Provider 侧异常——真机若仍黑框，结合 ts/ids 判断更新是否到达。
- 负一屏结论（同日调研）：安卓原生小部件经小部件中心「搜索—安卓小部件」可加进负一屏（无需审核）；「小米小部件」画廊需上架商店+平台审核，自用不走。


## v1.2.5+11（2026-10-21，真机反馈 4 项，209 测试全绿）

- **横线挂开关**：_GridArea 的 _FullWidthLinesPainter 层加 `if (ui.showGridLines)`（1.2.3 统一横线时漏挂；竖线本来就受控）。轴/网格间的 VerticalDivider 是结构线保留。
- **新默认值**：UiSettings 构造默认 + fromEncoded 缺失回退同步改为 showGridLines=false、colorSchemeId='macaron'、themePresetId='cocoa'、autoFitHeight=true（已存过键的用户不受影响）。注意连带：themePresetById 的 orElse 回退仍是列表首项 forest（与「默认预置」是两回事，测试分别覆盖）；copyWith 清除自定义色后期望种子 = 可可棕 0xFF8A6A52。
- **今天列边框**：删 _WeekGrid 的 α0.05 淡色 ColoredBox；在页 Stack 最末加整列边框（primary 1.5 + 圆角 6，top=0 高 totalHeight，IgnorePointer），highlightDay 的计算/传参未动。
- **当前周跟随**：DisplayWeekNotifier 加 _pinned 机制——未手动切周时 build() watch todayWeekProvider（学期后到自动纠正），setWeek 定住，goToday 解定；主页已有的 displayWeek→PageView 同步监听负责把页面跳过去。根因是旧 build() 一次性 read 撞上学期未加载（todayWeek=0 兜底成第 1 周）。


## v1.2.4+10（2026-10-21，应用完整性补全，209 测试全绿）

- **公开通道**：新建 GitHub 公开仓 jieke7k7k/xiaoma-app-channel（只放 channel.json：latest{versionName,versionCode,notes,downloadUrl,releaseUrl}+announcements[{id,title,body,date,level}]，App 匿名读 raw URL）。源码仓保持私有。发布公告/新版 = 改这个文件推送（本地克隆在 ~/workspace/xiaoma-app-channel）。MCP 建仓 403 无权限，仓库是浏览器建的、文件走 git SSH 推。
- **ChannelService**（services/channel_service.dart)：parseChannel/hasNewerVersion 纯函数可测；fetch 用 dart:io HttpClient（8s 超时）；状态存文档目录 channel_state.json（cache/lastCheckAt/seenIds/dismissedIds/dismissedVersionCode）；静默检查节流 20h。新依赖 package_info_plus、url_launcher、quick_actions。
- **关于页**（pages/about_page.dart，路由 /about，设置页「关于」分区入口）：版本读 PackageInfo；检查更新手动触发 + 有新版弹窗（notes + 去下载 launchUrl downloadUrl)；公告入口带未读 Badge；更新日志 /changelog（pubspec assets 加了 CHANGELOG.md，页面手写简易解析渲染）；开源许可走 showLicensePage；隐私说明是页内弹窗；问题反馈/项目主页都指向公开通道仓（私有仓外人打不开）。
- **主页接入**:WeekViewPage initState _loadChannel（缓存垫帧 + 节流静默刷新）；更新横幅与公告横幅共用 _ChannelBanner（tertiaryContainer)，插在状态条下方；重要公告未读第一条 postFrame 弹窗一次，确定即 markSeen。
- **快捷入口 B1**:HomeShell initState 注册 QuickActions(shortcut_new→/course-edit 裸推、shortcut_import→/import)，图标是 res/drawable 两支 vector (ic_shortcut_new/import)。注意 HomeShell 经 _RootGate 在引导后才建，首启当天快捷入口不注册（可接受）。
- **首次引导 B2**:_RootGate（main.dart）watch onboardingDoneProvider（providers.dart,Dao 键 onboarding_done）；未看完显示 OnboardingPage 三页（导入/小部件/备份），跳过/完成都落库放行；读标记失败直接进主页不挡路。
- **数据管理 B3**:DataManagePage（/data-manage，设置「数据管理」分区入口）：占用（DB 文件 + fonts 目录）、备份/恢复（复用 BackupCodec/BackupService 同设置页口径）、恢复出厂（两次确认 → DbHelper.resetAllData 关库删文件 → 删 fonts 目录与 channel_state.json → _refreshAll invalidate 主力 providers + 通知/小部件重排 + pop 回根）。重置后 createSchema 自动重播默认学期；onboarding 标记随库清掉、引导重现（出厂语义）。
- 待真机验：检查更新全链路（通道已含 1.2.3，1.2.4 发布后我会把通道 latest 更新为 1.2.4——届时 1.2.3 用户应能收到更新提示，正好实测）、公告横幅/弹窗、快捷入口图标、引导只出现一次、恢复出厂。


## v1.2.3+9（2026-10-21，反馈 4 项 + 优化 3 项，205 测试全绿）

- **图层重排（A1+A2)**：_GridArea 的 Stack 改为 分隔带（最下）→ _FullWidthLinesPainter 全宽横线（中）→ Row 轴+课表（最上）。横线收归一层统一绘制（行界 + 分隔带上下边，0.5/outlineVariant/drawLine)——此前轴单元格用控件 Border（实心偏粗）与网格 CustomPaint 描线（抗锯齿偏虚）同宽不同貌，接缝如错位（用户纠正：非位置错位、是线宽不一）。_TimeAxis 单元格已删自带底边框；_GridPainter 只剩竖线。带子沉底后跨带长卡（周六实验室）完整压住带体。
- **设置下拉化（A3)**：课程配色与显示字体改 DropdownButtonFormField（key 绑当前值防 FormField 状态不刷新；字体项各自以自身 family 渲染 + 顶部当前字体预览行；导入/删除按钮保留在下拉下方，删除仅当选中导入字体时出现）。
- **单双周开关（A4)**：UiSettings.showParityLabel（默认 true)，主页标题关时只显示「第 X 周」。
- **自适应行高（B1)**：UiSettings.autoFitHeight（默认 false);_GridArea 在 LayoutBuilder 内按 (可用高-带总高）/节数 均分行高（下限 24)，设置页开关开启时高度滑杆停用显示「自适应中」。导出图仍用固定 cellHeight（屏幕概念不入图）。
- **今天列高亮（B2)**:_GridArea 按 displayWeek==本周且今天在 displayDays 内算 highlightDay，只传给本周页 _WeekGrid；页内 Stack 首子层整列 primary α0.05。
- **深色卡浅字（B4)**：CourseCard 的 useLightText = 深色模式 || cardColor.computeLuminance()<0.42；边框深底改 lightenColor（color_schemes 新增，向白混合 0.35；注意该文件只有 dart:ui Color、无 material Colors）。
- **B3 导出图标题行**：核实后发现早已具备（title=「学期名 · 第 X 周课表」+ 日期范围行），本版未动，如实告知用户。
- 待真机验：接缝线宽观感、长卡压带、下拉手感、单双周开关、自适应行高、今天列高亮、深色卡文字。


## v1.2.1+7（2026-10-21，七项：五项确认方案 + 导出改版 + 小部件修复，192 测试全绿）

- **开学日期确认**：新组件 `widgets/semester_start_dialog.dart`（showSemesterStartConfirmDialog：大字日期+第 1 周范围+总周数，改日期在弹窗内完成并自动对齐周一，返回最终 DateTime/取消 null）。SemesterFormDialog._submit 改异步：校验后先弹确认，确认才 pop 学期（学期管理与导入页新建共用此对话框，一处覆盖两入口）。ImportPage 加 `_guardedImport`（按目标学期 id 记忆 `_startConfirmedForId`，同次导入只弹一次）：弹窗改期后走 **Dao 直更**（注意 CurrentSemesterNotifier.updateSemester 会把当前学期整体替换成参数，非当前目标禁用），是当前学期则 setDirectly 同步 + invalidate semestersProvider；动作闭包必须用更新后的 target（ICS 按 startDate 算周次，捕获旧对象会算错）。
- **预见式返回**：AndroidManifest application 加 `android:enableOnBackInvokedCallback="false"`（应用级退出预见式返回）。待真机验证 PopScope 类返回拦截（核对页放弃确认）在关闭后仍生效。
- **分隔带通栏**：grid_metrics 新增 `kBandHeight=24`（原 week_view 私有 _bandHeight=20 已删）与 `typedef GridBand=({after,label,interval})`；week_view 全部 `List<({int after,String label})>` 改 List<GridBand>；interval 在 _GridArea 按作息计算（上一节 endTime–下一节 startTime）；_TimeAxis 空白占位改为同底色名称段，_DividerBand 加 interval 显示。高度公式全走 kBandHeight 守恒。
- **边框无极调节**：UiSettings.boldBorder(bool) → borderWidth(double 0~3)，JSON 新键 borderWidth，旧键迁移 true→1.4/false→0；CourseCard 参数 borderWidth（>0 才画 darken 边）；设置页开关换 _SliderRow（0 显示「无边框」）；调用点 week_view/share/settings 预览三处。
- **字体**：内置 +得意黑（family SmileySans，官方 v2.0.1 zip 内 SmileySans-Oblique.ttf 改名，2.6MB）+思源黑体（family NotoSansSC，google/fonts 可变字体 17.7MB）。**MiSans 落选原因**：官方只有 228MB 全家桶包、npm 镜像只有子集 woff2，无稳定单文件源——已在 CHANGELOG 与交付消息中说明替换。CI 字体步已加两源+体积断言。fontId 新增 smiley/noto。导入字体：`services/fonts_service.dart`（ImportedFont{id imp_<ms>,name,ext}，family='Imported_<id>'；注册表 app_settings.imported_fonts JSON；文件存 getApplicationDocumentsDirectory()/fonts/；main() 在 runApp 前 FontsService.init() 逐个 FontLoader 注册+剔除缺失条目；resolveFamily(ui) 供 main 与分享图共用）；path_provider 转直接依赖；file_picker 13 的 API 是 FilePicker.pickFiles 静态法返回 List<PlatformFile>（无 .platform/.files）。设置页字体区抽成 _FontSection（Stateful，内置 5 + 导入列表带删 + 导入按钮）。已知边界：TTC 不支持、单字重、字体文件不进备份。
- **导出图改版**：share_image_page 整页重写为与主页同构——宽度=MediaQuery 逻辑宽度、行高=ui.cellHeight、轴 50/表头 46/带 24 通栏（含时间段）、topOf/bandTop 公式与主页一致、横线跳带、pixelRatio 3。旧版 720 固定版式与「无分隔带」简化一并取消。
- **1.2.2 四项反馈修复**：①小部件改整包 JSON 契约（键 widget_payload，utils/widget_data.dart 的 buildWidgetPayload；旧 widget_title/lines 已弃用，原生 CourseWidgetProvider 改 JSONObject 渲染 4 行列表式布局 + 色条 setBackgroundColor；数据口径与通知共用 next_class.dart 新抽出的 sessionsOnDay）。②AppBar 恒色：backgroundColor=surfaceContainerHigh + surfaceTintColor 透明 + scrolledUnderElevation 0（默认自动着色在下拉回弹时翻转 → 顶部发白，用户截图实测色值 242,223,209 → 255,248,245）。③分隔带改 _GridArea 顶层 Stack 单条 _FullBand 横贯（轴内只留等高透明占位、网格内 _DividerBand 已删；bandTop=after×rowH+前方带数×kBandHeight）——旧「轴段+网格段」拼法接缝错位。④通知/状态条去掉「· HH:mm 下课」（时间段已含）。
- **切周太灵敏（根因定案）**：框架 PageScrollPhysics._getTargetPixels 在松手速度 > tolerance.velocity 时把目标页偏移 ±0.5 再取整；tolerance.velocity = 20/DPR ≈ 7px/s（小米 14）——任何自然松手都翻页。touchSlop 只影响拖动认领、与松手结算无关，这是 1.1.1「touchSlop 30」没治好的原因。修复：`utils/deliberate_page_physics.dart` 的 DeliberatePagePhysics（阈值 800px/s 才甩页，否则按位置 round 结算，越界交父类），PageView 显式指定；test/page_physics_test 5 例用 FixedScrollMetrics 验算落点。
- **小部件不显示课程**：全链路审计结论——Dart 数据生成/键名/插件（home_widget 0.10）存取契约/类名解析/接收器注册/布局颜色/刷新挂点全部无误，属投递层问题（updatePeriodMillis=0 无系统重绘兜底 + 厂商省电吞广播 → 永远停在添加时的默认文案）。修复：widget info 改 1800000（30 分钟系统重绘读 prefs 自愈）；Kotlin onUpdate 每实例 runCatching；WidgetService 保存后 getWidgetData 回读校验不一致重写；设置页新增「立即刷新桌面小部件」ListTile（附「仍不显示就删掉重加」提示）。待真机验证：装新版后先看周期重绘是否自愈，不行走重加路径。


## v1.2.0+6（2026-10-21，用户确认的 12 项方案，188 测试全绿）

- **导入目标学期显式化**：ImportPage 改 Stateful，顶部目标学期卡（默认当前学期；「更改」底部弹层选已有/当场新建，新建走共享 `widgets/semester_form_dialog.dart` 的 `showSemesterFormDialog`，建好 addSemester+switchTo 并设为目标）。目标以参数传 ImportReviewPage（必填 targetSemester），ICS 解析用目标开学日，核对页横幅明示，`_importAll` 只查 `getCoursesBySemester(target.id)`。学期管理页的私有表单对话框已抽到共享组件。
- **冲突批量化**：`utils/import_planner.dart`（ImportPlanner.preScan/buildPlan 纯函数）+ `pages/import_conflicts_page.dart` 清单页（默认全跳过、顶部全部同选、底部实时计数）。ConflictResolution 枚举移到 conflict_detector.dart，旧 widgets/conflict_dialog.dart 已删除（全仓无其他引用）。语义：任一冲突选跳过→整条跳过且不带删除；覆盖对方分已有课程 id / 本批草稿下标两路，执行端用 insertedIds 映射。跨学期回归测试在 import_planner_test（契约：池子只装目标学期）。校准差异：核对页收集 diff 文案，完成弹窗与计数一并展示。
- **下一节课焦点**：`utils/next_class.dart` computeClassFocus（向前 9 天生成课次；注意 effectiveCoursesForWeek 不过滤周次，必须再 isActiveInWeek 过滤）。主页 _ClassFocusBar 在 body 顶部，30 秒 Timer 刷新；焦点签名变化时顺带 OngoingNoticeService.refresh()。buildOngoingNotice 已改焦点模式（标题=当前课/下一节，静态文案不带倒计时），旧「今日剩余/明日预告」契约废弃，相关测试已改写。
- **更多菜单**：主页 AppBar 考试图标换 PopupMenuButton（搜索/空闲时段/导出图/学期管理/考试倒计时/导入）。week_view 新增 ref.listen(displayWeekProvider) 同步 PageView（搜索跳周靠它；守卫 page.round() 防与滑动打架）。
- **新页面**：course_search_page（点结果 setWeek(_targetWeek)+popUntil 首页）、free_time_page + utils/free_time.dart（节次全集减占用求连续区间）、share_image_page（固定 720 宽浅色渲染，SlotLayout.layoutDay 复用，RepaintBoundary 2x 出图，share_plus 13 的 XFile.fromData 分享；注意 share_plus 12 与 file_picker 13 的 win32 约束冲突，必须用 ^13）。导出图无分隔带（已知简化）。
- **考试红点**：week_view 按 courses.examDate 聚合 examsByDay 传 _HeaderRow/_DayCell（日期圆右上角 7px error 色点，Stack 叠加不占高），点有考试的表头弹当天考试列表。
- **字号无极调节**：UiSettings.cardTextSize(int) → cardTextScale(double 0.8~1.3)，JSON 新键 cardTextScale，旧键迁移 0→0.92/1→1.0/2→1.08。CourseCard 参数 textSizeLevel → textScale（课名 12×、副文本 10×、角标钳 8~13）。
- **预览 1:1**：新增 ui/grid_metrics.dart（kTimeAxisWidth=50、kGridHeaderHeight=46），week_view 与预览共用；预览列宽=（屏宽−50）÷主页同源列数（页面 watch 课程/调课/显示周等 provider 算 computeDisplayDays，该函数已从 week_view 移到 utils/slot_layout.dart），节次栏时间取真实作息。


- **阶段六·作息时间三段化**（2026-10-20，规格第 1、2 项）：
  1. **分段点设置**：`lib/providers/providers.dart` 新增 `SegmentSettings` + `SegmentSettingsNotifier`/`segmentSettingsProvider`（AsyncNotifier，仿 `ReminderSettingsNotifier`），键名 `lunch_after_section`（默认 5）/`dinner_after_section`（默认 9）存进现有 `app_settings` 键值表；`setLunchAfterSection` 钳到 [1, 晚餐点-1]、`setDinnerAfterSection` 钳到 [午休点+1, +∞)，保证午休点 < 晚餐点。
  2. **作息时间页三段化**：`lib/pages/time_settings_page.dart` 逐节列表改「上午/下午/晚上」三段分组（段标题 + 各节卡片，`showTimePicker` 交互与一键套用卡片保留）；顶部新增「分段设置」卡片（两个步进器，晚餐上限按当前最大节次钳制）；段间插入间隔信息行（`_minutesBetween`/`_formatDuration` 自动算「午休 12:00 – 14:00 · 约 2 小时」）。
  3. **周视图分隔带动态化**：`lib/pages/week_view_page.dart` 删除 `const _bands`（原 4/8），`_GridArea` 用 `ref.watch(segmentSettingsProvider)` 生成 `activeBands`（未加载回退 5/9），沿用「after < sectionCount 过滤」与高度守恒逻辑；标签仍「午休」「晚间」。

- **阶段六·导入按课表文件校准作息（第 3 项）**（本轮，2026-10-20）：
  1. **解析器输出校准块**：`lib/utils/ics_parser.dart` 新增 `IcsTimeBlock`（startSection/endSection/startTime/endTime，时间 "HH:mm"）；`IcsParseResult` 新增 `timeBlocks`；`_parseEvent` 改返回 `({Course course, IcsTimeBlock timeBlock})?`。节次取值优先 `_extractSectionRange` 从 DESCRIPTION 解析「第 X - Y 节」/「第X节」，解析不到回退为按钟点匹配出的节次；startTime 由 DTSTART 时分格式化，endTime 由 DTEND 时分格式化，缺失 DTEND 用该块 endSection 现有作息下课时间兜底、找不到留空（校准阶段跳过）。
  2. **校准纯函数**：`lib/utils/slot_calibrator.dart`（新建）`SlotCalibrator.calibrate(slots, blocks)`——块 startTime 只覆盖 startSection 开始、endTime 只覆盖 endSection 结束；按「节次+字段」保留第一个值跳过冲突；未触及节次不变；非法/空时间跳过；返回新列表不改入参。
  3. **导入接线**：`lib/pages/import_page.dart` 的 `_openReview` 加可选 `timeBlocks`（仅 ICS 路径传 `parsed.timeBlocks`，图片/PDF 不传）；`lib/pages/import_review_page.dart` 的 `ImportReviewPage` 加可选 `timeBlocks`（默认空），`_importAll` 课程全部导入成功后 `SlotCalibrator.calibrate` → 逐节 `updateSlot` 持久化 → SnackBar「已按课表文件校准作息时间」；校准异常 catch + debugPrint 静默，不回滚课程。
  4. **测试**：`test/slot_calibrator_test.dart`（新建）6 用例：单块覆盖首尾、相邻块共享节次（第 3 节起止共同确定）、冲突保留第一个、未触及节次不变、非法/空时间跳过、不修改入参。
- **验证**：⚠️ 本轮无法执行命令（Bash/Glob/Grep 被拒），`flutter analyze` / `flutter test` 未跑，代码纯静态编写。无新增 pub 依赖、未动数据库表结构。待验证：① `flutter analyze` 零问题；② `flutter test` 全绿（既有 135 用例 + 本轮新增 6 个 slot_calibrator 用例 = 141）；③ 真机走查作息设置页三段分组/步进器钳制/间隔时长文案、周视图午休晚间分隔带随分段点移动；④ 真机走查 ICS 导入确认后 SnackBar「已按课表文件校准作息时间」且作息时间页逐节时间已更新（重点：DESCRIPTION 带「第 X - Y 节」的 WakeUp 导出文件）。
- **调度员验收（2026-10-20 晚，S3 段，亲自执行）**：`flutter analyze` **零问题**；`flutter test` **140/140 全绿**（基线 134 + 新增 slot_calibrator 6 用例；上文「135+6=141」为基线误记，以 140 为准）。两次 codebuddy 会话（均 deepseek-v4-pro，谷段调用）均一次通过验收、零返工。真机走查项仍待用户在小米 14 上确认（见上 ③④）。

- **阶段五·视觉打磨收尾**（本轮，2026-10-15，阶段五 (e) 项，代码会话完成、本轮仅补文档）：
  1. **视觉常量落地** `lib/ui/app_styles.dart`（新建）：`AppRadii`（card=12 / sheet=16 / chip=8 / logo=24）+ `AppSpacing`（xs=4 / s=8 / m=12 / l=16）。全 App 卡片圆角统一 12px，间距收敛到 8/12/16 三档，页面不再写圆角/间距魔法数。
  2. **统一空状态** `lib/widgets/empty_state.dart`（新建）：`EmptyState` 组件（圆形浅底图标 + 中文主文案 + 可选补充说明 + 可选操作按钮），各列表/网格空状态全部替换，杜绝白屏。
  3. **纯 Dart 启动页** `lib/pages/splash_page.dart`（新建）：Logo + 应用名 + slogan，实际停留 900ms（`_durationMs` 常量，约 1 秒）淡入后 `pushReplacementNamed('/')` 进主页；`main.dart` 接 `initialRoute: '/splash'`。纯 Dart 实现，不碰原生启动主题，深浅色跟随 surface 无白色闪屏，顺带兜住首帧读库的白屏窗口。
  4. **常量化 + 语义色清扫**（12 个既有文件，业务逻辑零改动）：course_card、course_detail_sheet、week_picker、week_view_page、course_edit_page、course_override_page、import_page、import_review_page、settings_page、semester_manage_page、exam_countdown_page、main.dart——圆角/间距改走 AppRadii/AppSpacing，硬编码颜色改 colorScheme 语义色，深色模式复查。
  5. **无新增 pub 依赖，严禁 build_runner，无新增测试**（纯视觉调整，既有用例数不变）。
- **验证**：⚠️ 代码会话与本轮均未跑命令，`flutter analyze` / `flutter test` 未执行，需先跑上方自检命令。待验证项：① `flutter analyze` 零问题；② `flutter test` 全绿（135 个既有用例，本轮无新增）；③ **小米 14 真机走查**：启动页约 1 秒（实测 900ms）进入主页、按返回键不回启动页；深色模式下逐页无白色块（重点：启动页底色、各空状态、圆角卡片）；各列表空状态显示 EmptyState 中文占位（无课周视图、无考试倒计时页、空导入列表等）。用法约束与设计位置见 ARCHITECTURE.md「阶段五·视觉规范用法约束」专节。

- **阶段五·节假日单次调课**（前轮，仅 (d) 项；深色模式相关代码未动）：
  1. **纯函数** `lib/utils/override_effect.dart`：`effectiveCoursesForWeek` 是全 App 唯一的调课应用口径——周视图渲染、提醒计划（reminder_plan）、常驻通知（ongoing_notice）、小组件（widget_service）四处都先经它得到「本周有效上课实例」（停课移除、调整替换为新星期/节次/教室的 Course 副本）。`test/override_effect_test.dart` 19 用例（含提醒/通知文案联动与冲突检测）。
  2. **Dao**：`getOverridesBySemester`（JOIN courses 按学期过滤，四服务与 provider 都用这份）+ `upsertOverride`（事务先删 (courseId, originalWeek) 再插，同周重复调整=覆盖）。原预留 `getOverridesByCourse`/`insertOverride` 已被替换（grep 确认无其他调用方；Bash 被拒，靠通读 backup_codec 与全部 lib 文件确认）。
  3. **Provider**：`courseOverridesProvider`（watch 当前学期自动联动）。`saveOverride`/`deleteOverride` 末尾三联动与课程增删改完全一致：rescheduleAll + 常驻通知 refresh + 小组件 refresh——调课改变未来 7 天提醒计划与今日文案。
  4. **周视图**：渲染前应用调课（停课隐藏、调课按新时间/教室显示，单课卡片右上角「调」角标，multi 格让位给「+N」）；长按菜单新增「调整本次」，已有调整时变为「查看/撤销本次调整」（副标题显示调整摘要）；周末自适应收起也按调课后结果算（调到周六则不收起）。
  5. **单次调整页** `/course-override`（参数 {courseId, week}）：原时间信息卡 + 「本次停课」开关 + 新星期/节次下拉 + 新教室（留空沿用原教室）；已有调整回显并可撤销（二次确认）；保存前 `checkOverrideConflicts` 冲突确认框（列出中文明细，仍要保存/返回修改）。
  6. **语义约定**（详见 ARCHITECTURE 专节）：调整类型 targetWeek=originalWeek、星期/节次恒存完整值、教室 null=沿用原教室；停课类型 targetWeek=-1 且不存目标时间；originalWeek = 长按所在页的浏览周次。
- **验证**：⚠️ 本轮无法执行命令（Bash/Grep 被拒，同踩坑 #6/#12），`flutter analyze` / `flutter test` 未跑，代码纯静态编写。新增 19 个纯函数用例，无插件/平台通道依赖。**本轮只做 (d)，深色/备份/倒计时相关代码零改动。**

- **阶段五·考试/作业倒计时**（本轮，仅 (c) 项；(d) 单次调课 / (e) 视觉打磨按要求未动）：
  1. **纯函数** `lib/utils/exam_countdown.dart`：`daysUntil`（两个日期都截到 `DateTime.utc` 再作差，忽略时分秒，规避夏令时截断差一天）+ `countdownText`（>0「还有 X 天」/ 0「今天考试」/ <0「已结束」）。`test/exam_countdown_test.dart` 10 用例（含验收场景「7 天后 → 还有 7 天」与毫秒时间戳往返）。
  2. **课程编辑页**：备注下方新增「考试日期」ListTile——点击弹日期选择器（2020~2035），已设置时右侧有清除按钮；保存时构造 `Course(examDate: _examDate)` 整对象走 `updateCourse`（copyWith 传 null 清不掉字段，故不走 copyWith，见 ARCHITECTURE 设计决策）。
  3. **详情 BottomSheet**：教室行之后条件插入「考试」行：`yyyy年M月d日（还有 X 天/今天考试/已结束）`。
  4. **考试倒计时页** `/exam-countdown`：读 `coursesProvider`，筛 `examDate` 非空按升序；卡片 = 课程色点（深色降饱和）+ 课程名 + 日期·周几 + 倒计时文案（临近 primary / 当天 error 红 / 已结束 outline 灰）；空状态与「加载失败：$e」中文兜底。
  5. **入口选在周视图 AppBar**（Icons.event_note IconButton，放在「回到本周」左侧）：理由——倒计时是高频查看项，放首页一眼直达；设置页条目已很多；考试数据源自课程，与课表更近。若真机觉得 AppBar 拥挤可再挪设置页。
  6. **无新增 pub 依赖**；CoursesNotifier.updateCourse 本就整对象落库，未改 Provider/Dao。
- **验证**：⚠️ 本轮无法执行命令（Bash 被拒，同踩坑 #6），`flutter analyze` / `flutter test` 未跑，代码纯静态编写。新增 10 个纯函数用例，无插件/平台通道依赖，analyze 风险极低。

- **阶段五·JSON 备份恢复 + ICS 导出**（前轮，仅 (b) 项）：
  1. **JSON 备份**：`lib/utils/backup_codec.dart` 纯逻辑（encode/decode/restore）。备份 JSON 带版本号（v1）与 app 标记，字段直接复用各模型 `toMap()`（semesters/timeSlots/courses/courseOverrides/appSettings 五块全量）。恢复三铁律：先内存校验后动库（坏文件在确认弹窗前就被中文报错拦下，数据库零接触）→ 单事务清空重建（失败整体回滚）→ 旧→新 id 外键重映射（课程重挂新学期、调课重挂新课程）。isCurrent 归一为恰好一个（无则回退第一个学期）。
  2. **ICS 导出**：`lib/utils/ics_export.dart` 纯逻辑。选了「逐周展开为独立 VEVENT」方案（弃 RRULE，实现简单零歧义）；floating local time（DTSTART/DTEND 无时区后缀，DTSTAMP 用 UTC）；教师/备注进 DESCRIPTION（格式 `教师：xxx`，与本 App IcsParser 的启发式互通，导出的文件能被自己读回来）；RFC 5545 TEXT 转义 + CRLF；节次缺失的课程跳过并计数提示。
  3. **文件层** `lib/services/backup_service.dart`：`pickJsonFile`（file_picker 选 JSON）、`readBackup`（读文件+校验）、`restore`（走 BackupCodec）、`saveTextFile`（file_picker `saveFile` 落盘，Android 传 bytes 由选择器直接写入，返回路径；取消返回 null 静默）。
  4. **Dao**：新增 `getAllCourses` / `getAllOverrides` / `getAllSettings`（全量备份跨学期读取）。
  5. **设置页**「数据管理」分区三入口：备份到文件 / 从备份恢复（展示统计 → 二次确认「覆盖并恢复」→ 进度遮罩 → 恢复后 invalidate 七个 Provider（含主题/提醒/常驻通知设置，因 app_settings 被覆盖）+ goToday + 通知/常驻通知/小组件三联动刷新）/ 导出课表 ICS。
  6. **测试**：`test/backup_codec_test.dart` 10 用例 + `test/ics_export_test.dart` 9 用例（均纯逻辑/ffi 内存库，不碰平台通道）。
  7. **无新增 pub 依赖**：只复用 file_picker ^13.1.0（pickFiles 已在项目用，saveFile 用户确认已在项目使用）。
- **验证**：⚠️ 本轮仍无法执行任何命令（Bash/Glob/Grep 被拒，同踩坑 #6/#12），`flutter analyze` / `flutter test` 未跑，代码纯静态编写。**本轮新增已知风险点见下文列表最后两条。**
- **阶段五·测试修复**（前轮，2026-10-15）：`test/morandi_palette_test.dart` 两处色相断言容差 0.5→8.0 度（HSV↔RGB 8-bit 量化固有漂移约 4-6 度，低饱和课程色视觉不可察觉），各附中文注释；lib/ 无改动。未跑命令（Bash 被拒，同踩坑 #6），`flutter test` 待用户执行。

- **阶段一 / 二 / 三**：已完成（见 ARCHITECTURE.md）。
- **阶段四·上课本地通知提醒**（本轮）：
  1. 依赖 `flutter_local_notifications ^22.3.2` + `timezone ^0.10.0`（pubspec.yaml，未跑 pub get）。
  2. `lib/utils/reminder_plan.dart`：提醒时刻 / 当日课程筛选 / 文案纯函数；`test/reminder_plan_test.dart` 11 用例（不碰平台通道，可脱离插件跑）。
  3. `lib/services/notification_service.dart`：初始化（时区 Asia/Shanghai + 插件 + 渠道 `course_reminder_channel`）；权限三件套（通知/精确闹钟检查与请求）；`rescheduleAll()` 滚动窗口（今天+未来 6 天 exactAllowWhileIdle，无精确闹钟权限降级 inexactAllowWhileIdle）+ 次日 0 点自举标记（低优先级静音）。
  4. 设置持久化：`app_settings` 键值表（db 升 v2 + onUpgrade），Dao 增 getSetting/setSetting 系列；`ReminderSettingsNotifier` 读写开关/提前分钟。
  5. 设置页：`上课提醒` 开关（开启时申请通知权限 + 精确闹钟引导对话框）+ `提前提醒` 5/10/15/30。
  6. 刷新挂点：`switchTo`/`addCourse`/`updateCourse`/`deleteCourse` 末尾 `unawaited(rescheduleAll())`；`main()` 改 async 初始化 + `HomeShell.initState` 启动重排。
  7. Android 原生：Manifest 加 `POST_NOTIFICATIONS`/`SCHEDULE_EXACT_ALARM`/`RECEIVE_BOOT_COMPLETED` + `BootReceiver`；Kotlin `BootReceiver` 日志占位（第二道保险）。
  8. 文档：ARCHITECTURE.md 已记渠道/权限/滚动窗口决策/刷新挂点/新增文件。
- **验证**：⚠️ 本轮运行环境仍无法执行任何命令（非交互模式 Bash 权限被拒），**`flutter pub get` / `flutter analyze` / `flutter test` / `flutter build apk` 均未执行**，代码为静态编写。
- **阶段四·多学期管理**（本轮）：
  1. 学期管理页（`/semester-manage`，设置页入口）：列表显示名称/开学日期/总周数/「当前学期」徽标；新建表单（名称 + 日期选择器自动对齐周一 + 总周数默认 20）；切换、删除均二次确认；当前学期隐藏切换/删除入口 + Notifier 层兜底禁删。
  2. `SemestersNotifier.switchTo` 是切换唯一入口：DAO 事务保证 isCurrent 唯一 → `currentSemesterProvider.setDirectly` 免闪烁写入 → `coursesProvider`/`todayWeekProvider` 自动联动 → `displayWeekProvider.goToday()` 重置浏览周；周视图 PageController 经 `ref.listen` 同步跳页（clamp 防越界）。
  3. 删除学期级联删课程与 course_overrides（DAO 手写事务，不依赖外键开关）。
  4. 新增 7 个单元测试（sqflite_common_ffi 内存库跑真实 SQL）：切换事务唯一性、三 Provider 联动、级联删除、禁删当前学期等。
  5. ARCHITECTURE.md 已记「学期切换时的刷新入口」，通知/小组件会话照此挂点。
- **验证**：⚠️ 本轮运行环境无法执行任何命令（非交互模式 Bash 权限被拒，见踩坑 #6），**`flutter pub get` / `flutter analyze` / `flutter test` 均未执行**，代码为静态编写。必须先跑下面的命令验证。
- **阶段四·今日课程常驻通知栏**（本轮）：
  1. 纯逻辑 `lib/utils/ongoing_notice.dart`：`buildOngoingNotice`（B 决策：今日有未下课课程显示「今日剩余课程（共 X 节）」，全部下课才切「明日课程预告（共 X 节）」；行格式「08:00-08:45 高等数学 A101」无教室省略；明日无课兜底「明天暂无课程」）；`test/ongoing_notice_test.dart` 5 用例（不碰平台通道）。
  2. 服务 `lib/services/ongoing_notice_service.dart`：MethodChannel `com.example.simple_timetable/ongoing_course` 原子下发 `update`（title + lines）/ `stop`；`refresh()` 读 app_settings `ongoing_enabled`（默认开）→ 读学期/课程/节次 → 下发；全 try/catch 中文日志。
  3. 开关 `OngoingNoticeSettingsNotifier`（providers.dart）：持久化 `ongoing_enabled`，关闭即 `stop()` 清通知停服务；刷新挂点 `switchTo`/`addCourse`/`updateCourse`/`deleteCourse` 末尾 + `HomeShell.initState`。
  4. 设置页「上课提醒」旁新增「今日课程常驻通知」开关。
  5. Android 原生：`OngoingCourseService.kt` 前台 Service（InboxStyle 可折叠、startForeground、渠道 `ongoing_course_channel` 中文名「今日课程」IMPORTANCE_LOW）；`MainActivity.kt` `configureFlutterEngine` 注册 channel；Manifest 加 `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` + service 注册 `foregroundServiceType="specialUse"`。
  6. **未新增任何 pubspec 依赖**：MethodChannel 是 SDK 内置，Android 仅用 androidx.core（模板已内置）。
- **验证**：⚠️ 本轮同样无法执行任何命令，`flutter analyze` / `flutter test` / `flutter build apk` 均未跑，代码为静态编写。
- **阶段五·深色模式深度适配**（前轮，仅第 (a) 项；备份/倒计时/调课/启动页未做）：
  1. 三档主题切换：`ThemeSettingsNotifier`（providers.dart）持久化 app_settings `theme_mode`（system/light/dark，默认 system）；main.dart `themeMode` watch 该 provider；设置页「外观」分区 SegmentedButton 三段选择。
  2. 课程格子深色降饱和：`MorandiPalette.desaturateForDark`（HSV 空间饱和度 ×0.72、明度夹紧 [0.18,0.40]、色相不动、浅色原样返回）+ 深色文字常量；course_card 深色下降饱和底色+浅色文字+角标反色；course_edit 色板圆点深色所见即所得。`test/morandi_palette_test.dart` 8 用例。
  3. 全页面语义色核查：各页原本已是 `colorScheme.*` 语义色，硬编码仅剩 course_card / course_edit 两处，已修复；深色下无刺眼白色块（待真机过一遍确认）。
  4. 桌面小组件深色：`values-night` 文字色 + `drawable-night` 背景（#2B2B2B），布局改 @color 引用；未引入新依赖、Kotlin 无改动逻辑。
  5. 通知小图标：新增 `ic_stat_course.xml` 纯白日历剪影，flutter_local_notifications 初始化与 OngoingCourseService 两处替换原 `@mipmap/ic_launcher`。
  6. 文档：ARCHITECTURE.md 已记文件表与设计决策。
- **验证**：⚠️ 本轮仍无法执行任何命令（Bash/Glob/Grep 被拒，同踩坑 #6/#12），`flutter pub get` / `flutter analyze` / `flutter test` / `flutter build apk` 均未执行，代码纯静态编写。本轮无新 pub 依赖。深色观感、小组件深色切换、通知图标形态必须等小米 14 真机验证。
- **阶段四·桌面小组件**（前轮）：
  1. 依赖 `home_widget ^0.10.0`（pubspec.yaml，未跑 pub get；版本参考 UntisPlus / csust-course-schedule 的 lockfile 均在用 0.10.0，与 Flutter 3.47/Dart 3.13 兼容性待验证）。
  2. `lib/services/widget_service.dart`：`WidgetService.refreshWidgets()` 读当前学期/课程/节次 → 复用 `buildOngoingNotice` 出标题+行列表 → `HomeWidget.saveWidgetData<String>` 下发 `widget_title` / `widget_lines`(JSON) → `HomeWidget.updateWidget(name, qualifiedAndroidName)` 触发原生刷新；全 try/catch 中文日志。
  3. 刷新挂点：`switchTo`/`addCourse`/`updateCourse`/`deleteCourse` 末尾 + `HomeShell.initState`。
  4. 设置页新增「桌面小组件」分区：一句说明引导去桌面长按添加。
  5. Android 原生：`CourseWidgetProvider.kt`（继承 `HomeWidgetProvider`，重写 4 参 `onUpdate`，从 data 读数据，RemoteViews 渲染标题+最多 3 行、超出「…等 X 节」、点击 PendingIntent 唤起 MainActivity）；`res/layout/course_widget.xml`；`res/xml/course_widget_info.xml`（250×110dp、updatePeriodMillis=0、home_screen）；`res/drawable/course_widget_background.xml`；Manifest 注册 receiver。
- **验证**：⚠️ 本轮仍无法执行任何命令（Bash/Glob/Grep/WebFetch 全被拒，见踩坑 #13），`flutter pub get` / `flutter analyze` / `flutter test` / `flutter build apk` 均未执行，代码纯静态编写；**小组件能否正常显示/点击、MIUI 与不同桌面启动器兼容性，必须等小米 14 真机验证**。

## 待执行的自检命令（环境恢复后第一件事）

```bash
export PATH="$HOME/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd /home/hatch/workspace/simple_timetable
flutter pub get            # 拉取新增依赖 flutter_local_notifications / timezone / home_widget（及之前 sqflite_common_ffi）
flutter analyze            # 必须零问题
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=localhost,127.0.0.1
flutter test               # 307 个用例应全绿（基线 300：265 + bridge_codec 35；本轮 +7：学期编辑 2 + 学期表单 5；本机代理会导致 flutter_tester 连接失败）
```

已知风险点（analyze/test 若报错优先查这里）：
- **（本轮 1.3.6）未配置 / 断网 / 令牌失效都不应该崩**：这三条路径全部靠 `_syncOnce` 外层与各子步骤的 try/catch 兜，`syncNow` 的共享 Future（`_running`）若因异常没被 `whenComplete` 清掉会卡住后续同步——真机上如果发现「第一次失败后再点同步没反应」，查这一处。
- **（本轮 1.3.6）`Processed ids` 那一行是 JSON 字符串**：`processed_command_ids` 写的是 `jsonEncode(List<String>)`，读走 `parseProcessedIds`（坏数据当空历史），不要当成别的格式。
- **（本轮 1.3.6）GitHub 返回的 base64 带换行**：`readRemoteFile` 里先 `replaceAll(RegExp(r'\s'), '')` 再 `base64Decode`，若将来出现 FormatException 优先查这一步。
- **（本轮 1.3.5）`AndroidNotificationDetails` 的 `ongoing` / `autoCancel` 与 `BigTextStyleInformation` 构造**：凭 flutter_local_notifications 22.x 记忆编写（`BigTextStyleInformation(bigText, contentTitle:, summaryText:)`），若报未知命名参数按提示改名，语义不受影响（备注通知退化为普通文本也不影响数据链路）。
- **（本轮 1.3.5）Kotlin 侧没新增任何资源 id**：`widget_footer` 是既有 TextView，`notesText` 只是改它的文本与可见性；不要去查新布局。
- **（本轮 1.3.4）`AndroidNotificationChannel` 的两个新参数**：`_ensureBootstrapChannel` 传了 `enableVibration: false` 与 `showBadge: false`；`_bootstrapDetails` 传了 `channelShowBadge: false`。三者凭 22.x 记忆编写（无法读 pub cache / pub.dev 核对）。若 analyze 报「参数不存在」，按提示删除或改名（`AndroidNotificationDetails` 的角标参数历史上在 `showBadge` / `channelShowBadge` 之间改过名）；渠道的 `playSound` 有意未传（类型随版本变动，importance=low 已足够静音，确认是 bool 可自行补 `playSound: false`）。
- **（本轮 1.3.4）Kotlin `JSONObject.optString(key, null)`**：平台类型参数传 null 合法；若编译挑剔，改 `if (o.has(key)) parsePayload(o.getString(key)) else null`。`SimpleDateFormat` 需 `java.text`/`java.util` 三个 import（已加）。
- `semester_manage_page.dart` 的 PopupMenu 内嵌 ListTile 写法（dense + contentPadding: EdgeInsets.zero）是否触发 lint；
- `providers.dart` 中 `SemestersNotifier` 对 `ref.read(displayWeekProvider.notifier)` 的跨 Provider 读取；
- `db_helper.dart` 新增的 `import 'package:flutter/foundation.dart'` 与 sqflite 导入共存；
- sqflite_common_ffi 版本约束 `^2.3.0` 是否与当前 SDK 解析兼容（不行就升到最新 2.3.x/2.4.x）；
- **notification_service.dart 的插件 API 签名**：本会话无法读 pub cache，凭 flutter_local_notifications 22.x 记忆编写。重点核对 `zonedSchedule` 的 `androidScheduleMode`（必需命名参数）、`AndroidFlutterLocalNotificationsPlugin.requestNotificationsPermission()/canScheduleExactNotifications()/requestExactAlarmsPermission()` 返回 `Future<bool?>`、`AndroidNotificationChannel` 的 `playSound` 是 `PlaySound` 枚举（channel 上不可用 bool）而 `AndroidNotificationDetails` 的 `playSound` 是 bool；
- `timezone` 双别名 import（`data/latest.dart` 与 `timezone.dart` 都 as tz）是否触发冲突（官方 README 即此写法，一般无冲突）；若 `latest.dart` 不含 Asia/Shanghai 可改 `latest_all.dart`。
- **ongoing_notice_service.dart**：`OngoingNoticeService.refresh()` 直接读 Dao（sqflite 需真库），未写 service 层单测（纯逻辑 ongoing_notice.dart 已测 5 用例）；service 层行为留给真机验证。
- **Kotlin `call.argument<List<String>>("lines")`**：StandardMethodCodec 解码为 `ArrayList<Any?>`，泛型 `argument<List<String>>` 是运行时擦除的强转；随后 `ArrayList(lines)` 用 Java 的 `ArrayList(Collection)` 构造。若编译报类型不匹配，改 `lines.toCollection(ArrayList())`。
- **`ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` 与 `Build.VERSION_CODES.UPSIDE_DOWN_CAKE`**：均需 compileSdk ≥ 34（本项目 compileSdk = flutter.compileSdkVersion = 36，满足）。三参 `startForeground(id, notif, type)` 需 API 29+，已用 `>= UPSIDE_DOWN_CAKE` 守卫。
- **`STOP_FOREGROUND_REMOVE`**：`Service` 的 `static final int` 常量（=1），编译期内联，低 API 下引用安全。
- **home_widget API（本次桌面小组件）**：本会话无法读 pub cache（~/.pub-cache 被拒）、WebFetch 被拒，home_widget 0.10.0 的 Dart/Kotlin API 凭参考项目 UntisPlus（github-research/UntisPlus，MIT，同样钉 0.10.0）的真实调用反推。关键点：Dart `HomeWidget.saveWidgetData<String>(key, value)`、`HomeWidget.updateWidget(name:, qualifiedAndroidName:)`；Kotlin `import es.antonborri.home_widget.HomeWidgetProvider` 并重写 `onUpdate(context, manager, ids, data: SharedPreferences)`（data 即 Dart saveWidgetData 写入的偏好文件，键不加前缀）。若 pub get 后 API 对不上（参数名/方法名变了），以 pub.dev 上 home_widget 0.10.0 的 README/源码为准修正。
- **`org.json.JSONArray`**：Android 框架自带（android.jar），解析 widget_lines JSON 无需新增原生依赖，低版本也安全。
- **（本轮深色）`Color.value` 新 API 弃用风险**：Flutter 3.4x 起 `Color.value`/`withOpacity` 等有弃用趋势，本次代码刻意避开了（比较用 `same()`、取 HSV 用 `HSVColor.fromColor`），若 analyze 仍报 deprecation 按提示改 `toARGB32()`。
- **（本轮深色）`desaturateForDark` 明度夹紧区间 [0.18, 0.40] 是拍脑袋初值**：真机深色下如果整体偏暗看不出格子，先调下限 0.18→0.24；如果仍刺眼，调上限 0.40→0.34。区间在 morandi_palette.dart 一处常量，好改。
- **（本轮深色）小组件 night 资源生效时机**：`values-night`/`drawable-night` 依赖系统在深浅模式切换时重 inflate RemoteViews；MIUI 上切换深色后小组件若不刷新，手动回桌面或重开 App 触发一次 updateWidget 即可，属已知行为非 bug。
- **（本轮深色）`AndroidInitializationSettings('@drawable/ic_stat_course')`**：参数只是资源名字符串，运行时按名查找；若把 drawable 改名需两处（Dart 初始化 + Kotlin setSmallIcon）同步。
- **（本轮深色）providers.dart 新增 `import 'package:flutter/material.dart' show ThemeMode, debugPrint`**：与 riverpod 无冲突；若 analyze 报不必要的 show，删 debugPrint（未用到时）即可。
- **（本轮备份/ICS）file_picker 13.x 的 `FilePicker.saveFile` API 签名**：backup_service.dart 凭记忆调用 `saveFile(dialogTitle:, fileName:, type: FileType.custom, allowedExtensions:, bytes:)`，期望 Android 传 bytes 时选择器直接落盘并返回路径、取消返回 null。analyze 前以 pub cache 里 file_picker 13.1.0 源码为准核对：若 13.x 的 saveFile 需要 `Uint8List? bytes` 以外的参数名（或该版本 saveFile 不接受 bytes 而只返回目标路径需自行写文件），按源码修正 `saveTextFile` 一处即可，调用方不用动。
- **（本轮备份/ICS）`JsonEncoder.withIndent` 是 const 构造**（`const pretty = JsonEncoder.withIndent('  ')`），Dart 3 下合法；若 lint 报 prefer_const 之类照提示调整。
- **（本轮备份/ICS）设置页恢复后的 Provider invalidate 顺序**：`goToday()` 在 invalidate 之后调用，此时 currentSemesterProvider 尚在重建（value 短暂为 null → todayWeek=0），浏览周会先落在第 1 周；随后 WeekViewPage 的 `ref.listen(currentSemesterProvider)` 会把 PageController 跳到恢复学期的本周，属预期行为非 bug。若真机发现没跳，检查该 listen 是否被本轮改动影响（本轮未动 week_view_page）。
- **（本轮调课）`getOverridesBySemester` 用 rawQuery JOIN**：`SELECT o.* FROM course_overrides o INNER JOIN courses c ON o.courseId = c.id WHERE c.semesterId = ?`，sqflite rawQuery 返回的列名即 `o.*` 的原列名，CourseOverride.fromMap 可直接吃；若 analyze 后跑 test 报「no such column」，优先检查 courses 表里 semesterId 列名。
- **（本轮调课）课程被删除但 override 残留的防御**：正常删课路径 `Dao.deleteCourse` 会先删该课的 overrides，理论上无悬空；但若出现（如老版本数据），`checkOverrideConflicts` 的 `_findById` 找不到课程会跳过该项检查，`effectiveCoursesForWeek` 只按 courseId 匹配（课程不在列表即不生效），不会闪退。
- **（本轮调课）`DropdownButtonFormField.initialValue`**：与 course_edit_page 同款写法（同 Flutter 版本已验证可用），非新风险；列出仅备忘。

## 本轮踩过的坑

1. **codebuddy CLI 不可用**：本机 `codebuddy` 命令丢失（npm 全局包没了），用 `npm i -g @tencent-ai/codebuddy-code` 重装恢复，auth 文件仍在（~/.local/share/CodeBuddyExtension/Data/Public/auth/）。但 `-p` 非交互模式下 Bash/Edit/Write 权限被拒（审批 UI 不可用），codebuddy 无法动手。**本轮改为我直接实现，未走 codebuddy 会话** —— 注意：那次失败的 `-p` 调用本身产生了一次模型输出（glm-5.3-flash），可能烧了一点积分，但没有做任何代码改动。
2. **main.dart 是 CRLF 换行**：`muse.edit` 精确匹配失败，改为整文件重写（已统一为 LF）。
3. **手滑写错字段**：`_showSlotPicker` 里误写 `c.dimmed`（Course 没有该字段），analyze 会报，已修正为用 `slot.dimmed`。
4. **分隔带对齐**：时间轴原本用 Expanded 自适应，加入分隔带后必须改固定高度 + 分隔带占位，否则左右错位。现在 `_GridArea` 统一计算度量，时间轴与网格共用。
5. **PopScope 与导入成功返回的冲突**：导入成功后代码里 `Navigator.pop` 会被 PopScope 拦截（canPop=false），所以加了 `_done` 标记，导入完成/用户确认放弃时才放行。
6. **非交互会话 Bash 全被拒**（本轮）：`-p` 模式下 Bash 需审批但审批 UI 不可用，Read/Write/Edit/Grep/Glob 正常。结果：pub get/analyze/test 全没跑。下次在这种环境干活，代码写完必须把自检命令原样写进 DEV_STATE.md 交用户执行，不能假装验证过。
7. **学期切换刷新用 setDirectly 而非 reload()**：reload 会先把 currentSemesterProvider 置 AsyncLoading，`.value` 变 null 导致 todayWeekProvider 瞬时归 0、周视图闪烁；直接写 AsyncData 则下游无感重建。这个模式值得复用。
8. **本轮（本地通知）Bash 仍全被拒，且 pub cache 目录（~/.pub-cache）读取被拒**：无法用 `flutter pub get` 拉包、也无法读插件源码核对 API。所以插件调用全凭 22.x 记忆写，`AndroidNotificationChannel.playSound` 一度误写 bool（应为 `PlaySound` 枚举）已改。**本轮代码未编译验证，analyze 前务必先核对上面「已知风险点」的插件 API。**
9. **设置持久化选型**：项目原本没有任何设置持久化（`showOtherWeeks`/`autoCollapseWeekend` 都是纯内存 Notifier）。提醒开关/提前分钟必须持久化（开机/切学期/重排都要读），且铁律只准加 `flutter_local_notifications`+`timezone` 两个依赖，故复用现有 sqflite，新增 `app_settings` 键值表（db 升 v2 + onUpgrade 补建），不引入 shared_preferences。
10. **「每日 0 点重排」无法纯本地通知实现**：flutter_local_notifications 只有「点按回调」，没有「触发瞬间回调」，0 点没法唤醒 Dart 做重排。落地为「滚动窗口」（今天+未来 6 天全排好 + 次日 0 点自举标记），配合 App 启动/改数据重排 + 插件内置 BootReceiver 恢复，达到等价效果。`BootReceiver` 因此只做日志占位，没有假装「调用 Dart 重排」。
11. **前台服务 specialUse 的 Android 14 细节**：常驻通知前台服务属「特殊用途」，Android 14+ 必须满足三件套——Manifest 加 `FOREGROUND_SERVICE_SPECIAL_USE` 权限 + service 声明 `foregroundServiceType="specialUse"` + `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE">`；且 `startForeground` 要用三参重载显式传 `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE`，否则运行时抛 MissingForegroundServiceTypeException。已全部落实。
12. **本轮 Bash/Glob/Grep 全被拒（ripgrep EACCES）**：非交互会话下连 Glob/Grep 都 spawn rg 失败（EACCES），只能靠 Read 逐个读文件摸结构。pub get/analyze/test 仍无法执行，代码纯静态编写，自检命令照例写进本文件交用户执行，未假装验证过。
13. **本轮 Bash/Glob/Grep/WebFetch 全被拒，且 ~/.pub-cache 读取被拒**：无法拉 home_widget 源码核对 API，也无法用 WebFetch 查 pub.dev。home_widget 0.10.0 的 API 凭参考项目 UntisPlus（github-research/UntisPlus，MIT，同样钉 home_widget 0.10.0）的真实调用反推。**注意：SchedU 不用 home_widget（用 Jetpack Glance 自读 Flutter DB），不能作为 home_widget API 参考**，已确认。代码未编译验证，analyze 前先核对「已知风险点」里的 home_widget API。

## 必须等用户在小米 14 真机验证的项（云电脑测不了）

- [ ] **先跑上面的自检命令**：pub get 拉新依赖、analyze 零问题、82 个测试全绿。
- [ ] 多学期流程走查：设置 → 学期管理 → 新建「下学期」（日期选择器对齐周一）→ 卡片点击切换 → 周视图清空且顶部周次/日期变化 → 录一门新课 → 切回旧学期确认原课程还在 → 删除下学期（二次确认）确认课程级联删除。

### 阶段四·上课本地通知（小米 14 / Android 14+ 重点验证）

- [ ] **准时响铃**：设一节 5 分钟后的课，提醒应准时弹出，文案「《xx》还有 15 分钟在 xx教室上课」（无教室则「…还有 15 分钟上课」）；提前分钟改 5/10/30 后重设验证。
- [ ] **App 被杀后台**：录一节 ~10 分钟后的课 → 完全杀掉 App（任务卡片划掉）→ 到点是否仍准响。这是「精确闹钟 + 滚动窗口」能否抗 MIUI 杀后台的关键验证。
- [ ] **MIUI 自启动/省电策略**：进系统「应用信息 → 省电策略」设为「无限制」前后对比；MIUI 可能额外弹「自启动」授权，若被杀后台不响，先检查这两项（与抖音弹窗教训同理，别轻信「没开」）。
- [ ] **精确闹钟授权引导**：首次开启「上课提醒」→ 弹「开启精确闹钟」对话框 → 点「去设置」是否跳到系统「闹钟和提醒」页；拒绝后应降级为 inexact（提醒仍响、可能延迟），不闪退。
- [ ] **通知权限**：Android 13+ 首次开启若拒绝 POST_NOTIFICATIONS，应弹中文 SnackBar 且不闪退；到系统设置开启后提醒可见。
- [ ] **切学期/增删改课程联动**：切换学期后重新设一节课提醒能响；删课/改课时间后旧提醒不再响、新提醒响。
- [ ] **重启恢复（BOOT_COMPLETED）**：设好提醒后重启手机，到点是否仍响（验证插件内置 BootReceiver 是否真能恢复；本项目 `BootReceiver` 仅打日志，可 `adb logcat -s BootReceiver` 看开机日志）。
- [ ] **通知小图标**：已改为 `@drawable/ic_stat_course` 纯白剪影（2026-10-15），验证状态栏/下拉形态清晰无白块。
- [ ] 关闭「上课提醒」开关后，当天不应再有提醒弹。

### 阶段四·今日课程常驻通知栏（小米 14 / Android 14+ 重点验证）

- [ ] **常驻通知保活**：打开 App（今日有课）→ 通知栏应出现「今日剩余课程（共 X 节）」可折叠 InboxStyle 列表；完全杀掉 App（任务卡片划掉）→ 通知是否仍在。前台 Service 能否抗 MIUI 杀后台是最大未知数。
- [ ] **MIUI 省电策略**：进「应用信息 → 省电策略」设为「无限制」前后对比；MIUI 可能额外限制前台服务，若通知被杀先查省电/自启动设置（别轻信「没开」，与抖音弹窗教训同理）。
- [ ] **Dart isolate 回收导致文案冻结**：长时间不打开 App，通知文案会停留在旧内容（refresh 只在 App 启动/改数据时触发，无后台 0 点重排）。重点观察跨天场景：今天课全部下课后，通知是否自动切「明日课程预告」——**预期不会自动切**，需重新打开 App 才刷新，确认这是当前架构的已知限制且可接受。
- [ ] **20:00 规则（B 决策）**：设一节 20:00-21:30 的课，20:30 时通知仍显示「今日剩余课程」；另设一天课程全部 16:00 前结束，20:30 打开 App 应显示「明日课程预告」。
- [ ] **无教室/明日无课兜底**：无教室的课行文案省略教室；周末（明日无课）显示「明日课程预告（共 0 节）+ 明天暂无课程」。
- [ ] **开关联动**：设置页关闭「今日课程常驻通知」→ 通知立即消失、前台服务停止；重新开启 → 通知恢复；重启 App 后开关状态保持（读 app_settings `ongoing_enabled`）。
- [ ] **切学期/增删改联动**：切换学期后通知内容换成新学期；改课时间/删课后通知刷新。
- [ ] **点按通知回 App**：点通知能回到简课表主界面。
- [ ] **通知小图标**：`setSmallIcon` 已改为 `R.drawable.ic_stat_course` 纯白剪影（2026-10-15），验证清晰无白块。
- [ ] **渠道静默**：渠道名「今日课程」IMPORTANCE_LOW，展开可折叠、不响铃不震动。

### 阶段五·深色模式（小米 14 重点验证，本轮验收标准）

- [ ] **设置页外观三段切换**：跟随系统/浅色/深色即点即生效；杀掉 App 重启后保持上次选择（读 app_settings `theme_mode`）；切「跟随系统」后跟系统深色开关联动。
- [ ] **周视图深色观感**：课程格子为降饱和深色底、浅色文字清晰可读；「+N」角标与备注圆点为浅块深字；非本周置灰卡片在深色下不过黑/不可见。
- [ ] **逐页过一遍深色无白色块**（验收标准）：设置页、课程编辑页（含色板圆点与勾选图标）、作息时间页、学期管理页、导入入口页、核对页、详情 BottomSheet、周次选择器、各 AlertDialog/BottomSheet/日期时间选择器。
- [ ] **课程编辑页色板**：深色下圆点显示降饱和后实际效果，勾选图标可见；保存后浅色模式下颜色不变（深色降饱和只影响显示，不改存库值）。
- [ ] **小组件深色切换**：系统切深色 → 桌面小组件背景变 #2B2B2B、文字变浅色；切回浅色 → 恢复浅底深字。MIUI 若不自动刷新，重开 App 后再看。
- [ ] **通知小图标**：上课提醒与常驻通知的状态栏小图标应为清晰的白色日历剪影（不再是彩色图标压成的白块）；深色/浅色通知栏、下拉展开两种形态各看一遍。
- [ ] `flutter build apk --debug` 正常打包（新增了 drawable-night/values-night 资源，确认资源合并没有冲突）。

### 阶段四·桌面小组件（小米 14 / 不同桌面启动器 重点验证）

- [ ] **小组件添加与显示**：桌面长按空白处 →「小组件」→ 找到「简课表」（或「今日课程」）→ 添加 4×2 小组件，应显示「今日剩余课程（共 X 节）+ 行文案」；今日有课 / 今日无课（明日预告）/ 明日无课兜底三种情况各看一遍。
- [ ] **点击唤起 App**：点小组件任意处应回到简课表主界面（不闪退、不重启）。
- [ ] **数据推送联动**：新增 / 修改 / 删除一门今天的课，小组件应随之刷新；切换学期后小组件内容换新学期；重启 App 后小组件刷新为最新。
- [ ] **行数截断与兜底**：造一个当天超过 3 节课的学期，小组件应最多显示 3 行、最后一行「…等 X 节」；假期/无课显示「暂无课程」。
- [ ] **MIUI 桌面启动器兼容性**：系统默认桌面 / 第三方启动器（如有）下小组件能否添加、尺寸是否正常、圆角背景是否与桌面协调；MIUI 可能对小组件刷新有省电限制，若数据不更新先查省电策略（别轻信「没开」，与抖音弹窗教训同理）。
- [ ] **跨天不自动刷新（已知限制）**：长时间不打开 App 跨天后，小组件文案停留旧值，需重新打开 App 才刷新——确认这是可接受的已知限制。
- [ ] **深色模式观感**：小组件已做深色适配（values-night/drawable-night，见阶段五深色节），验证深浅切换观感。
- [ ] `flutter build apk --debug` 能正常打包（首次引入 home_widget 插件，需确认其原生依赖/Manifest 合并无冲突）。


- [ ] 切换学期后周视图 PageController 落在新学期「本周」，无越界/白屏（尤其新学期总周数比旧学期少时）。
- [ ] 切学期瞬间周视图无闪烁（setDirectly 方案的实际效果）。

- [ ] HapticFeedback 三处触感是否生效、强度是否合适（云电脑无震动马达）。
- [ ] 午休/晚间分隔带在真机各种屏幕尺寸/字体缩放下的对齐与观感。
- [ ] PopScope 返回确认：系统返回键 / 全面屏手势返回是否正常弹窗。
- [ ] 5 列/7 列切换：找一个周末无课的周确认自动收起，周末有课的周确认不收起。
- [ ] 「+N」角标点击 → 迷你选课列表 → 详情，流程走通。
- [ ] 备注圆点角标显示正常。
- [ ] 底部中间「新建」BottomSheet 两个入口跳转正常；确认 IndexedStack 只有两页后无黑屏/状态残留。
- [ ] 导入失败三按钮：复制错误报告后去剪贴板能粘贴出完整报告。
- [ ] 跑一遍 `flutter build apk --debug` 确认能正常打包（本轮只跑了 analyze/test，未打包）。
- [ ] 深色模式下分隔带/角标/置灰卡片观感（阶段五才深度适配，但别太难看）。
- [ ] 学期管理页在深色模式下「当前学期」徽标、PopupMenu 观感。

### 阶段五·JSON 备份恢复 + ICS 导出（小米 14 真机验证，本轮验收标准）

- [ ] **JSON 备份导出**：设置 → 数据管理 → 备份到文件 → 系统选择器选位置 → 提示「备份已保存到：路径」；文件存在、内容为带缩进的 JSON、顶层含 `app`/`version`/五块数据字段。
- [ ] **JSON 恢复（核心验收标准：删 App 重装后能完整恢复）**：导出备份 → 录几门课/改主题/改节次时间制造差异 → 卸载重装 App → 从备份恢复 → 二次确认弹窗显示「X 个学期、Y 门课程」→ 恢复后：课程/学期/节次时间/主题（深浅色）/提醒开关全部回到备份时状态；周视图跳到恢复学期的本周；通知与小组件内容刷新。
- [ ] **恢复失败不破坏数据**：选一个非备份 JSON（或改坏的文件）→ 应弹中文报错「现有数据未受影响，可放心重试」→ 重开 App 确认现有课程原样还在（先校验后动手 + 单事务回滚的双保险）。
- [ ] **恢复二次确认与进度遮罩**：确认框点「取消」无任何写入；点「覆盖并恢复」后出现「正在恢复…」遮罩，完成后自动关闭。
- [ ] **ICS 导出**：导出 → 提示「已导出 X 节课：路径」；文件用「文件管理器」打开或分享到系统日历/Google 日历导入，事件数 = 课表实际次数、时间地点正确（重点核对跨周的日期递推与 DTEND=下课时间）。
- [ ] **ICS 回导自洽**：把导出的 .ics 通过本 App「导入课表 → ICS」再导回来，核对页里课程名/教室/星期/节次/周次与原课表一致（DESCRIPTION 教师启发式互通）。
- [ ] **ICS 分享**：导出的文件能通过微信/网盘等正常分享（文件在用户选择的位置，非 App 私有目录）。
- [ ] **取消路径**：备份/恢复/ICS 导出在文件选择器里点取消，App 无报错无多余提示。
- [ ] `flutter build apk --debug` 正常打包（本轮无新依赖、无 Android 原生改动，预期无风险）。

## 下一步（阶段五）

阶段四已全部完成（上课提醒、桌面小组件、多学期管理、今日课程常驻通知栏）。阶段五·深色模式深度适配已完成（2026-10-15，三档主题 + 降饱和 + 小组件 night 资源 + 通知剪影图标），**观感与流程待小米 14 真机验证**。阶段五·JSON 备份恢复 + ICS 导出已完成（2026-10-15，见上文专节，**待真机验证**）。阶段五·考试倒计时已完成（2026-10-15，见「做到哪了」，**待真机验证**）。阶段五·节假日单次调课已完成（2026-10-15，见「做到哪了」，**待真机验证**）。阶段五·视觉打磨已完成（2026-10-15，见「做到哪了」首节：AppRadii/AppSpacing 常量 + EmptyState 空状态 + 纯 Dart 启动页，**analyze/test/真机走查待验证**）。阶段五代码侧全部完成，剩余为验收；应用图标（launcher icon）未涉及，如需再做。常驻通知栏与小组件的「明日课程预告」已统一按 B 决策落地（今日课程全部下课才切明日）。

### 阶段五·节假日单次调课（小米 14 真机验证，本轮验收标准）

- [ ] **长按交互（重点）**：长按本周某节课 → 菜单第一项应为「调整本次」（副标题「只改这一节课…」）；对该课该周建立调整后再长按，第一项变为「查看/撤销本次调整」并显示调整摘要；其他周长按同一门课仍是「调整本次」。长按触感正常、菜单不闪退。
- [ ] **调整后周视图渲染**：把周一的课调到周三 → 周一原格消失、周三新格出现且右上角有「调」角标（浅色深角标/深色浅角标都清晰）；只改教室 → 原位置显示新教室 + 「调」角标；切到其他周确认课程仍是原时间原教室（规律未动）。
- [ ] **本次停课渲染**：勾「本次停课」保存 → 该周该节课消失、无角标残留；其他周照常显示。
- [ ] **调课后提醒准时（重点）**：设一节 ~20 分钟后的课并把它单次调到 ~10 分钟后（提前提醒 5 分钟）→ 应按**新时间**提前 5 分钟响铃，文案含新教室；把当天唯一的课标记停课 → 到点不应响。
- [ ] **常驻通知/小组件文案联动（重点）**：今天的课被调到明天（或反之）后，常驻通知与桌面小组件应刷新为调课后的时间/教室文案；停课后通知里不再出现该课、计数减一；撤销调整后文案恢复。
- [ ] **冲突提示**：把 A 课调到 B 课同一天的同一时段 → 弹「检测到时间冲突」确认框列出中文明细；点「返回修改」不落库，点「仍要保存」正常保存且周视图两课同格（multi「+N」）。端点相接（如调到第 2 节而对方是第 3-4 节）不应报冲突。
- [ ] **撤销**：调整页点「撤销本次调整」→ 二次确认 → 课程回到原规律、「调」角标消失、其他周不受影响。
- [ ] **周末收起联动**：把某节课单次调到周六 → 当前浏览周应显示 7 列（不收起）；撤销后周末无课的周恢复 5 列。
- [ ] **跨学期隔离**：切到另一学期，确认调课记录不串（列表按学期过滤）；删学期/删课正常级联。
- [ ] **调整页异常路径**：课程刚被删除后进入调整页（理论不可达）应显示中文兜底 + 返回按钮，不闪退；保存失败（如库异常）有「保存失败」提示不闪退。
- [ ] `flutter build apk --debug` 正常打包（本轮无新依赖、无 Android 原生改动，预期无风险）。

### 阶段五·考试倒计时（小米 14 真机验证，本轮验收标准）

- [ ] **验收主路径**：编辑一门课 → 设置考试日期为 7 天后 → 保存 → 周视图 AppBar 点倒计时图标 → 该课排最前（若唯一）且显示「还有 7 天」。
- [ ] **编辑页往返**：再次进入编辑页，考试日期回显正确；点清除图标后保存 → 详情页不再显示「考试」行，倒计时页该课消失。
- [ ] **详情页联动**：点课程格 → 详情 BottomSheet 显示「考试 yyyy年M月d日（还有 X 天）」；当天设为考试日显示「今天考试」（红色），过期显示「已结束」（灰色）。
- [ ] **排序**：给两门课设不同考试日期，倒计时页近的在上；同日按入库顺序稳定即可。
- [ ] **空状态**：没有任何课程设考试日期时，倒计时页显示「还没有设置考试日期」引导文案，不白屏。
- [ ] **深色模式**：倒计时页卡片/色点/文字深色下无刺眼亮块（色点走 desaturateForDark）。
- [ ] **跨学期**：切换学期后倒计时页只显示新学期课程（coursesProvider watch 当前学期，预期自动联动）。


## 2026-10-20 改名记录（简课表 → 小马课表）

- 应用显示名：「简课表」→「小马课表」（AndroidManifest `android:label`、App `title`、启动页、设置页文案、备份/ICS 导出文件名、导入错误报告抬头、备份异常文案、小组件默认标题等用户可见文案已全量替换）。
- Android 包名：`com.example.simple_timetable` → `com.jieke.xiaomakebiao`（build.gradle.kts 的 namespace 与 applicationId、4 个 Kotlin 文件的目录与 package 声明、CHANNEL/ACTION 字符串、Dart 侧 MethodChannel 名与小组件类名已同步）。
- Dart 包名：`simple_timetable` → `xiaoma_timetable`（pubspec `name`、全项目 `package:` import 已同步替换）；pubspec 版本升为 `1.1.0+2`，description 改为「小马课表 - 零广告的大学生课程表 App」。
- 有意保留不改：数据库文件名 `simple_timetable.db` 与备份格式标识 `appTag = 'simple_timetable'`（含 backup_codec 文档注释），避免已有数据/旧备份文件失效；本文件与 ARCHITECTURE.md 中的历史记述保留原文。

## 待执行的自检命令（本环境无命令权限，由用户执行）

```bash
# 先清代理（本机 Clash 系统代理会让 flutter_tester 的 WebSocket 连不上）
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
export NO_PROXY=localhost,127.0.0.1

flutter pub get
flutter analyze          # 期望零问题
flutter test             # 期望 340/340 全绿（2.0.0 基线）
flutter build apk --debug
```

最新一轮（2.0.0）新增/改动点若 analyze 报错，优先看 DEV_STATE 顶部那轮的「analyze 风险点」。
