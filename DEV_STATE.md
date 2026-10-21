# 简课表 · 开发状态备忘（给下一阶段 / 真机验收用）

> 更新时间：2026-10-20（阶段六·作息时间三段化 + 导入校准作息）

## 做到哪了

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
flutter test               # 135 + 6 = 141 个用例应全绿（本机代理会导致 flutter_tester 连接失败）
```

已知风险点（analyze/test 若报错优先查这里）：
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
