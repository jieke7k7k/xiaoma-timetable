# WB_SPEC_264：三轮审查全量修复（进 2.16.1，待确认版本号）

## §0 范围（「全修」的清单）

- 来源：Neon 三轮审查共 71 条主张，核对结论：属实 63、半属实 5、不属实 1，另逐字一致结论 1 项（抽查属实）。核对记录见 `~/workspace/goals/app/hidden_files/neon_review_verification.md`（第一轮 + 第二轮）与 `neon_review_round3_verbatim.md`（第三轮逐字比对）。
- **本批在修 66 项**（三处重叠合并后，见 §7）。全部是已核实属实的部分。
- **不进本批**：
  - T1 的「用例崩溃」指控（假，单跑 4/4 全绿）——但包一层 ProviderScope 作防御性改动（防以后点导出时炸），计入 §6。
  - S2-2 widget 备注口径（有意设计，产品定夺）、C14 提醒入口徽标是否纳入常驻通知（产品定夺）——两处都不改，等他定。
  - 各半属实条目中不成立的子断言：S2-5「单双周简化成 1-7周」与「checkConflict 与注释不符」；T5(a) 飘窗 Timer 生产泄漏推断；T14「兄弟同步回滚缺乏测试」；C15 的 CurrentSemesterNotifier.updateSemester（全仓无调用方，latent）；C16「撞 1001」（基本不可达，只做 cap 保险）。
  - 「暂无课程」文案：他 2026-11-25 16:57 定「下次改成『暂无课程』四个字」，位置（状态条 / 常驻通知 / 两处）待确认，确认后随本批进（改通知行务必 Dart + Kotlin + 夹具三处同步）。
- **版本**：纯修复、无新功能，按规矩升小号 → **2.16.1+55**（versionCode 2055）。若他想与 262（Gitee）、263（OCR）合进一个大版，则改 2.17.0+55，版本号不变。
- **实施**：Neon 写代码（按 § 分段给，每段独立可落盘；Neon 不可用时按 2026-11-11 既定替代走 DeepSeek flash）；DeepSeek 只读复审（拿用户原始需求 + 本规格）；analyze + 全量测试全绿才发版。

## §1 崩溃 / 数据错乱

- S1-1 `lib/services/backup_service.dart:97` saveTextFile：`uri?.toFilePath()` 前先判 `uri.isScheme('file')`，content:// 时直接返回 `uri.toString()`（或仅返回成功与文件名），不抛 UnsupportedError。
- S1-2 `lib/utils/heuristic_parser.dart`：`_extractWeeks` 区间后必须带「周」（或负向前瞻排除「节」「:」），子串交 `WeekParser.parse` 统一处理单双周；`_extractSections` 加 `1 <= a <= b` 校验；每生成一门草稿课后重置 `lastClassroom`（或仅同块内绑定）。
- S1-3 `lib/models/course.dart:64` Course.fromMap：`dayOfWeek` 钳制到 1..7（或复用 `override_effect.dart` 的安全 `weekdayName()`，同时 `ics_export.dart` 跳过非法星期）。
- S1-4 `lib/services/backup_service.dart:74` restore：恢复事务完成后无论 `data.fonts` 是否为空，都统一同步/重载 `FontsService` 内存列表与数据库注册表。
- S1-5 `lib/services/fonts_service.dart:113` importFont：入口校验扩展名，仅放行 ttf/otf，非法时抛清晰中文提示，不写磁盘也不写注册表。
- C1 `lib/database/db_helper.dart`：upgradeSchema 的 oldVersion < 5 分支 4 条 ALTER TABLE ADD COLUMN 前先查 PRAGMA table_info 跳过已存在列；`_open()` 失败时在 catchError 中把 `_opening` 置空（或提供显式重置）。注：触发须先降级到 ≤v4 再升回；`_opening` 缓存失败是有意设计（2.0.0 复审 C1），恢复靠重启或 resetAllData。
- C2 `lib/database/dao.dart`：setCurrentSemester 检查第二条 UPDATE 受影响行数，为 0 抛错触发事务回滚；insertSemester 若 `s.isCurrent` 为真则强制走事务清零旧标记（或强制以 isCurrent: 0 插入，统一由 switchTo 激活）。getCurrentSemester 补 orderBy（见 §7 合并 A）。
- C3 `lib/pages/week_view_page.dart:589-592`：build 顶部显式处理 currentSemesterProvider（以及 coursesProvider 等）的 hasError 状态，展示带「重试」按钮的错误占位页，不再只判 `value == null` 就转圈。
- C4 `lib/pages/week_view_page.dart:2700/2773`：删除课程项与 canOverride 同口径，仅 `course.id != null` 时渲染（或提前拦截），草稿课（id 为空）点删除不再 `course.id!` 强解崩溃。
- C5 `lib/providers/providers.dart`：addSection（:186-205）加 24:00（1440 分钟）上限钳制，起止不超过 23:59（或无法继续追加时拦截）；applyPresetBigSections（:238-256）放入事务，并同步清理或顺延第 5 节之后的冲突节次（套用后第 4 节 15:10–16:20、第 5 节仍是 11:20–12:00 的倒置必须消除）。
- C6 `lib/providers/providers.dart`：TimeSlotsNotifier（updateSlot/addSection/removeLastSection）、ReminderSettingsNotifier、SegmentSettingsNotifier、BandSettingsNotifier、UiSettingsNotifier.updateWith 写方法入口统一用 `state.value ?? await future` 取已落库基线后再变更（仿 MenuConfigNotifier），不直接读 `state.value ?? 默认值`。
- R3-4 `android/.../OngoingDbReader.kt`：readOngoingEnabled 区分「表正常但无该键（默认开）」与「读表异常（向上返回失败并停链）」；readOverrides 遇到 targetWeek 为空时直接跳过该条异常记录，不按停课处理（现 :195 `?: FocusOverride.CANCEL_FLAG` 会把 NULL 当停课）。

## §2 通知链路（常驻通知 / 提醒 / 小组件）

- C7 `lib/providers/providers.dart:573/586`：ReminderSettingsNotifier.setEnabled / setAdvanceMinutes 改走 `_notifyDataChanged()`（已有现成联动 `_refreshAfterDataChange()` :66-67，rescheduleAll → refresh），不再直接调 `rescheduleAll()`（其第一步 cancelAll 会清掉 id 1001 常驻通知）。settings_sections.dart:537/556/572/589/663 的调用点同样确认无补偿 refresh 缺口。
- C8 `lib/providers/providers.dart`：TimeSlotsNotifier 四个改动作息的方法末尾统一改调 `_notifyDataChanged()`，取代只刷新小组件（现类注释 :162-165 明文写着只挂小部件刷新）。
- C9 `lib/services/notification_service.dart:91`：rescheduleAll() 改用 `tz.TZDateTime(tz.local, year, month, day, hour, minute)` 构造墙上时间；并明确全 App 统一采用「设备本地时区」还是「固定东八区」，消除跨组件分歧。注：Neon 对 `TZDateTime.from` 的描述不精确（from 保留时间戳、不产生小时偏移），真正分叉点是 tz.local 被固定为东八区；主用户在金华（设备 +8）无实际影响。
- C10-scheduleAt `android/.../OngoingCourseReceiver.kt:178/182`：scheduleAt 对 API 23–30 统一使用 setExactAndAllowWhileIdle（现 API<31 用 setExact，Doze 下会被推迟）。
- R3-1 排序稳定性（与 S2-1、C10 orderBy 部分合并，见 §7 合并 A）：双端排序补充确定性次级比较键（开始时刻、结束时刻、课程 id 升序）；Dao.getCoursesBySemester 与 OngoingDbReader.readCourses 统一加 `ORDER BY id ASC`。根因：Dart List.sort 不稳定（>32 元素切双轴快排），Kotlin sortBy 稳定；9 天窗口 sessions 超 32 条是常态，同时间多门课时双端可能选出不同焦点课。
- R3-2 夏令时（与 S2-7 合并，见 §7 合并 B）：Dart 侧前瞻日期改为构造日历日期（按 day + offset 进位，与 ongoing_boundary.dart 写法一致），dayLabel 改用 UTC 日期对象求差值。根因：Dart `today.add(Duration(days: offset))` 与 `difference().inDays` 按 24 小时物理时长，Kotlin LocalDate 按纯日历天；仅非东八区设备受影响。
- R3-3 脏开学日期回退基准：Dart 侧将开学日期解析改为接收参考日期的纯函数，在 computeClassFocus 开头按 today 解析一次后传入 sessionsOnDay，与 Kotlin 侧同构。根因：`semester.dart:51-52` startDateParsed 回退用实时 `DateTime.now()`，且 sessionsOnDay 每次调用都重读；触发窄（脏 startDate + 跨午夜瞬间或非当前时刻重算）。
- S2-1（已并入合并 A，不另立条目）。

## §3 逻辑不一致

- S2-3 `lib/utils/ics_export.dart:28-33`：IcsExporter.build 增加可选参数 overrides，按周调用 effectiveCoursesForWeek 生成实际课次后再输出 VEVENT；`_escapeText`（:124-129）先归一化 `\r\n` / `\r` 为 `\n`。
- S2-4 `lib/utils/reminder_plan.dart:67`：buildDailyReminderPlan 补齐 `week > semester.totalWeeks` 早退判断，与 sessionsOnDay（next_class.dart:135）一致。
- S2-5（修正版）`lib/utils/semester_export_helper.dart:231-239`：formatWeekCapsule 复用 `WeekParser.toText`（或先检测是否等差步长为 2 的纯单/双周再格式化，单周时优先显示 `第X周`），非连续周次不再简化成 `1-12周`，单周仅剩 1 周不再出 `3-3单周`；checkConflict 清理冗余条件并与注释口径一致。注：Neon「单双周简化成 1-7周」不成立（weekType≠0 时有后缀，[1,3,5,7] 实际是「1-7单周」），不按该说法改。
- S2-6 色点统一：抽统一纯函数（例如 `resolveCourseDisplayColor(colorValue, ui.colorScheme, brightness)`），course_card.dart、course_detail_sheet.dart、exam_countdown_page.dart、course_search_page.dart、import_conflicts_page.dart 共用同一入口（映射 + 深色降饱和两项都做）。
- S2-8 `lib/utils/override_effect.dart:137-153`：checkOverrideConflicts 第 2 步遍历 allOverrides 时同步检查 `other.isActiveInWeek(week)`（第 1 步 :130 已查）。
- S2-9 `lib/widgets/week_picker.dart`：initState 初始化 `_selected` 时按 initialWeekType 过滤一次并把 `_weekType` 归一化为 allWeeks（_quickSelect 与 _parseText 已重置，_toggleWeek 未重置）。
- S2-10 `lib/utils/slot_calibrator.dart`：start 上限钳在 1438 并保证 `end >= start + 1`（或对超出当天范围的异常节次做更合理的截断提示），不再产出 23:59–23:59 退化节次。
- C11 `lib/pages/week_view_page.dart:1016/327-332`：未开学（todayWeek <= 0）时隐藏回到本周竖条；其余情况按 `displayWeek != WeekCalc.clampForPage(todayWeek, semester.totalWeeks)` 判断显隐。
- C12 `lib/providers/providers.dart:434-439`：todayWeekProvider 在 AppLifecycleState.resumed 或跨日检测时 `ref.invalidate(todayWeekProvider)`，跨午夜自动重算。
- C13 `lib/pages/week_view_page.dart`：当前周导出行同步改为等待 `coursesProvider.future`（现 :3156 用 `ref.read(coursesProvider).value ?? []`，整学期行 :2968 已改）；`_showEmptySemesterSnackBar`（:2922-2925）与导出分享后的 SnackBar（:2998）在 pop/await 后统一校验 `widget.parentContext.mounted` 后再弹。
- C15 `lib/database/db_helper.dart` + `lib/database/dao.dart`：`_open()` 的 onConfigure 执行 `PRAGMA foreign_keys = ON`（createSchema 已声明 FOREIGN KEY ON DELETE CASCADE，现形同虚设）；updateSemester/updateCourse/updateNote 对 id == null 做断言或抛错（现静默返回 0 行）；收口学期更新仅走 SemestersNotifier.updateSemester。注：CurrentSemesterNotifier.updateSemester 不同步 semestersProvider 一事全仓无直接调用方，属 latent，不单独立项。
- C16 `lib/services/notification_service.dart:338`：排期循环增加安全上限（如最多 400 条），超限截断并记日志，保证 nextId 永远小于 1001。注：触发极端（日均 17+ 条才超 500，注释已算每天 12 节约 360 在安全区内；撞 1001 须日均 34 条），只做便宜保险。

## §4 性能与资源

- S3-1 `lib/services/channel_service.dart:151/156`：fetch() 用 try/finally 确保 `client.close()`；响应体读取加与请求一致的 8 秒超时。注：与 262 的隐患修复重叠，若 262 先行，以 262 的实现为准，不重复改。
- S3-2 局部 TextEditingController 释放：`lib/widgets/draft_edit_dialog.dart`（4 个）与 `lib/pages/notes_page.dart`（`_showEditor` 内）——抽成独立 StatefulWidget 在 dispose() 中释放，或在 showDialog 返回后于 finally 块中统一 dispose()。
- S3-3 `lib/ui/shell_transition.dart`：非当前且透明度归零的 Tab 套上 `TickerMode(enabled: isVisible)` 与 `ExcludeSemantics(excluding: !isCurrent)`（现 ParallaxShellBody `Visibility(maintainAnimation: true)`、QuickFadeShellBody 仅 AnimatedOpacity，隐藏页 MarqueeText 仍 60/120fps 重绘且读屏焦点穿透）。
- S3-4 `lib/pages/changelog_page.dart`：改为 StatefulWidget 在 initState 缓存 Future，并补充 `snap.hasError` 的错误占位展示（现每次 build 重新 loadString 且报错永久转圈）。
- S3-5 `lib/widgets/update_download_dialog.dart`：`_triggerInstall` 增加 `_isTriggeringInstall` 布尔锁防重入（`_startDownload` 已有 P1-4 防双击先例）。
- C17 `lib/pages/week_view_page.dart:282-287`：把 30 秒倒计时与 _ClassFocusBar 拆成独立有状态子组件，仅局部刷新状态条本身；`ui.showClassBroadcast == false` 时不再启动该定时器（现 Timer.periodic 每 30 秒整页 setState 全量重建，关播报仍空转）。
- C18 `lib/providers/providers.dart:38/:85/:260/:338/:379/:424`：6 处 reload() 改为 `state = await AsyncValue.guard(build)`（或 `AsyncLoading().copyWithPrevious(state)`），刷新期间保留旧数据，不再闪全屏转圈。
- C19 `android/.../CourseWidgetProvider.kt`：barBitmapCache 上提至 companion object（限制最大条目数防常驻内存膨胀）；DAY_KEY_FORMAT 的 SimpleDateFormat 改用 `java.time.LocalDate.now()`；parsePayload 重载直接接收 JSONObject 避免二次解析。
- C20 `lib/database/dao.dart:72-88`：deleteSemester 按课程列表循环逐条删 course_overrides 改为单条子查询 SQL 批量删除。

## §5 体验与文案

- S4-1 `lib/widgets/draft_edit_dialog.dart:150`：拆出独立的 nameError 挂在课程名输入框上（现课程名为空时把 `'课程名不能为空'` 赋给了 weekError，报错出现在周次框下），输入变化时自动清空。
- S4-2 `lib/pages/notes_page.dart:51-52`：ListView 底部 padding 增至 88dp 左右（或按 FAB 高度留足安全空间），末条备注卡片右侧删除图标不再被 FAB 挡住。
- S4-3 `lib/pages/notes_page.dart:208` 与 `lib/widgets/semester_form_dialog.dart:180`：弹窗内表单校验改为输入框内联 errorText 提示，不再用 ScaffoldMessenger.of(ctx).showSnackBar（会出现在遮罩后的底层 Scaffold，小屏易被键盘挡住）。
- S4-4 `lib/ui/settings_entry_row.dart:192`：震动判断改为 `(v - value).abs() > 1e-6` 触发（带 divisions 的 Slider 回调本身已是离散档位，AppHaptics 内部已有 45ms 节流兜底；现 `v.round() != value.round()` 使 0.0–3.0/30 档滑杆全程只震约 3 次）。
- S4-5 `lib/widgets/marquee_text.dart`：`MediaQuery.disableAnimationsOf(context)` 为 true 时强制 `shouldScroll = false`，回退为静态省略号文本。
- S4-6 `lib/utils/widget_data.dart:127-141`：toRow 中复用 `CourseDisplayFormatter.formatCourseName` 与 `formatClassroom`（现直接用原始 course.name / course.classroom，小部件里仍显示 [选修]、校区前缀或尾部符号）。
- S4-7 `android/app/build.gradle.kts` + `android/gradle.properties` + `android/build.gradle.kts`：把 keystore 存在性判断抽成一个局部布尔值供 signingConfigs 与 buildTypes.release 共用（现前者校验路径存在且 >0，后者只判 env 非空，指向不存在文件时构建失败而非回退 debug 签名）；默认 `-Xmx` 由 8G 降至 4G（本地需要更大内存放用户级 `~/.gradle/gradle.properties`）；清理冗余的 `allprojects.repositories`。
- S4-8 文档/注释同步：help_page.dart（注释「三个操作」实际 4 项，路径指引与现 3 层设置页核对）；README.md（「20:00 后自动显示明日预告」与实际「当日无剩余课程即切明日」不符）；ics_export.dart（PRODID 与 UID 域名仍残留旧名 `simple-timetable / jiankebiao 1.0`）；pdf_import.dart（像 OcrService 一样顺带提取左侧节次时间）。
- C21 `lib/pages/week_view_page.dart:2246/:2294`：空周占位引导文案改为「点击空白格子新建，或点右上角「+」导入课表」（现写「从底部「新建」导入课表」，底栏已是「今日 / 课表 / 我的」）。
- C22 `lib/pages/settings_page.dart`：semesterSubtitle 在 todayWeek <= 0 显示「未开学」，超过 totalWeeks 显示「已结束」（现直接拼 `第 $todayWeek 周`，未开学显示「第 0 周」）；appearanceSubtitle 去掉恒定的「标签栏」字样；reminderSubtitle 关闭时精简为「未开启」。
- C23 `lib/pages/week_view_page.dart:509-511/172-185`：_showDayExams 先 Navigator.pop(ctx) 再 Navigator.pushNamed（现先 push 再在 .then 里 pop，返回时闪一下旧弹窗）；_loadChannel() 的 `PackageInfo.fromPlatform()` 补 try/catch 兜底。
- C24 `lib/database/dao.dart`：类注释承诺「统一捕获并抛出中文异常」与实际脱节——在 UI 失败提示或 DAO 层统一转换友好中文文案，原始异常仅打 debugPrint 日志（全文件现无一处 try/catch，底层 DatabaseException 英文堆栈直达 UI）。

## §6 测试修复

- T1（防御性）`test/wb257_menu_order_test.dart`：末尾「课表工具页：6 个入口顺序」用例外层补包 ProviderScope（现单跑 4/4 全绿、指控为假；包一层是防以后有人在该用例里点导出时炸）。
- T2 `test/wb231_empty_week_placeholder_test.dart:44`：sundayDialogNow 改为固定日期（已知非周日的常量）或显式对齐到本周一（现 `DateTime.now().subtract(Duration(days: 1))`，周一跑时「昨天」恰是周日，会触发周日弹窗遮挡页面）。
- T3 `test/wb236_custom_band_tile_test.dart`：setUp 先查询并更新默认学期，或清空 semesters 后再插入测试学期（现 createSchema 已插一条 isCurrent=1 的默认学期，setUp 又直接 insertSemester(isCurrent: true)，库里两条 isCurrent=1）。
- T4 `test/fixtures/ongoing_focus_cases.json` + `test/ongoing_focus_fixture_test.dart`：补 4 类用例——now == start / now == end 踩点（08:00 / 09:30）、开学前 ≤9 天预告（开学前 3 天）、跨周调课与同时间重叠、纯空白/多行备注；脏数据用例基准时间改为可控注入（现直接用 DateTime.now()）。
- T5(b)(c) `test/wb242_edit_mode_toast_test.dart`：slots14() 第 14 节 23:35–00:20 改为合法递增时间或直接复用 defaultTimeSlots；长按空白格改用稳定 Key 定位，删硬编码 `Offset(width * 0.35, height * 0.28)`。注：(a) 飘窗 Timer 推断不成立（生产代码已修，dispose 与手动关闭都 cancel），测试末尾 pump(3500ms) 只是残留收尾——顺手删掉，不单独立项。
- T6 `test/db_migration_217_test.dart`：补充从早期版本（至少含无 notes / 无 course_overrides 的历史 schema）逐级或跨级升到当前版本的集成测试（现只验证 v6→v7 删两个设置键）。
- T7 `test/app_haptics_test.dart:58-61`：删掉误导性断言，或改为静态检查 lib/utils/app_haptics.dart 与业务源码中不存在 heavyImpact 调用（现标题「不提供 heavyImpact」，断言体只校验 throttleWindow == 45ms）。
- T8 `test/wb231_onboarding_test.dart`：抽离或直接接入生产根门卫（main.dart:519）的完成逻辑来测试，或单独对启动门卫做 widget 测试（现测试 harness 自带与根门卫一字一致的 onDone 写库再断言，只测了页面调没调回调）。
- T9 三处 `sectionCount: 14` 改 `defaultTimeSlots.length`：test/wb239_semester_single_image_test.dart:153、test/wb244_semester_export_align_test.dart:45、test/pages/course_card_display_test.dart:173（传的 defaultTimeSlots 只有 13 节）。
- T10 `test/wb236_custom_band_tile_test.dart:114`：像 todayViewNow / sundayDialogNow 一样为 TimeSettingsPage 注入可替换时钟，测试中分别锁定早/午/晚三个固定时刻（现 `currentTimeBand(DateTime.now())`，分界整点附近有跨分钟风险）。
- T11 `test/wb261_cleanup_test.dart:223` 与 `test/wb257_menu_order_test.dart`：补 `addTearDown(container.dispose)`；HomeShell 类测试收尾统一卸载树并排空定时器（现手动建 ProviderContainer 未注册 dispose，用例结束既未销毁 widget 树也未推进假时钟）。
- T12 固定 1500ms 死等：提取统一测试辅助函数（如 test/helpers/pump_helpers.dart），以条件轮询（pumpUntil）替代 `Future.delayed(1500ms)` + 多轮抽水样板（wb231:76、week_title_focus_frame_test.dart:99、wb257:105、import_target_default_new_test.dart:74 等）。
- T13 `test/wb232_share_no_watermark_test.dart`：第二个用例拆出为独立纯 test，并把分享文案生成抽成纯函数直接做单测，不再正则/字面量读源码（现只做字符串匹配却挂在 testWidgets 且共享开关内存 SQLite 的 setUp/tearDown）。
- T14-hook `test/wb246_same_name_weeks_test.dart:123`：删 tearDown 里无用的 `Dao.debugBeforeUpdateCourse = null` 重置（全文件别处不用该钩子）。注：「兄弟同步回滚缺乏测试」不成立（wb231_course_multi_slot_test.dart:301 已有整批回滚用例），不补。
- T15 测试结构：后续补 course_dao_test.dart / override_dao_test.dart（核心数据层 Course CRUD、调课级联清理、批量导入覆盖事务缺独立 DAO 级测试）；wb240:34 与 wb242:153 重复断言同一飘窗文案，合并收敛。

## §7 合并说明（三处重叠，只修一次）

- 合并 A（排序 + ORDER BY）：S2-1（Dart/Kotlin 排序）+ C10 的 getCoursesBySemester 无 orderBy 部分 + R3-1（排序稳定性）。一次改动：双端排序补次级键（开始、结束、课程 id 升序）+ 两端 SQL 加 `ORDER BY id ASC`。
- 合并 B（夏令时）：S2-7（日期差未转 UTC）+ R3-2（夏令时日期推算）。一次改动：Dart 侧三处（week_calc.dart、term_start_date_helper.dart、next_class.dart）统一改用 UTC 日历日期差值。
- 合并 C（S3-1 与 262 重叠）：ChannelService.fetch() 的 HttpClient 泄漏 + 响应体无超时，与 WB_SPEC_262 §2 的隐患修复是同一处。若 262 先行，以 262 的实现为准，本批不重复改；若本批先行，按 §4 S3-1 改，262 落盘时以本批为准。

## §8 测试计划

- 每项修复配回归测试或断言更新：新增测试优先放在对应 wb264_*_test.dart（按 § 分组命名）；夹具改动（T4）同步更新 ongoing_focus_cases.json 与 Dart/Kotlin 双端断言（改夹具务必 Dart + Kotlin + 夹具三处同步，否则 CI Kotlin 单测必红）。
- 全量回归：`flutter test --no-pub`（一次只跑一个进程；跑前查 sqlite3 软链；pumpAndSettle 在主页会 hang，一律手动泵）+ `flutter analyze` 零问题；CI 只跑 Kotlin 单测与打包，本机 Gradle 跑不了。
- 发版前 DeepSeek flash 只读复审（拿用户原始需求原话 + 本规格全文），高/中必修；跳过须在发版汇报里如实说明。
