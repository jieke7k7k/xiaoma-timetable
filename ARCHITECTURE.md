# 简课表 · 架构备忘录

> 每完成一个阶段更新本文件，防止上下文丢失。

## 项目信息

- 项目路径：`D:\WorkBuddy\2026-10-14-16-48-07\simple_timetable`
- 包名：`com.example.simple_timetable`，应用显示名「简课表」
- 技术栈：Flutter 3.47.7 stable（SDK 位于 `D:\flutter`）+ Dart 3 空安全
- 依赖：`sqflite` + `path`（手写 SQL）、`flutter_riverpod`（手写 Notifier）、`intl`；阶段四新增 `flutter_local_notifications ^22.3.2` + `timezone ^0.10.0`（本地通知/精确闹钟）+ `home_widget ^0.10.0`（桌面小组件，均不用 build_runner）
- 国内镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（已写入用户环境变量）
- 注意：运行 `flutter test` 需先清空代理环境变量并设 `NO_PROXY=localhost,127.0.0.1`（本机 Clash 系统代理会导致 flutter_tester WebSocket 连接失败）

## 构建环境（Android 真机/APK 构建，已踩坑并解决）

- **JDK**：`flutter config --jdk-dir D:\Java\jdk-17` 强制用 Temurin JDK 17（Flutter 默认会抓 Android Studio 的 JBR = Java 25，与 Gradle 9.3.1 不兼容导致卡死）
- **Gradle 插件源**：`plugins.gradle.org` 在校园网下 body 传输 0 速度，已用全局 `C:\Users\10111\.gradle\init.gradle` 重定向到阿里云 gradle-plugin 镜像
- **项目内镜像**：`android/settings.gradle.kts`、`build.gradle.kts` 已加阿里云 google/central/gradle-plugin 镜像优先；`gradle.properties` 已加 `systemProp.java.net.preferIPv4Stack=true`
- **构建命令**：先 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy`（设空值会让 sdkmanager 报 no protocol），再 `flutter build apk --debug`
- 产物：`build/app/outputs/flutter-apk/app-debug.apk`

### 阶段三新增的坑（重要，阶段四/五仍会遇到）

- **mavenCentral 大文件被限速（~10KB/s）**：`repo.maven.apache.org`（Cloudflare）在校园网下下载大 jar 极慢。根因是 Flutter 3.47 模板 + AGP 9 已弃用 `allprojects.repositories`，必须在三处加阿里云镜像：
  1. `android/settings.gradle.kts` 的 `dependencyResolutionManagement.repositories`（主项目依赖）
  2. `D:\flutter\packages\flutter_tools\gradle\settings.gradle.kts`（Flutter 工具 includeBuild，FAIL_ON_PROJECT_REPOS 模式）
  3. 全局 `C:\Users\10111\.gradle\init.gradle` 的 `beforeProject` 注入 `buildscript.repositories`（覆盖 url_launcher 等第三方插件的 kotlin-gradle-plugin 依赖）
  - 注意：init.gradle 里**不要**注入 `project.repositories`，会与 FAIL_ON_PROJECT_REPOS 冲突报错
- **Kotlin 增量编译跨盘符**：pub cache 在 C 盘、项目在 D 盘，Kotlin 增量缓存报 "different roots"。已在 `gradle.properties` 加 `kotlin.incremental=false`
- **compileSdk 版本**：Flutter 3.47 默认 compileSdk=36，但 `file_picker 8.x` 硬编码 34 导致 AAR metadata 报错，已升到 `file_picker 13.x`（其 API 从 `FilePicker.platform.pickFiles` 改为 `FilePicker.pickFiles` 返回 `List<PlatformFile>`）
- **PDF 文本提取库选型**：`dart_pdf` 已无文本提取 API；`pdfrx 1.x` 与 Dart 3.13 不兼容（null 安全 bug）、`pdfrx 2.x` 需运行时下载 GitHub 的 PDFium（校园网不可达）；最终用 **`syncfusion_flutter_pdf`（纯 Dart）**，其 `PdfDocument(inputBytes:)` + `PdfTextExtractor.extractText()`

## 数据表结构（v2，建库时一次性建好，含阶段五预留字段/表）

- **semesters**：`id` PK、`name`、`startDate`(TEXT, ISO yyyy-MM-dd)、`totalWeeks`(默认20)、`isCurrent`(0/1)
- **time_slots**：`section` PK(1~12)、`startTime`、`endTime`（首启内置 12 节默认时间）
- **courses**：`id` PK、`semesterId` FK、`name`、`teacher?`、`classroom?`、`colorValue`(ARGB int)、`dayOfWeek`(1~7)、`startSection`、`endSection`、`weeksJson`(周次数组 JSON)、`weekType`(0全部/1单/2双)、`note?`、`examDate?`(毫秒时间戳，阶段五预留)；索引 `idx_courses_semester(semesterId, dayOfWeek)`
- **course_overrides**（阶段五预留）：`id` PK、`courseId` FK、`originalWeek`、`targetWeek`(-1=停课标记 `CourseOverride.cancelFlag`)、`targetDayOfWeek?`、`targetStartSection?`、`targetEndSection?`、`targetClassroom?`
- **app_settings**（v2 新增，阶段四提醒设置持久化）：`key` PK、`value`；当前键 `reminder_enabled`("1"/"0")、`reminder_advance_minutes`("15")、`ongoing_enabled`("1"/"0")、`theme_mode`("system"/"light"/"dark"，阶段五)、`lunch_after_section`("5")、`dinner_after_section`("9")（阶段六·作息三段化）。`_dbVersion=2`，`onUpgrade` 对 v1 库补建此表。

首启自动创建：默认学期（2026-09-07 开学、20 周、isCurrent=1）+ 12 节默认节次时间。

## 核心 Provider（lib/providers/providers.dart）

- `currentSemesterProvider` — `CurrentSemesterNotifier extends AsyncNotifier<Semester>`：`updateSemester()` 改开学日期/总周数后即时刷新；`reload()` 重新加载；`setDirectly()` 免 Loading 直接写入（切学期专用，防闪烁）
- `semestersProvider` — `SemestersNotifier extends AsyncNotifier<List<Semester>>`：学期列表 + `addSemester()` / `switchTo()` / `deleteSemester()`（删除当前学期抛异常兜底）
- `timeSlotsProvider` — `TimeSlotsNotifier extends AsyncNotifier<List<TimeSlot>>`
- `coursesProvider` — `CoursesNotifier extends AsyncNotifier<List<Course>>`（watch 当前学期，切学期自动联动）
- `reminderSettingsProvider` — `ReminderSettingsNotifier extends AsyncNotifier<ReminderSettings>`：上课提醒开关 + 提前分钟，读写 `app_settings` 表，改动即持久化并触发 `NotificationService.rescheduleAll()`（阶段四）
- `segmentSettingsProvider` — `SegmentSettingsNotifier extends AsyncNotifier<SegmentSettings>`：作息三段化分段点（午休/晚餐在第几节课之后），读写 `app_settings` 表 `lunch_after_section`/`dinner_after_section`，供作息设置页与周视图共用（阶段六）

## 阶段六·作息时间三段化新增/改动文件（2026-10-20）

| 文件 | 职责 |
|---|---|
| `lib/providers/providers.dart` | 新增 `SegmentSettings`（lunchAfterSection/dinnerAfterSection）+ `SegmentSettingsNotifier`/`segmentSettingsProvider`（AsyncNotifier，读 `Dao.getSettingInt('lunch_after_section', 5)` / `getSettingInt('dinner_after_section', 9)`，写 `Dao.setSetting('key', '$value')`）；`setLunchAfterSection` 钳制到 [1, 晚餐点-1]，`setDinnerAfterSection` 钳制到 [午休点+1, +∞)，保证午休点 < 晚餐点 |
| `lib/pages/time_settings_page.dart` | 逐节时间列表改「上午/下午/晚上」三段分组（段标题 + 各节卡片，点击改时间交互不变）；新增顶部「分段设置」卡片（两个 `_SegmentStepper` 步进器，晚餐上限按当前最大节次钳制）；段间插入间隔信息行（由上一段末节 endTime 到下一段首节 startTime 自动算出，`_formatDuration` 格式化「约 X 小时[ Y 分钟]」/「约 Y 分钟」）；一键套用卡片保留 |
| `lib/pages/week_view_page.dart` | 删除 `const _bands`（原硬编码 4/8）；`_GridArea.build` 用 `ref.watch(segmentSettingsProvider)` 动态生成 `activeBands`（午休 after=lunch、晚间 after=dinner，未加载回退 5/9），沿用「after < sectionCount 过滤」与高度守恒逻辑 |

## 阶段六·作息时间三段化设计决策（2026-10-20）

- **分段点单一数据源**：`segmentSettingsProvider` 是午休/晚餐分段点唯一来源，作息设置页（分组 + 步进器）与周视图（分隔带 after）都 watch 它，杜绝两处硬编码漂移。键名 `lunch_after_section`/`dinner_after_section`，存进现有 `app_settings` 键值表（不改表结构、不新引依赖）。
- **钳制只在 Notifier 层做午休<晚餐不变量**，晚餐上限（≤ 最大节次）在设置页步进器按 `slots.length` 钳制；周视图靠既有「after < sectionCount 过滤」保证只保留落在节次范围内的分隔带，二者独立不互相依赖。
- **间隔时长纯函数在页面内**（`_toMinutes`/`_minutesBetween`/`_formatDuration`）：跨天按 +24h 兜底；`>=60` 分钟输出「约 X 小时[ Y 分钟]」（Y=0 省略分钟），`<60` 输出「约 Y 分钟」，文案「午休 12:00 – 14:00 · 约 2 小时」。
- **周视图文案与设置页不同**：周视图分隔带标签沿用「午休」「晚间」（`_DividerBand`），设置页间隔行用「午休」「晚餐」（与三段「上午/下午/晚上」对应），符合规格要求。

## 阶段六·导入按课表文件校准作息（第 3 项）新增/改动文件（2026-10-20）

| 文件 | 职责 |
|---|---|
| `lib/utils/ics_parser.dart` | 新增 `IcsTimeBlock`（startSection/endSection/startTime/endTime，时间 "HH:mm"）；`IcsParseResult` 新增 `timeBlocks` 字段；`_parseEvent` 改返回 `({Course course, IcsTimeBlock timeBlock})?`，每个成功事件产出一块。节次取值：优先 `_extractSectionRange` 从 DESCRIPTION 解析「第 X - Y 节」/「第X节」，解析不到回退为按钟点匹配出的 startSection/endSection；startTime 由 DTSTART 时分格式化，endTime 由 DTEND 时分格式化，缺失 DTEND 时用该块 endSection 现有作息下课时间兜底、找不到则留空 |
| `lib/utils/slot_calibrator.dart`（新建） | 纯函数 `SlotCalibrator.calibrate(slots, blocks)`：块的 startTime 只覆盖 startSection 的开始时间、endTime 只覆盖 endSection 的结束时间；按「节次+字段」粒度保留第一个值跳过冲突；未触及节次不变；非法/空时间跳过；返回新列表不修改入参 |
| `lib/pages/import_page.dart` | `_openReview` 增加可选参数 `timeBlocks`（默认空），仅 ICS 路径传 `parsed.timeBlocks`，图片/PDF 不传 |
| `lib/pages/import_review_page.dart` | `ImportReviewPage` 增加可选参数 `timeBlocks`（默认空）；`_importAll` 课程全部导入成功后按 timeBlocks 校准作息并逐节 `updateSlot` 持久化，SnackBar「已按课表文件校准作息时间」；校准失败 catch + debugPrint 静默，不回滚已导入课程 |
| `test/slot_calibrator_test.dart`（新建） | 6 个用例：单块覆盖首尾、相邻块共享节次、冲突保留第一个、未触及节次不变、非法/空时间跳过、不修改入参 |

## 阶段六·导入校准作息设计决策（2026-10-20）

- **校准块与课程解耦**：`IcsTimeBlock` 的节次区间优先取 DESCRIPTION 文本里的「第 X - Y 节」，与 Course 按钟点匹配的节次可能不同（文本更权威）；解析不到才回退到与 Course 相同的节次。startTime/endTime 直接来自 DTSTART/DTEND 时分，不经过 `_matchSection` 的钟点匹配。
- **缺失 DTEND 的处理（已选方案）**：用该块 endSection 现有作息的下课时间兜底填充 endTime——校准阶段该字段值与原值相同、等价于跳过该块的结束覆盖；找不到对应节次则留空，由 `_isValidHm` 跳过。未选「跳过结束覆盖」方案。
- **冲突按「节次+字段」粒度**：startTime 与 endTime 各用独立的 seen 集合，第 N 节的 startTime 与 endTime 互不干扰，因此「1-3 节块给第 3 节 endTime、3-5 节块给第 3 节 startTime」能共同生效；同字段不同值保留第一个。
- **校准不阻断导入**：校准在课程全部导入、`coursesProvider.reload()` 之后执行；异常仅 debugPrint，不回滚课程、不弹失败提示（选静默，非另给失败提示）。

## 工具类

- `WeekCalc`（lib/utils/week_calc.dart）：`alignToMonday` / `currentWeek`(未开学返回0) / `isOddWeek` / `weekDates` / `weekDatesOf` / `weekTitle`；20 个单元测试全绿（test/week_calc_test.dart）
- `Course.isActiveInWeek(week)`：周次列表 ∩ 单双周过滤

## 已完成进度

- [x] **阶段一**：项目初始化；四表 sqflite 落地；底部导航三入口（课表/新建/设置）；设置页可改开学日期与总周数并即时联动主页周次显示；WeekCalc + 单元测试；`flutter analyze` 零问题、`flutter test` 20/20 通过
- [x] **阶段二**：7 列 × N 节次网格周视图（跨节合并、PageView 切周、周次跳转条、回到本周、今天高亮）；课程增删改查（空白格新建、长按菜单、详情 BottomSheet）；周次选择器（可视化点选 + 全选/单周/双周 + 文本解析「1-8, 10-16单周」）；作息时间设置页（逐节改时间 + 一键套用大节时间）；**莫兰迪色系课程色板**（lib/utils/morandi_palette.dart，16 色）；设置页「显示非本周课程」开关；`flutter analyze` 零问题、`flutter test` 41/41 通过
- [x] **阶段三**：冲突检测（`ConflictDetector`，8 用例）；课程导入入口页（ICS/OCR/PDF + 教务预留）；人工核对页（草稿编辑/删除/补录）；冲突弹窗（跳过/覆盖/保留两者）；ICS 解析器（`IcsParser`，自动匹配星期/节次/周次）；图片 OCR（google_mlkit 中文脚本 + 启发式解析）；PDF 文本提取（syncfusion，复用启发式解析）；Android 相机/相册权限 + MLKit 中文模型依赖；`flutter analyze` 零问题、`flutter test` 49/49 通过、APK 构建成功
- [x] **阶段三收尾**（2026-10-15）：批量导入漏洞修复（同批自冲突检测/覆盖延迟删除/空周次拦截+默认填满/PopScope 防误触/周次格式化显示）；冲突描述补星期几；底部导航重构（IndexedStack 只留课表+设置，新建改 ModalBottomSheet）；周视图三态布局（`slot_layout.dart`，本周优先/非本周淡化/同格 multi +「+N」角标+迷你选课）；午休/晚间 20px 分隔带（高度守恒）；周末无课自动收起 5 列（设置开关）；备注圆点角标；详情页「新增本课其他时段」快捷录入；HapticFeedback 三处触感；导入失败三按钮（复制错误报告/重新选择/返回）；`flutter analyze` 零问题、`flutter test` 59/59 通过
- [x] **阶段四·多学期管理**（2026-10-15）：学期管理页（新建/切换/删除 + 二次确认 + 当前学期禁删禁切）；`semestersProvider`（SemestersNotifier，switchTo 统一联动入口）；`db_helper` 公开 createSchema + 测试注入；新增 7 个学期联动单元测试（sqflite_common_ffi 内存库）。**注意：本轮在无法执行命令的环境完成，`flutter pub get`（新增 dev 依赖 sqflite_common_ffi）与 analyze/test 未跑，验证命令见 DEV_STATE.md**
- [x] **阶段四·上课本地通知提醒**（2026-10-15）：`flutter_local_notifications` + `timezone`；`NotificationService`（初始化/渠道/权限/滚动窗口重排/次日0点自举）；`ReminderSettingsNotifier`（开关+提前分钟，app_settings 表持久化）；`BootReceiver`（Kotlin）+ Manifest 三权限+receiver；纯逻辑 `reminder_plan.dart` + 11 个单元测试；挂点：`switchTo`/`addCourse`/`updateCourse`/`deleteCourse` 末尾 `rescheduleAll()`。**本轮同样无法执行命令，pub get/analyze/test/APK 未跑，见 DEV_STATE.md**
- [x] **阶段四·今日课程常驻通知栏**（2026-10-15）：`OngoingNoticeService` + MethodChannel + Kotlin 前台 Service（InboxStyle 可折叠、specialUse）；纯逻辑 `ongoing_notice.dart`（B 决策：今日有未下课课程就显示今日剩余，仅当全部下课才切明日预告）+ 5 个单元测试；`OngoingNoticeSettingsNotifier` 开关（app_settings `ongoing_enabled` 默认开，关闭即清通知停服务）；挂点 switchTo/addCourse/updateCourse/deleteCourse + HomeShell.initState。**本轮无法执行命令，pub get/analyze/test/APK 未跑，见 DEV_STATE.md**
- [x] **阶段四·桌面小组件**（2026-10-15）：`home_widget ^0.10.0`；`WidgetService.refreshWidgets()`（复用 `buildOngoingNotice` 出标题+行列表，saveWidgetData 下发 widget_title/widget_lines，updateWidget 触发刷新）；Android 原生 `CourseWidgetProvider`（继承 `HomeWidgetProvider`，RemoteViews 渲染标题+最多 3 行，点击 PendingIntent 唤起 App）+ `course_widget.xml`/`course_widget_info.xml`/`course_widget_background.xml` + Manifest receiver；挂点 switchTo/addCourse/updateCourse/deleteCourse + HomeShell.initState；设置页加小组件说明。**本轮无法执行命令，pub get/analyze/test/APK 未跑，小组件显示/点击/桌面启动器兼容性必须等小米 14 真机验证，见 DEV_STATE.md**
- [ ] 阶段五：深色打磨（**深色模式深度适配已完成 2026-10-15，见下文专节**）、**JSON 备份恢复 + ICS 导出（已完成 2026-10-15，见下文专节）**、**考试倒计时（已完成 2026-10-15，见下文专节）**、**节假日单次调课（已完成 2026-10-15，见下文专节）**、**视觉打磨（已完成 2026-10-15，见下文专节，含纯 Dart 启动页；应用图标未涉及）**

## 阶段五·节假日单次调课新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/utils/override_effect.dart` | 纯逻辑：`overridesForWeek`/`overrideForCourse`/`movedCourseIds`/`effectiveCoursesForWeek`（应用调课出「本周有效上课实例」）/`checkOverrideConflicts`（落库前冲突检测）/`describeOverride`/`weekdayName` |
| `lib/database/dao.dart` | 新增 `getOverridesBySemester`（JOIN courses 按学期过滤）与 `upsertOverride`（事务内先删 (courseId, originalWeek) 旧记录再插入，同周重复调整=覆盖）；原阶段五预留的 `getOverridesByCourse`/`insertOverride` 被这两个替换（确认无调用方） |
| `lib/providers/providers.dart` | 新增 `CourseOverridesNotifier`/`courseOverridesProvider`（watch 当前学期自动联动）；`saveOverride`/`deleteOverride` 末尾三联动（提醒重排/常驻通知/小组件，同课程增删改挂点） |
| `lib/utils/reminder_plan.dart` | `buildDailyReminderPlan` 新增可选参数 `overrides`：先经 `effectiveCoursesForWeek` 应用调课——停课的本次不排提醒，调课的按新星期/节次/教室排 |
| `lib/utils/ongoing_notice.dart` | `buildOngoingNotice` 新增可选参数 `overrides`；今/明两天各自按所在周次应用调课（周日晚→周一早跨周次场景） |
| `lib/services/notification_service.dart` | `rescheduleAll` 读当前学期调课记录传入提醒计划 |
| `lib/services/ongoing_notice_service.dart` | `refresh()` 读调课记录传入 `buildOngoingNotice` |
| `lib/services/widget_service.dart` | `refreshWidgets()` 读调课记录传入 `buildOngoingNotice` |
| `lib/pages/week_view_page.dart` | 周视图渲染前应用调课（停课隐藏、调课按新时间/教室显示）；被调整的单课卡片显示「调」角标（复用现有角标样式，深色下自动反色）；长按菜单新增「调整本次」/已有调整时「查看/撤销本次调整」；周末自适应收起也按调课后结果计算 |
| `lib/pages/course_override_page.dart` | 单次调整页（路由 `/course-override`，参数 `{courseId, week}`）：原时间信息卡 + 「本次停课」开关 + 新星期/节次/教室选择；已有调整时回显并可撤销；保存前冲突确认框（仍要保存/返回修改） |
| `lib/main.dart` | 注册 `/course-override` 路由 |
| `test/override_effect_test.dart` | 19 个用例：按周应用（停课移除/调整替换/其他周不受影响/无效 override 忽略/草稿课豁免/教室沿用）、角标集合、提醒计划联动（停课不提醒/调课按新时间新教室）、常驻通知文案联动、冲突检测（含端点相接不算、对方停课/被调走后原位置不算、调到对方新位置算） |

## 阶段五·节假日单次调课设计决策（2026-10-15）

- **targetWeek 语义收紧**：调整类型一律 `targetWeek = originalWeek`（只支持周内改星期/节次/教室，不跨周调）；停课类型 `targetWeek = cancelFlag(-1)`。调整记录的星期/节次恒存完整值（没改就存原值），教室为 null 表示沿用原教室——不支持「清空教室」，调整页留空即沿用，语义唯一无歧义。
- **四处口径统一在 `effectiveCoursesForWeek`**：周视图渲染、提醒计划、常驻通知、小组件全部先经这一个函数得到「本周有效上课实例」，杜绝四处各写一遍过滤逻辑导致口径漂移；该函数返回 `Course` 副本（copyWith 保留 id 与 weeks），slot_layout 三态布局、详情 BottomSheet 无需感知调课。
- **override 失效情形**：课程在 originalWeek 本就不上课（weeks 不含）时记录无效忽略；草稿课（id 空，导入核对场景）天然无调课关联；同一 (courseId, originalWeek) 至多一条，由 `upsertOverride` 事务先删后插保证。
- **冲突检测不复用 ConflictDetector**：单次调课只针对一周，且需跳过该周已停课/已被调整课程的原位置（它们的位置已不存在）、改查被调整课程的新位置——与「两门常规课全学期比对」语义不同，硬套会产生误报。`checkOverrideConflicts` 返回中文描述列表供确认框直接展示；端点相接（第 2 节结束 vs 第 3 节开始）不算冲突。冲突是警告不是阻断，用户可选「仍要保存」。
- **「调」角标复用 CourseCard 既有角标通道**（badgeText）：深色模式下角标自动反色为浅块深字，无需新写深色适配；multi 格让位给「+N」（调整信息长按菜单可见）。
- **长按菜单按已有调整分流**：无记录→「调整本次」；有记录→「查看/撤销本次调整」（副标题显示 describeOverride 摘要）；草稿课（id 空）不显示该入口。originalWeek = 长按所在页的浏览周次。
- **刷新挂点**：`CourseOverridesNotifier.saveOverride/deleteOverride` 末尾与课程增删改完全一致的三联动（rescheduleAll / 常驻通知 refresh / 小组件 refresh），因为调课会改变未来 7 天提醒计划与今日课程文案；`switchTo` 切学期无需额外改动（overridesProvider watch 当前学期自动重建，三服务自己读库）。
- **停课记录不存目标时间**：targetDayOfWeek/targetStartSection/targetEndSection 全空，UI 上开关打开即隐藏时间选择，杜绝「停课但带着半个时间」的脏数据。

## 阶段五·考试/作业倒计时新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/utils/exam_countdown.dart` | 纯逻辑：`ExamCountdown.daysUntil(examDate, now)`（按日历日期差算天数，忽略时分秒）+ `countdownText(days)`（>0「还有 X 天」/ 0「今天考试」/ <0「已结束」） |
| `lib/pages/exam_countdown_page.dart` | 考试倒计时页（路由 `/exam-countdown`）：读 `coursesProvider` 筛 `examDate` 非空课程按日期升序，卡片显示课程色点 + 课程名 + 日期星期 + 倒计时文案；空状态与加载失败中文兜底 |
| `lib/pages/course_edit_page.dart` | 表单新增「考试日期」：日期选择器（2020~2035）+ 清除按钮；保存进 `Course.examDate`（毫秒时间戳，可空） |
| `lib/widgets/course_detail_sheet.dart` | 详情 BottomSheet 新增「考试」行（设置了才显示）：日期 + 倒计时文案 |
| `lib/pages/week_view_page.dart` | 周视图 AppBar 新增考试倒计时入口 IconButton（入口选型理由见 DEV_STATE.md） |
| `lib/main.dart` | 注册 `/exam-countdown` 路由 |
| `test/exam_countdown_test.dart` | 10 个用例：当天/前后若干天/跨月/跨年/忽略时分秒/毫秒时间戳往返/三种文案 |

## 阶段五·考试倒计时设计决策（2026-10-15）

- **天数按日历日期差**：`daysUntil` 先把两个日期都截到 `DateTime.utc(y, m, d)` 再作差——UTC 无夏令时，本地时间直接 `difference().inDays` 在夏令时切换日会因 23/25 小时截断差一天；中国虽无夏令时，但函数应无条件正确。
- **清除考试日期的落库路径**：`Course.copyWith` 的 `examDate` 参数用 `??` 合并、传 null 不会清空，因此编辑页不走 copyWith 更新，而是整对象构造 `Course(examDate: _examDate)` 后走 `updateCourse` 整行落库，null 能正常写回数据库清空字段（无需改 Dao）。
- **倒计时颜色语义**：临近（>0）用 `colorScheme.primary`、当天（=0）用 `colorScheme.error` 红色警示、已结束（<0）用 `colorScheme.outline` 置灰，全部语义色，深色模式自动适配。
- **课程色点深色降饱和**：倒计时页与详情页的色点沿用 `MorandiPalette.desaturateForDark`（同 course_card 逻辑），深浅两套界面同一门课同色系。
- **入口选在周视图 AppBar**（IconButton `event_note`）：倒计时属高频查看项，首页一眼可达；设置页条目已很多且考试数据源自课程，与课表更近。理由同步记入 DEV_STATE.md。
- **无新依赖**：日期展示课程编辑页用手工格式化、详情/倒计时页复用已有 `intl`（数字占位符 `yyyy年M月d日` 不依赖 locale 数据），周几用查表，未新增 pub 包。


## 阶段五·JSON 备份恢复 + ICS 导出新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/utils/backup_codec.dart` | 纯逻辑：`BackupCodec.encode/decode`（备份 JSON 组装与校验，带 version 字段）+ `BackupCodec.restore(db, data)`（单事务清空重建 + 旧→新 id 外键重映射）+ `BackupData`/`RestoreSummary`/`BackupFormatException` |
| `lib/utils/ics_export.dart` | 纯逻辑：`IcsExporter.build()`（学期课表逐周展开为独立 VEVENT，CRLF + RFC 5545 TEXT 转义 + floating local time）+ `IcsExportResult`（事件数/跳过数统计） |
| `lib/services/backup_service.dart` | 文件服务：`pickJsonFile`（file_picker 选 JSON）、`readBackup`（读文件 + 内存校验，先校验后动手）、`restore`（走 BackupCodec 单事务）、`saveTextFile`（file_picker saveFile 落盘，返回路径/取消 null） |
| `lib/database/dao.dart` | 新增 `getAllCourses()` / `getAllOverrides()` / `getAllSettings()`（全量备份需跨学期读取全部表） |
| `lib/pages/settings_page.dart` | 新增「数据管理」分区：备份到文件（JSON）/ 从备份恢复（二次确认 + 进度遮罩 + Provider 全量 invalidate + 通知/常驻通知/小组件联动刷新）/ 导出课表（ICS） |
| `test/backup_codec_test.dart` | 10 个用例：encode/decode 往返字段保留、版本号存在、非 JSON/版本过新/缺学期/外键悬空中文报错、isCurrent 归一与回退、ffi 内存库 restore（清空旧数据/外键重映射/设置覆盖/isCurrent 唯一） |
| `test/ics_export_test.dart` | 9 个用例：逐周展开计数、DTSTART/DTEND 具体日期时刻、TEXT 转义（分号/逗号/换行）、无教室无 LOCATION、单双周过滤、CRLF 无裸 LF、头尾结构、节次缺失跳过计数 |

## 阶段五·JSON 备份恢复设计决策（2026-10-15）

- **备份格式**：顶层 `{app, version, exportedAt, semesters, timeSlots, courses, courseOverrides, appSettings}`，字段名直接复用各模型 `toMap()`（与数据库行一一对应），不引入第二套字段名，也不照搬 SchedU 等外部项目的字段。`version=1`：导入比当前 App 更新的版本直接拒绝并提示升级 App，旧版本未来写兼容分支。
- **三条恢复铁律**：①「先校验后动手」——decode 全程内存校验，任何格式问题在用户确认覆盖之前抛 `BackupFormatException`（中文信息），数据库零接触；②「单事务原子恢复」——restore 在一个事务里清空五张表再重灌，任一步失败整体回滚，不会出现「删一半」；③「外键重映射」——恢复后自增 id 必变，课程按 旧 semesterId→新 id、调课按 旧 courseId→新 id 重灌，绝不照抄备份 id。
- **isCurrent 归一**：decode 阶段把 isCurrent 归一为恰好一个（取备份里第一个标记的，一个都没有回退第一个学期），保证恢复后 `currentSemesterProvider` 一定能读到值不报错。
- **app_settings 跟备份走**：恢复含设置（全量语义），完成后设置页对 `themeSettings/reminderSettings/ongoingNoticeSettings/currentSemester/semesters/timeSlots/courses` 七个 Provider 全量 `invalidate`，主题、提醒开关等即时回到备份时的状态；随后 `rescheduleAll/refreshWidgets/refresh` 三联动让通知与小组件基于新数据重排。
- **宽容与严格的边界**：结构错（非数组、字段缺失、外键悬空）一律拒绝；个别数据瑕疵（学期缺 id 自动补、appSettings 结构不对按空处理）宽容放行，报错信息点名第几条。
- **入口与文件名**：设置页「数据管理」分区；备份文件名 `简课表备份_yyyyMMdd_HHmm.json`（时间戳防覆盖旧备份）；导出走 `file_picker` 的 `saveFile`（用户自选保存位置），取消返回 null 静默处理。

## 阶段五·ICS 导出设计决策（2026-10-15）

- **周次展开选「逐周单事件」而非 RRULE**：一个 20 周 × 10 门的学期约 200 个事件，体积可接受；换来实现简单、零歧义，任何日历 App 与本项目 `IcsParser` 都能正确解析。RRULE 的 FREQ=WEEKLY+UNTIL 边界在不同软件下兼容性参差，弃用。
- **floating local time**（`YYYYMMDDTHHMMSS`，无 Z 无 TZID）：课表只关心本地时间，floating 是最不易出错的表示法。DTSTAMP 用 UTC（规范要求）。
- **DTEND 取结束节次的下课时间**（不是开始节的时间）；教师/备注放 DESCRIPTION（`教师：xxx`，与 `IcsParser._extractTeacher` 的启发式互通，导出的文件能被本 App 读回来还原老师字段）。
- **TEXT 转义**按 RFC 5545（`\` `;` `,` 换行），先转义反斜杠；`X-WR-CALNAME` 放学期名（事实标准，多数 App 用作导入后的日历名）；不做 75 字节行折叠（主流均接受长行，已知取舍）。
- **节次缺失兜底**：引用了不存在节次号的课程无法给出时刻，跳过并在 SnackBar 提示跳过次数，不中断整体导出。
- **文件名**：`简课表_<学期名>_课表.ics`，学期名过滤 `\ / : * ? " < > |` 非法字符。


## 阶段五·深色模式深度适配新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/providers/providers.dart` | 新增 `ThemeSettingsNotifier`/`themeSettingsProvider`（三档主题持久化 app_settings `theme_mode`，读库异常兜底回 system） |
| `lib/main.dart` | `SimpleTimetableApp` 改 ConsumerWidget，`themeMode` watch `themeSettingsProvider`（加载完成前按 system 渲染） |
| `lib/pages/settings_page.dart` | 「外观」分区：SegmentedButton 跟随系统/浅色/深色三段选择 |
| `lib/utils/morandi_palette.dart` | 新增 `desaturateForDark(Color, {brightness})`：深色下降饱和（×0.72）降明度（夹紧 [0.18, 0.40]）、浅色原样返回；新增深色文字常量 `darkTextColor`/`darkSubTextColor`/`darkBadgeBackground`/`darkBadgeTextColor` |
| `lib/widgets/course_card.dart` | 深色下降饱和底色 + 浅色文字；角标/备注圆点深色下反色为浅块深字 |
| `lib/pages/course_edit_page.dart` | 色板圆点深色下展示降饱和后实际效果（所见即所得），勾选图标随亮度取色 |
| `lib/services/notification_service.dart` | 通知小图标 `@mipmap/ic_launcher` → `@drawable/ic_stat_course`（纯白剪影） |
| `android/.../OngoingCourseService.kt` | `setSmallIcon(applicationInfo.icon)` → `R.drawable.ic_stat_course` |
| `android/res/drawable/ic_stat_course.xml` | 新增：24dp 纯白日历剪影（状态栏单色 silhouette，深浅色通知栏都清晰） |
| `android/res/layout/course_widget.xml` | 硬编码 textColor 改 `@color/widget_title_color`/`@color/widget_line_color` 引用 |
| `android/res/values/colors.xml` | 新增：小组件浅色文字色（#1A1A1A / #444444） |
| `android/res/values-night/colors.xml` | 新增：小组件深色文字色（#EAE6E0 / #B8B4AE） |
| `android/res/drawable-night/course_widget_background.xml` | 新增：深色小组件背景 #2B2B2B 圆角 16dp（drawable-night 限定符自动切换） |
| `test/morandi_palette_test.dart` | 新增 8 个用例：浅色原样返回、深色饱和度/明度降低且色相不变、明度区间夹紧、纯白/近黑极端输入 |

## 阶段五·深色模式设计决策（2026-10-15）

- **三档主题**：「跟随系统/浅色/深色」存 `app_settings.theme_mode` 字符串，`ThemeSettingsNotifier` 仿 `ReminderSettingsNotifier`；`MaterialApp.themeMode` watch 该 provider，切换即时生效、重启保持。provider 首帧加载前按 system 渲染（读库毫秒级，闪烁不可感知）。
- **降饱和算法**：`desaturateForDark` 在 HSV 空间做两件事——饱和度 ×0.72（莫兰迪本就低饱和，只温和收敛保色相辨识）、明度压进 [0.18, 0.40]（上限防刺眼、下限防黑底看不见格子）。函数带 `brightness` 参数，浅色原样返回调用方无需判断模式，也让单测可直接断言「浅色原样返回」。色相不动，深浅两套界面上同一门课仍是同一色系。
- **文字对比度**：深色卡片配固定浅暖灰文字（`darkTextColor` 0xFFE8E4DE / `darkSubTextColor` 0xFFBDB9B2），不依赖动态对比度计算——莫兰迪降饱和后明度已被夹紧在固定区间，固定浅字对比度恒定可控。
- **角标反色**：深色下「+N」角标与备注圆点从深块白字反转为浅块深字，在降饱和深底上更醒目。
- **色板所见即所得**：课程编辑页色板圆点深色下直接展示降饱和后的效果，用户选色即所见（避免「选浅色上深卡片」的认知偏差）。
- **小组件深色走 Android 资源限定符**：`values-night` 颜色 + `drawable-night` 背景，RemoteViews 重 inflate 时系统自动选用，无需在 Kotlin 里判断 `isNightMode`，不引入任何新依赖。
- **通知小图标**：状态栏图标必须是单色 silhouette，彩色 mipmap 图标会被压成白块。新建 `ic_stat_course.xml` 纯白日历剪影，flutter_local_notifications 初始化与常驻通知前台 Service 两处同步替换。
- **全页面语义色核查结论**：settings/course_detail_sheet/week_picker/import/import_review/time_settings/semester_manage/week_view 各页原实现已用 `colorScheme.*` 语义色，无需改动；仅 course_card（硬编码文字色 + Colors.white 角标字）与 course_edit（色板勾选图标）存在硬编码，已修复。

## 阶段五·视觉打磨新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/ui/app_styles.dart`（新建） | 全局视觉常量：`AppRadii`（卡片 card=12 / 弹层 sheet=16 / chip 级元素 chip=8 / 启动页 Logo logo=24）+ `AppSpacing`（xs=4 / s=8 / m=12 / l=16），私有构造禁止实例化 |
| `lib/widgets/empty_state.dart`（新建） | 统一空状态组件 `EmptyState`：圆形浅底图标（88px 圆 + 40px *_outlined 图标）+ 主文案 + 可选补充说明 + 可选 tonal 操作按钮，居中布局，全部走 colorScheme 语义色 |
| `lib/pages/splash_page.dart`（新建） | 纯 Dart 启动页：品牌 Logo（primaryContainer 圆角色块 + 日历图标）+ 应用名 + slogan，900ms 淡入停留后 `pushReplacementNamed('/')`；首帧后再淡入防跳变，底部细进度圈示意正在进入 |
| `lib/main.dart` | `initialRoute: '/splash'` 接入启动页（SplashPage → '/' 主页），业务逻辑零改动 |
| `lib/widgets/course_card.dart` 等 12 个页面/组件 | 统一卡片圆角 12px、间距 8/12/16 改走 AppRadii/AppSpacing 常量；各列表空状态替换为 EmptyState 中文占位；残留硬编码颜色改 colorScheme 语义色。涉及：course_card、course_detail_sheet、week_picker、week_view_page、course_edit_page、course_override_page、import_page、import_review_page、settings_page、semester_manage_page、exam_countdown_page |

**业务逻辑零改动、无新增 pub 依赖**；本轮纯视觉层调整。

## 阶段五·视觉规范用法约束（2026-10-15 起，后续新增页面必须遵守）

- **圆角一律从 `AppRadii` 取**（lib/ui/app_styles.dart）：列表卡片/课程格子/图标底座用 `AppRadii.card`（12），BottomSheet 顶部用 `AppRadii.sheet`（16），周次跳转块/快捷按钮等 chip 级元素用 `AppRadii.chip`（8），大块 Logo 用 `AppRadii.logo`（24）。不在页面里写 `BorderRadius.circular(魔法数)`。
- **间距只允许 8/12/16 三档**（`AppSpacing.s/m/l`），微调场景可用 4/24（`AppSpacing.xs`）；同组元素之间 s、卡片间距/分组条目之间 m、页面左右留白/分组之间 l。不在布局里裸写 `SizedBox(height: 10)` 这类档外数值。
- **空状态必须用 `EmptyState`**（lib/widgets/empty_state.dart）：图标推荐 `*_outlined` 线性风格；`title` 必填一句话中文主文案（如「还没有设置考试日期」），`message` 可选补充解决思路，`actionLabel+onAction` 可选放引导按钮（如「新建学期」）。任何列表/网格无数据时不允许白屏或裸 `Text`。
- **颜色一律 `colorScheme` 语义色**：不新增硬编码 `Color(0x...)` / `Colors.white`；课程色仍走 `MorandiPalette`（深色经 `desaturateForDark`，见深色模式专节），不属于本次常量体系。
- **启动页**：`SplashPage` 停留 900ms（`_durationMs` 一处常量）后 `pushReplacementNamed('/')`，返回键不会退回启动页；不依赖任何原生启动主题/资源插件，底色走 Scaffold surface，深色模式无白色闪屏。启动耗时兜底：通知初始化与 Provider 首帧读库都发生在启动瞬间， Splash 同时兜住读库白屏窗口。


## 阶段四待办注意事项

- **学期切换时的刷新入口（通知/小组件/常驻通知栏会话必读）**：全 App 切换激活学期的唯一入口是 `SemestersNotifier.switchTo(semesterId)`（lib/providers/providers.dart）。它依次做四件事，后续功能必须挂在对应环节：
  1. `Dao.instance.setCurrentSemester(id)` — 事务内清零所有 isCurrent 再激活目标（保证唯一）；
  2. `currentSemesterProvider.notifier.setDirectly(新学期)` — 下游 `coursesProvider`（watch 其 future）、`todayWeekProvider`（watch 其 value）自动重建，**课程列表、周次计算无需手动刷新**；
  3. `displayWeekProvider.goToday()` — 周视图浏览周重置为新学期「本周」；`WeekViewPage` 里另有 `ref.listen(currentSemesterProvider)` 把 PageController 跳到新学期本周（clamp 防越界）。
  4. **未实现功能的挂点**：上课提醒重排（重算未来 N 天的提醒计划）、桌面小组件数据重新推送、今日课程常驻通知内容刷新，都应加在 switchTo 末尾（goToday 之后），或在各自 Notifier/Service 里 watch `currentSemesterProvider` 自行联动。
- **小组件与常驻通知智能预告**：常驻通知栏已按 **B 决策**实现（2026-10-15）：只要今天还有「未下课」的课程就继续显示「今日剩余课程」，哪怕已过 20:00；仅当今日所有课程均已下课（或今日无课）才切换为「明日课程预告（共 X 节）」。桌面小组件后续沿用同一 `buildOngoingNotice` 纯函数即可。注意跨学期/假期无课时的兜底文案（明日无课 →「明天暂无课程」）。
- **多学期与节次时间**：time_slots 表全学期共用一套（建表时已决定不按学期拆分）；新建学期不复制节次时间，切换后沿用。

## 阶段四·上课本地通知提醒设计决策（2026-10-15）

- **通知渠道**：`course_reminder_channel`（高优先级，中文名「课程提醒」）；后续「今日课程常驻通知栏」另建 `ongoing_course_channel`，勿混用。
- **权限**：`POST_NOTIFICATIONS`（Android 13+ 动态申请，被拒 SnackBar 提示）、`SCHEDULE_EXACT_ALARM`（`canScheduleExactNotifications()` 动态检查，无权限降级 `inexactAllowWhileIdle` 并弹对话框引导去系统设置）、`RECEIVE_BOOT_COMPLETED`（BootReceiver）。
- **「每日重排」落地为「滚动窗口」**：flutter_local_notifications 无「通知触发即回调」能力，无法做真正的 0 点后台重排；故 `rescheduleAll()` 一次性排「今天 + 未来 6 天」的精确闹钟（exactAllowWhileIdle）+ 次日 0 点自举标记（低优先级静音），App 启动/切学期/增删改课程/改设置时重排。重启后由插件内置 `ScheduledNotificationBootReceiver` 恢复已排通知，本项目 `BootReceiver` 仅做日志第二道保险（见 DEV_STATE 待真机验证）。
- **刷新挂点**：`SemestersNotifier.switchTo` 末尾、`CoursesNotifier.addCourse/updateCourse/deleteCourse` 末尾均 `unawaited(NotificationService.instance.rescheduleAll())`；`ReminderSettingsNotifier.setEnabled/setAdvanceMinutes` 持久化后同样触发。
- **纯逻辑可测**：提醒时刻/当日课程筛选/文案构建全部在 `lib/utils/reminder_plan.dart`（纯函数，不依赖插件），单测不碰平台通道。

## 阶段四·上课本地通知提醒新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/utils/reminder_plan.dart` | 纯逻辑：`computeReminderTime`（上课-提前分钟）、`buildDailyReminderPlan`（按星期/周次/单双周筛选当日课程并算提醒时刻）、`buildReminderBody`（有/无教室文案） |
| `lib/services/notification_service.dart` | 提醒服务：初始化（时区+插件+渠道）、`ensureNotificationPermission`/`canScheduleExact`/`requestExactAlarmPermission`、`rescheduleAll`（滚动窗口重排+次日0点自举） |
| `lib/database/db_helper.dart` | `app_settings` 表（v2）+ `onUpgrade` 补建 |
| `lib/database/dao.dart` | `getSetting/setSetting/getSettingBool/getSettingInt` |
| `lib/providers/providers.dart` | `ReminderSettingsNotifier`/`reminderSettingsProvider`；switchTo/addCourse/updateCourse/deleteCourse 挂重排 |
| `lib/pages/settings_page.dart` | 「上课提醒」开关（含权限申请/精确闹钟引导）+「提前提醒」5/10/15/30 选择 |
| `lib/main.dart` | main 改 async 初始化通知；HomeShell.initState 启动重排 |
| `android/app/src/main/AndroidManifest.xml` | 三权限 + `BootReceiver` 注册 |
| `android/app/src/main/kotlin/com/example/simple_timetable/BootReceiver.kt` | 开机自启接收器（日志占位，第二道保险） |
| `test/reminder_plan_test.dart` | 11 个用例：提醒时刻/文案/当日筛选 |

## 阶段四·今日课程常驻通知栏新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/utils/ongoing_notice.dart` | 纯逻辑：`OngoingNotice`（标题+行文案）+ `buildOngoingNotice`（B 决策：今日有未下课课程显示今日剩余，全部下课才切明日预告；行格式「08:00-08:45 高等数学 A101」无教室省略；明日无课兜底「明天暂无课程」） |
| `lib/services/ongoing_notice_service.dart` | 常驻通知服务：MethodChannel `com.example.simple_timetable/ongoing_course` 原子下发 update/stop；`refresh()` 读 `ongoing_enabled`（默认开）→ 读学期/课程/节次 → 下发；`stop()` 清通知停服务；全 try/catch 中文日志不闪退 |
| `lib/providers/providers.dart` | `OngoingNoticeSettingsNotifier`/`ongoingNoticeSettingsProvider`（开关持久化，关闭即 stop）；switchTo/addCourse/updateCourse/deleteCourse 末尾挂 `refresh()` |
| `lib/pages/settings_page.dart` | 「上课提醒」旁新增「今日课程常驻通知」开关 |
| `lib/main.dart` | `HomeShell.initState` 调 `OngoingNoticeService.instance.refresh()` |
| `android/app/src/main/kotlin/.../OngoingCourseService.kt` | 前台 Service 哑渲染：InboxStyle 可折叠、startForeground（Android 14+ 显式传 specialUse 类型）、渠道 `ongoing_course_channel` 中文名「今日课程」IMPORTANCE_LOW |
| `android/app/src/main/kotlin/.../MainActivity.kt` | `configureFlutterEngine` 注册 MethodChannel，update/stop 转发前台 Service |
| `android/app/src/main/AndroidManifest.xml` | `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` 权限；service 注册 `foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` |
| `test/ongoing_notice_test.dart` | 5 个用例：今日剩余/20:30 切明日（B 决策）/已过 20:00 仍今日/无教室省略/明日无课兜底 |

## 阶段四·今日课程常驻通知栏设计决策（2026-10-15）

- **不新增 pubspec 依赖**：MethodChannel 来自 Flutter SDK 内置 `flutter/services`；Android 原生仅用 `androidx.core`（NotificationCompat / ContextCompat），Flutter 模板与 flutter_local_notifications 已传递引入，无需写任何新依赖。
- **三层架构（借鉴 csust-course-schedule，MIT）**：纯逻辑（ongoing_notice.dart，可单测）→ 服务（ongoing_notice_service.dart，读库 + 通道）→ 原生（OngoingCourseService.kt，真正渲染）。三层职责清晰，纯逻辑不碰平台通道。
- **前台服务类型 specialUse**：常驻通知属「用户可感知、非典型前台服务」，Android 14+ 要求声明 `FOREGROUND_SERVICE_SPECIAL_USE` 权限 + `foregroundServiceType="specialUse"` + `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE">`；`startForeground` 在 API 34+ 需用三参重载显式传 `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE`。
- **B 决策（20:00 规则）**：只要今天还有「未下课」的课程（当前时间早于下课时间）就显示「今日剩余课程」，哪怕已过 20:00；仅当今日所有课程均下课（或今日无课）才切「明日课程预告」。对应单测「今日课程 16:00 前全部结束、20:30 时切明日」。
- **开关关闭即清通知停服务**：`OngoingNoticeSettingsNotifier.setEnabled(false)` → `OngoingNoticeService.stop()` → MethodChannel `stop` → 前台 Service 停服务并移除通知。
- **「剩余」判定按下课时间**：`now.isBefore(结束时间)` 才计入剩余；节次时间缺失的课程跳过（无法判断下课）。

## 阶段四·桌面小组件新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `pubspec.yaml` | 新增依赖 `home_widget: ^0.10.0`（本次唯一新依赖；版本参考 UntisPlus / csust-course-schedule 均在用 0.10.0） |
| `lib/services/widget_service.dart` | `WidgetService.refreshWidgets()`：读当前学期/课程/节次 → 复用 `buildOngoingNotice` 出标题+行列表 → `HomeWidget.saveWidgetData<String>` 下发 `widget_title` / `widget_lines`(JSON) → `HomeWidget.updateWidget(name, qualifiedAndroidName)` 触发原生刷新；全 try/catch 中文日志不闪退 |
| `lib/providers/providers.dart` | switchTo / addCourse / updateCourse / deleteCourse 末尾挂 `unawaited(WidgetService.instance.refreshWidgets())` |
| `lib/main.dart` | `HomeShell.initState` 调 `WidgetService.instance.refreshWidgets()` |
| `lib/pages/settings_page.dart` | 「桌面小组件」分区：一句说明引导用户去桌面长按添加 |
| `android/app/src/main/kotlin/com/example/simple_timetable/CourseWidgetProvider.kt` | 继承 home_widget 的 `HomeWidgetProvider`，重写 `onUpdate(context, manager, ids, data: SharedPreferences)`；从 data 读 widget_title/widget_lines，RemoteViews 渲染标题+最多 3 行（超出显示「…等 X 节」），点击 PendingIntent 唤起 MainActivity |
| `android/app/src/main/res/layout/course_widget.xml` | 4×2 布局：标题 + 3 行课程文案（TextView 预置 3 行，未用到的隐藏） |
| `android/app/src/main/res/xml/course_widget_info.xml` | appwidget-provider：minWidth=250dp / minHeight=110dp、updatePeriodMillis=0（不靠系统轮询）、widgetCategory=home_screen |
| `android/app/src/main/res/drawable/course_widget_background.xml` | 小组件圆角背景（浅色，深色适配留阶段五） |
| `android/app/src/main/AndroidManifest.xml` | 注册 receiver（APPWIDGET_UPDATE + `android.appwidget.provider` meta-data） |

## 阶段四·桌面小组件设计决策（2026-10-15）

- **插件与模型**：用 `home_widget`（非 Glance、非自读 Flutter DB）。模型：Dart `saveWidgetData` 写入其专用 SharedPreferences → 原生 `HomeWidgetProvider` 的 `onUpdate` 第 4 参 `data: SharedPreferences` 直接读到 → RemoteViews 渲染；`updateWidget` 从 Dart 触发刷新。版本 `^0.10.0`（与 Flutter 3.47/Dart 3.13 兼容性待 pub get 验证）。
- **继承 `HomeWidgetProvider` 而非裸 `AppWidgetProvider`**：home_widget 0.10.x 推荐继承 `es.antonborri.home_widget.HomeWidgetProvider`，它把 data 注入 onUpdate 第 4 参，免手动 `HomeWidgetPlugin.getData(context)`。本类只做哑渲染，不碰任何计算逻辑。
- **复用 `buildOngoingNotice`（B 决策）**：小组件与常驻通知栏共用同一纯函数，标题即「今日剩余课程（共 X 节）/ 明日课程预告（共 X 节）」，行即「08:00-08:45 高等数学 A101」；不写第二套判断。
- **`updatePeriodMillis=0`**：不靠系统周期轮询，刷新完全由 App 数据变化时 `updateWidget` 推送。代价：App 长时间不打开（跨天）小组件文案停留旧值，需下次打开才刷新（与常驻通知栏同一已知限制）。
- **行数截断**：原生最多渲染 3 行（4×2 尺寸有限），超出时最后一行显示「…等 X 节」（X=总节数）；空数据显示「暂无课程」；widget_lines JSON 解析失败/为空都有兜底，不崩溃。
- **点击唤起 App**：`setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(MainActivity))`，FLAG_ACTIVITY_NEW_TASK | CLEAR_TOP 回首页。
- **显示与否由用户决定**：App 侧不做开关，小组件是否添加完全由用户在桌面手动决定；设置页仅放一句说明。
- **深色模式**：小组件背景/文字当前为浅色固定值，深色适配留到阶段五。

## 阶段四·多学期管理新增/改动文件（2026-10-15）

| 文件 | 职责 |
|---|---|
| `lib/pages/semester_manage_page.dart` | 学期管理页：列表（名称/开学日期/总周数/「当前学期」徽标）、新建表单对话框（名称 + 日期选择器自动对齐周一 + 总周数默认 20）、切换/删除二次确认；当前学期隐藏切换与删除入口 |
| `lib/providers/providers.dart` | 新增 `SemestersNotifier`/`semestersProvider`；`CurrentSemesterNotifier` 新增 `setDirectly()` |
| `lib/database/db_helper.dart` | `createSchema()` 公开（测试复用同一套 SQL）；新增 `useDatabaseForTest()` 注入测试库 |
| `lib/pages/settings_page.dart` | 「学期设置」分区新增「学期管理」入口 |
| `lib/main.dart` | 注册 `/semester-manage` 路由 |
| `lib/pages/week_view_page.dart` | `ref.listen(currentSemesterProvider)` 切学期后 PageController 同步跳页 |
| `test/semester_manage_test.dart` | 7 个用例：默认学期存在、切换事务 isCurrent 唯一、courses/todayWeek/displayWeek 三联动、级联删除、禁删当前学期、列表刷新 |
| `pubspec.yaml` | dev 依赖新增 `sqflite_common_ffi ^2.3.0`（仅测试用，不违反禁 build_runner 铁律） |

## 阶段三新增文件与职责

| 文件 | 职责 |
|---|---|
| `lib/utils/conflict_detector.dart` | 冲突检测（同星期+重合周次+重合节次），返回冲突详情 |
| `lib/utils/ics_parser.dart` | ICS VEVENT 解析，推算星期/节次/周次 |
| `lib/utils/heuristic_parser.dart` | OCR/PDF 共用的课表文本启发式解析 |
| `lib/services/ocr_service.dart` | google_mlkit 中文 OCR + 启发式解析 |
| `lib/services/pdf_import.dart` | syncfusion PDF 文本提取 + 启发式解析 |
| `lib/widgets/conflict_dialog.dart` | 冲突弹窗（跳过/覆盖/保留两者） |
| `lib/widgets/draft_edit_dialog.dart` | 核对页草稿编辑对话框 |
| `lib/pages/import_page.dart` | 导入入口（ICS/OCR/PDF/教务预留）；导入失败三按钮对话框（复制错误报告/重新选择/返回） |
| `lib/pages/import_review_page.dart` | 人工核对页（草稿增删改 + 冲突检测后入库）；空周次拦截、覆盖延迟删除、同批自冲突、PopScope 防误触 |
| `lib/utils/slot_layout.dart` | 周视图「日×节」三态布局（empty/single/multi，本周优先、非本周淡化、连续同态合并），纯 Dart + 9 个单元测试 |

## 阶段二新增文件与职责

| 文件 | 职责 |
|---|---|
| `lib/utils/morandi_palette.dart` | 莫兰迪色系 16 色课程色板 + 卡片文字色 |
| `lib/utils/week_parser.dart` | 周次文本解析（单双周语义落到 weeks 数组，weekType 恒 0）+ 反向序列化 |
| `lib/widgets/course_card.dart` | 周视图课程卡片（莫兰迪底色圆角，支持置灰） |
| `lib/widgets/course_detail_sheet.dart` | 课程详情 BottomSheet（编辑/删除） |
| `lib/widgets/week_picker.dart` | 周次选择器（网格点选 + 快捷按钮 + 文本解析） |
| `lib/pages/week_view_page.dart` | 网格周视图完整实现（Stack 绝对定位跨节合并） |
| `lib/pages/course_edit_page.dart` | 课程编辑表单（校验 + 莫兰迪色板 + 周次选择器） |
| `lib/pages/time_settings_page.dart` | 作息时间设置（逐节 TimePicker + 一键套用大节） |

## 阶段二 Provider 补充

- `todayWeekProvider`：今天第几周（watch 当前学期，改开学日期自动刷新）
- `displayWeekProvider`：`Notifier<int>` 周视图浏览周次（PageView 联动）
- `showOtherWeeksProvider`：`Notifier<bool>` 显示非本周课程开关
- `coursesProvider.notifier`：新增 `addCourse/updateCourse/deleteCourse`
- `timeSlotsProvider.notifier`：新增 `applyPresetBigSections()`

## 阶段三收尾设计决策（2026-10-15）

- **三态布局**：周视图渲染前先经 `SlotLayout.layoutDay` 做逐节三态解析（empty/single/multi），本周课永远优先同节渲染，非本周课只在无本周课时置灰出现；连续同态节次合并为一段（一段=一张卡片）。同格多课（multi）收敛为最上层一张卡片 + 「+N」角标，点击先弹迷你选课列表。借鉴 SchedU（MIT）思想独立实现，未复制 AGPL 的 OpenWakeUp 代码。
- **分隔带高度守恒**：午休/晚间带不是 overlay，而是参与总高度计算：`_GridArea` 统一算 `rowHeight = (总高 - 带数×20) / 节次数`，时间轴与网格共用行高 + 分隔带占位；卡片纵向偏移 `top = (节次-1)×行高 + 之前带数×20`；空白格点击逐节比对纵向坐标校准（点到带上直接忽略）。
- **周末自适应**：`computeDisplayDays` 按「周末两天有无任何需显示课程」返回 7 列或 5 列；表头、日列、列宽、点击列号全部由该列表驱动。开关 `autoCollapseWeekendProvider` 默认开启。
- **批量导入事务语义**：覆盖的旧课延迟到整批冲突确认且决定导入后统一删除；每插入一门立即回填内存 `existing`（带新 id）供后续草稿检测；空周次草稿阻断导入（SnackBar 点名第 X 门），手动补录默认填满整学期周次。

## 阶段三收尾 Provider 补充

- `autoCollapseWeekendProvider`：`Notifier<bool>` 周末无课自动收起开关，默认 true

## 设计决策记录

- **周次单双周语义**：文本解析与快捷按钮均把单双周过滤落到 weeks 数组（weekType 恒 0），避免全局 weekType 误伤「1-8, 10-16单周」这类混合输入；Course.weekType 字段保留兼容旧数据
- **网格布局**：外层 Stack + 课程卡片绝对定位（left = (dayOfWeek-1)×cellWidth），跨节合并高度 = span×rowHeight；网格线用 CustomPainter；空白格点击区域由外层 GestureDetector.onTapUp 计算行列
- **编辑页路由参数**：int = 编辑指定课程；Map{dayOfWeek, startSection} = 新建并带入格子
