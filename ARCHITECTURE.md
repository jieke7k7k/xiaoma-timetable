# 简课表 · 架构备忘录

> 每完成一个阶段更新本文件，防止上下文丢失。

## 2.1.0 变更（2026-10-26，WB_SPEC_211：Supabase 云同步）

| 文件 | 改动 |
|---|---|
| `lib/services/supabase_sync_service.dart` | 新增 SupabaseSyncService：dart-define 配置初始化（占位符关闭不闪退）、上传（防抖）、下载（水位+冲突取新）、首次迁移去重、exams 镜像维护、离线静默失败；抽象 CloudStore 接口供测试注入 fake |
| `lib/utils/supabase_codec.dart` | 新增纯函数：Course↔courses、Note↔notes、exams 镜像映射；远程 id 规则；冲突取新；水位过滤；日期备注去重 |
| `lib/models/course.dart` | Course 扩展 examEndTime / examPlace，toMap/fromMap/copyWith/withMutableFields 同步 |
| `lib/database/db_helper.dart` | 库版本 4→5；courses 补 examEndTime/examPlace/updatedAt、notes 补 updatedAt（旧数据 null 不丢） |
| `lib/database/dao.dart` | 增改课程/备注自动补 updatedAt；新增 getAllCourseRows/getAllNoteRows/putCourseSynced/putNoteSynced；静态 onLocalChange 钩子（增改触发、删除不触发） |
| `lib/pages/settings_page.dart` | 设置首页顶部新增「云同步」行（上次同步时间 + 立即同步按钮，未配置/失败文案） |
| `lib/main.dart` | 启动挂 DAO 钩子 + 首帧后静默云同步一次；下载改动后失效 Provider 并联动通知/小组件 |
| `pubspec.yaml` | 版本 2.1.0+25；新增 supabase_flutter 依赖 |

### 关键设计决策

- **本地 updatedAt 水位列**：同步协议要求「本地行 updated_at 大于水位」与「冲突取新」，本地库原本没有这列，故 v5 给 courses/notes 补 updatedAt（毫秒），DAO 增改时自动写当前时间；旧数据为 null，只在首次迁移（水位 0）全量上传，之后不参与增量。
- **DAO 钩子解耦**：云同步服务要读 DAO，DAO 又要「变动后触发同步」，直接互相 import 会循环依赖。改由 DAO 暴露静态 `onLocalChange` 钩子，SupabaseSyncService 启动时注册成「防抖同步」，DAO 保持纯数据层；删除不触发（本版删除不同步）。
- **下载覆盖不用 replace**：`putCourseSynced` 先查后 update/insert，刻意不用 `ConflictAlgorithm.replace`——courses 的 course_overrides 外键级联删除，replace 会连带清掉调课记录。
- **纯函数与网络分离**：所有映射/冲突/水位/去重都是 `supabase_codec.dart` 里的纯函数，网络读写抽象成 `CloudStore` 接口，测试注入 fake 断言，不真连 Supabase。
- **exams 镜像只写不读**：App 无独立考试模型（考试挂 Course.examDate），上传时同步 upsert exams 镜像行供小马读写；App 显示以 courses 为准，考试清除时镜像行保留为孤儿（App 不读它）。

## 2.0.9 变更（2026-10-25，WB_SPEC_210：上下栏紧凑 + 网格线跳过休息带）

| 文件 | 改动 |
|---|---|
| `lib/ui/grid_metrics.dart` | `kBottomBarHeight` 72 → 56；新增纯函数 `verticalLineSegments`（竖线按节次分段、跳过休息带，主页与导出图共用） |
| `lib/main.dart` | `theme` / `darkTheme` 增 `appBarTheme`：toolbarHeight 48 + systemOverlayStyle（状态栏透明贴顶、图标按浅/深色可辨）；底栏 `_HomeBottomBar` / `_SideButton` 图标 26→22、文字 11→10、图标与文字间距 2→1 |
| `lib/pages/week_view_page.dart` | `_GridPainter` 竖线改用 `verticalLineSegments` 分段绘制（跳过休息带）、`shouldRepaint` 补 activeBands 比较；`_GridLines` 注释同步 |
| `lib/pages/share_image_page.dart` | 导出图横线改为「每节底边 + 带子底边」（保留节次分隔线，带内无线，与主页一致）；竖线改用 `verticalLineSegments` 分段跳过休息带 |
| `pubspec.yaml` | 版本 2.0.9+24 |
| 测试 | 新增 `grid_metrics_test.dart`（kBottomBarHeight 常量 + verticalLineSegments 纯函数） |

### 关键设计决策

- **栏高全局统一**：顶栏压矮放进全局 `appBarTheme.toolbarHeight`（56→48），所有页面的 AppBar 一起生效，不在某一页单独改高；底栏高度仍走 `kBottomBarHeight` 单点常量，三键图标/文字/间距随底栏一起收紧。
- **贴顶与状态栏同色**：AppBar 默认 `primary: true` 已把背景铺到状态栏后，`appBarTheme.systemOverlayStyle.statusBarColor = transparent` 让状态栏露出 AppBar 同背景色；图标明暗按主题亮度显式指定（浅色深图标 / 深色浅图标），保证可辨。
- **竖线跳带纯函数化**：`verticalLineSegments` 把「整条竖线」切成按节次的纵向分段，休息带（午休/晚间）区间不产生分段即自然跳过；主页 `_GridPainter` 与导出图共用同一函数，从源头避免「主页去线、导出图有线」。
- **横线口径统一**：主页 `_FullWidthLinesPainter` 画「每节底边 + 带子底边」；导出图此前的横线在带子位置把节次分隔线也一并跳过了（与主页不一致），本轮改为同一口径——节次底边（含带子顶边）与带子底边都保留，带子内部无线。

## 2.0.8 变更（2026-10-25，WB_SPEC_209：六件合一——周日弹窗 / 回到本周悬浮按钮 / 设置删聊天 / 左上角只周数 / 编辑锁滑动与空白修复 / 休息时段自定义）

| 文件 | 改动 |
|---|---|
| `lib/ui/grid_metrics.dart` | 新增 `BandSettings`（午休/晚间显隐 + 起止时间，默认开、12:00–14:00 / 17:10–18:00）与纯函数 `bandTimeToMinutes` / `bandRangeValid` / `computeActiveBands`（显隐过滤 + 自定义 interval + 越界过滤） |
| `lib/providers/providers.dart` | 新增 `BandSettingsNotifier` + `bandSettingsProvider`（app_settings 六个键持久化；起止校验不合法不保存返回 false） |
| `lib/pages/week_view_page.dart` | 删周日通栏横幅改 AppDialog 小弹窗（每会话一次）；删顶栏「回到本周」改右缘竖条悬浮按钮 `_BackToWeekRail`（网格区 Stack 内）；左上角删日期范围只留周数；编辑模式锁 PageView（NeverScrollableScrollPhysics）与纵向滚动（`scrollLocked \|\| editMode`）；`_WeekGrid` GestureDetector 改 `HitTestBehavior.opaque`；分隔带改 `computeActiveBands` |
| `lib/pages/share_image_page.dart` | 分隔带改 `computeActiveBands` 与主页同源（隐藏/自定义时间一致） |
| `lib/pages/settings_page.dart` | 删「和智能助手聊聊」行 + `_XiaomaIcon` + 与智能助手设置之间的 Divider，入口 10 → 9 行 |
| `lib/pages/time_settings_page.dart` | 新增「休息时段」卡片：午休/晚间显示开关 + 起止时间选择器（开始早于结束校验，不合法 SnackBar） |
| `pubspec.yaml` | 版本 2.0.8+23 |
| 测试 | `settings_page_test.dart`（9 入口 / 无聊天 / 无 Divider）、`band_settings_test.dart`（默认值 / 纯函数 / Notifier 持久化与校验） |

### 关键设计决策

- **休息时段设置与分段点分离**：分段点（午休/晚间在第几节后，`segmentSettingsProvider`）决定带子位置，`BandSettings` 决定显隐与标注时间——两者正交互不干扰。`computeActiveBands` 作为唯一分隔带计算入口，主页与导出图共用，从源头保证「主页隐藏、导出图还显示」不再发生。
- **自定义时间不再从节次推导**：旧 interval 由前后节次时间算出，用户改了作息就跟着变；现在 interval 直接取用户自定义的起止（默认值与旧版观感一致，老用户升级不突变）。
- **空白格命中根因**：`GestureDetector` 默认 `deferToChild`，Stack 无背景子层时空白处不产生命中；改 `HitTestBehavior.opaque` 后整块可命中，课程卡片仍在 hit test 链上层、配合父级「非空 cell 直接返回」守卫不抢走卡片手势。
- **编辑模式锁滑动的两层**：左右切周锁 PageView、纵向滚动锁 SingleChildScrollView，二者都只在 `editMode` 时切换为 `NeverScrollableScrollPhysics`，退出即恢复原物理；长按拖选仍走既有 `scrollLocked`。
- **周日弹窗一次性状态位**：`_sundayDialogShown` 是页面 State 字段，进程内只置一次，跨周来回切换不再重复弹；与「回到本周」悬浮按钮显隐互不影响。

## 2.0.7 变更（2026-10-25，WB_SPEC_208：设置界面 Taste 重排，只改设置界面、颜色不改黑）

| 文件 | 改动 |
|---|---|
| `lib/ui/app_styles.dart` | `AppSpacing` 新增 `group = 24`（组/节间距共享常量，不影响全局主题与其他页） |
| `lib/pages/settings_page.dart` | 组与组间距统一 24；智能助手组内两行改 1px 分隔线（现有主题 dividerColor）隔开；入口行标题字重 medium。入口行、顺序、副标题、图标、跳转、颜色不动 |
| `lib/pages/settings_sections.dart` | 新增 `_divideRows` 在连续行间插 1px 分隔线（学期 3 行 / 提醒 4 项 / 学期与数据 6 行 / 外观组内两组与尾部四行）；节间距统一 24（`_Header` 上边距 18→24）；节标题改 onSurface + semibold、字号不放大；行标题 medium。控件类型、颜色、逻辑不动 |
| `pubspec.yaml` | 版本 2.0.7+22 |
| 测试 | `settings_page_test.dart`（首页分隔线存在）、`settings_sections_test.dart`（学期与数据子页 6 行 → 5 条分隔线） |

### 关键设计决策

- **只动布局与层级、不动功能与颜色**：Taste 化严格限定在「间距 + 分隔线 + 字重层级」三个维度；主题种子色、卡片色、图标色、开关色、分隔线颜色（用现有主题 dividerColor）全部原样保留，其他界面本版不改。
- **分隔线口径统一**：首页组内用 1px 分隔线、组间用 24 空隙；子页同一节内连续行用 1px 分隔线、节与节用 24 空隙——「组/节内 = 分隔线、组/节间 = 24」，不一处用空隙、一处用分隔线混着来。分隔线一律 `Divider(height: 1, thickness: 1)` 不指定 color（取主题 dividerColor，避免硬编码黑）。
- **节标题不放大**：`_Header` 保持 13 号小字，只把颜色从品牌色 `primary` 改为正文主文字色 `onSurface`、字重从 bold 改 semibold，层次靠颜色与字重区分而非放大字号。

## 2.0.6 变更（2026-10-24，WB_SPEC_206：设置首页去重标题 + 定位容错 + 全部课程清单 + 失败纠错重试）

| 文件 | 改动 |
|---|---|
| `lib/pages/settings_page.dart` | 去掉全部分组小标题（小标题与入口行同名，纯重复），首页只留入口行，组间用 `SizedBox(AppSpacing.l)`、智能助手组内 `SizedBox(AppSpacing.s)` 分隔 |
| `lib/services/command_executor.dart` | 新增共用定位方法 `_locateTargetCourses`：courseId 别名 `courseId`/`id`、courseName 别名 `courseName`/`name`/`course`/`course_name`/`课程名`；courseId 优先，精确匹配同名全改，精确落空按名模糊匹配（互为包含：恰 1 用它 / 多报错列候选 / 0 维持「没有名为」）。add_course 的 `name` 是新课名、不走别名不受影响 |
| `lib/utils/ai_context.dart` | `buildTimetableContext` 加可选 `allCourses` 输出【全部课程（定位用）】节；新增公开 `buildCourseListContext`；提示词补 set_course_remark 两条 JSON 示例与 courseName 原样复制硬规矩；新增 `isParameterFailure` / `shouldRetryForParameterError` / `buildCorrectionPrompt` |
| `lib/pages/ai_chat_page.dart` | `_contextNow` 传 `allCourses`；`_runCommands` 参数类失败自动纠错重试一次（`_retriedThisRound` 硬上限一次，`_autoCorrectCommands` 追加提示行再问模型，纠错回指令照走确认卡片） |
| `pubspec.yaml` | 版本 2.0.6+21 |
| 测试 | `settings_page_test.dart`（同名文字各只出现一次）、`command_executor_test.dart`（别名+模糊匹配）、`ai_context_test.dart`（全部课程清单+示例+纠错判定纯函数） |

### 关键设计决策

- **定位容错收成一个方法**：set_course_color / set_course_remark / add_exam 三处原本各写一遍「courseId 优先、按 courseName 精确匹配、同名全改」，本轮收进 `_locateTargetCourses`。别名只在这三条「定位已有课程」指令里生效——add_course 的 `name` 是新课名、走原 `_addCourse` 不碰别名，避免「给新课取名」被误当「定位课程」。
- **按名模糊匹配是「精确落空后的兜底」**：先精确、再模糊，只有模糊候选恰好 1 个才用，多个列候选、0 个维持原报错——不会因为模糊把「名字写错」静默改到别的课上。
- **全部课程清单只对内置助手开**：`buildTimetableContext` 的 `allCourses` 可选、缺省 null，桥等其他调用方不传也能编译能跑（桥走 `buildSnapshotJson`，与本函数无关）。清单给弱模型一个「可原样复制」的名字来源，配合提示词硬规矩从源头压住「编名字/用简称」。
- **纠错重试硬上限一次**：判定抽成纯函数 `shouldRetryForParameterError`（`alreadyRetried` 为真即不重试），页面只用一个 `_retriedThisRound` 布尔守门——防死循环、防刷接口。桥侧不加这层，因为对端是外部 AI、自己会看 results 纠错。

## 2.0.5 变更（2026-10-24，WB_SPEC_205 第 1/5/6/7 节：设置页 QQ 式分级 + 像素小马 + 预览高亮修复 + 桥 Custom Tab）

本轮只落地第 1/5/6/7 四节，第 2/3/4 节（AI 指令补全 / 历史记录 / 撤回）未动。

| 文件 | 改动 |
|---|---|
| `lib/pages/settings_sections.dart`（新建） | 6 个设置分类子页（学期 / 外观 / 提醒 / 学期与数据 / 权限 / 桌面小组件）；`_AppearanceGroup`、`Preview`（原 `_Preview` 改公开）、`_PreviewGridPainter`、`_FontSection`、`_PermissionSummaryTile` 等组件与全部业务方法从 settings_page.dart 原样搬来 |
| `lib/pages/settings_page.dart` | 重写为纯入口首页：9 个分组标题 + 每类一行入口行（图标 + 名称 + 副标题 + ›），无任何 Switch/Slider；`_SectionHeader`/`_EntryTile`/`_XiaomaIcon` 保留 |
| `lib/main.dart` | 注册 6 条新路由；`_SideButton` 改 `iconBuilder`，智能助手 Tab 换像素小马 PNG（选中玫红/未选灰） |
| `lib/widgets/empty_state.dart` | 新增可选 `iconImage` 参数（非空时优先于 Icon 渲染），供 ai_chat_page 空状态用像素小马 |
| `lib/pages/ai_chat_page.dart` | 两处空状态图标换玫红像素小马 |
| `lib/pages/bridge_page.dart` | `_openInBrowser` 改 `LaunchMode.inAppBrowserView`（Custom Tab 共享登录）；按钮文案 + 三步说明补一句要点 |
| `pubspec.yaml` | 版本 2.0.5+20；assets 声明 `assets/icons/` |
| `test/settings_page_test.dart`（新建） | 首页 9 分类入口 + 无 Switch/Slider |
| `test/settings_sections_test.dart`（新建） | 外观子页预览与主要项存在 + `Preview` 今天列高亮开/关结构断言 |
| `test/bridge_page_test.dart` | 同步按钮文案与新增要点句断言 |

### 关键设计决策

- **QQ 式分级**：设置首页只放分类入口，点进分类才看到该组开关/滑杆；取代 2.0.3 的「外观平铺首页」。迁移是「搬家」——控件与业务逻辑整段复用、不许丢项不许改行为，因此新建 `settings_sections.dart` 承载全部下沉内容。
- **像素小马**：选中玫红/未选灰两版 PNG 颜色已 baked in，渲染用 `Image.asset` 而非 `ImageIcon`（避免 IconTheme 对图片再着色破坏原有玫红/灰）；底栏 `_SideButton` 由 `IconData` 改为 `iconBuilder(Color)`，让图标按选中态换图、文字标签颜色仍同步。
- **预览高亮**：`Preview` 展示「今天起连续三天」，`highlightTodayColumn` 开时给第一列画 `DecoratedBox` 整列边框（主页同款线宽 1.5、圆角 6），覆盖层带公开 Key `kPreviewTodayHighlightKey` 供测试做结构断言。

## 2.0.5 变更（续 · 2026-10-24，WB_SPEC_205 第 2/3/4 节：AI 指令补全 + 历史记录 + 撤回）

| 文件 | 改动 |
|---|---|
| `lib/models/chat_session.dart`（新建） | `ChatMessage`（role/text/time/commands/resolved/results，可 JSON 往返）+ `ChatSession`（title/createdAt/updatedAt/messagesJson） |
| `lib/models/operation_log.dart`（新建） | 操作记录：时间/来源（ai/bridge）/中文摘要/执行前快照 JSON/undone 标记 |
| `lib/models/course.dart` | 新增 `withMutableFields`（给定值原样覆盖 colorValue/note/examDate，null 即清空——补 `copyWith` 用 `??` 清不掉可空字段的缺口） |
| `lib/database/db_helper.dart` | 版本 3→4，onUpgrade 与 createSchema 补建 `chat_sessions`、`operation_log` 两张表 |
| `lib/database/dao.dart` | 会话列/存/删 + 操作记录列/插/标撤回 |
| `lib/services/command_executor.dart` | 新增 `set_course_remark`；`delete_note` 支持 id/date/date+关键词；`execute`/`executeAll` 加 `CommandSource? source`，成功改数据时执行前取快照落操作记录 |
| `lib/services/chat_session_service.dart`（新建） | 对话历史的存/列（倒序）/删 |
| `lib/services/operation_log_service.dart`（新建） | 撤回：按快照还原数据（add_course 删课 / add_note 删备注 / delete_note 加回 / 修改类改回旧值），尽力还原、失败给中文提示、标已撤回；撤回不走执行器防套娃 |
| `lib/utils/command_describe.dart` | 补 `set_course_remark` 描述；`delete_note` 描述支持 id/日期/关键词 |
| `lib/utils/ai_context.dart` | 上下文列全部日期备注（带 id/日期/内容）+ 单列课程备注节；提示词补 set_course_remark 与两类备注默认语义 |
| `lib/pages/ai_chat_page.dart` | AppBar 加历史/新对话入口；`_persistSession`/`_restoreSession`/`_startNewConversation`；执行指令传 `CommandSource.ai` |
| `lib/pages/ai_history_page.dart`（新建） | 路由 `/ai-history`：Tab「对话」（恢复/删除/空状态）+ Tab「操作记录」（撤回按钮） |
| `lib/main.dart` | 注册 `/ai-history` |
| `lib/services/bridge_service.dart` | `_processBatch`/`resolvePending` 传 `CommandSource.bridge` |
| 测试 | `command_executor_test.dart`（set_course_remark + delete_note 扩展）、`ai_context_test.dart`、`chat_session_test.dart`、`ai_history_page_test.dart`、`operation_undo_test.dart` |

### 关键设计决策

- **两类备注**：`courses.note`（课程备注，长期）与 `notes` 表（日期备注，按天）本就两套存储；本轮让上下文与提示词把二者讲清楚，模型才不再把「给课加备注」塞成日期备注。
- **历史持久化选新表而非 app_settings**：要「列全部会话 + 按更新时间倒序 + 单条删除」，一张 `chat_sessions` 表比塞 app_settings 的 JSON 键更直接；消息整段存 messagesJson（量级是「人手聊几句」，拆表 join 是过度设计）。
- **撤回快照在执行器内、执行前取**：新增类记新 id、删除类记被删全文、修改类记旧值，正好落在每个指令实现「读到旧对象」的地方；来源由 `CommandSource` 显式传入，AI 与桥两个调用方都覆盖。撤回走 Dao 直接还原、不再进执行器，天然不套娃。
- **清除语义**：`Course.copyWith` 用 `??` 合并、传 null 清不掉 note/examDate，故新增 `withMutableFields`（给定值原样写）统一处理「清空备注 / 恢复旧值」。

## 2.0.4 变更（2026-10-23，WB_SPEC_204：桥登录改 App 内嵌 WebView 自动填码）

真机实测结论：GitHub 输码页是「每格 maxlength=1」的 8 个单字符输入框，手机浏览器里粘贴整串设备码只进第一个格（剪贴板逐字提交被每格截断），一键粘贴不成立。解法：授权页搬进 App 的 WebView，页面加载完后 JS 逐格自动填码，用户只点 Continue 和授权。

| 文件 | 改动 |
|---|---|
| `lib/pages/bridge_web_login_page.dart`（新建） | WebView 内嵌打开 `verificationUri`（回退 `https://github.com/login/device`）：`JavaScriptMode.unrestricted` + 主流 Chrome Android UA（防 GitHub 推 WebView 降级页）；AppBar「GitHub 授权」带刷新 / 在浏览器打开（url_launcher）/ 左上角关闭；底部小字「授权完成后关闭本页返回，App 会自动完成连接。」；`onPageFinished` 注入自动填码 JS。登录/选账号/输码/授权全在本页走完（cookie 留在 WebView），**不碰令牌** |
| `lib/pages/bridge_page.dart` | 设备码卡主按钮改「在 App 内打开并自动填码」（push `BridgeWebLoginPage`）；原「去 GitHub 粘贴」降次要按钮改名「在浏览器打开（手动输码）」（`_openVerification` → `_openInBrowser`）；三步文案换新流程；2.0.3 自动复制与「复制代码」保留（SnackBar 改「已复制，可作为手动输码备用」）；轮询换令牌逻辑原样 |
| `test/bridge_page_test.dart`（新建） | 桥页按钮存在性/文案：内存库 + `HttpOverrides` 假 GitHub（设备码申请/轮询），断言新主按钮、次要按钮、「复制代码」、大字码与三步新文案存在、旧文案消失 |
| `pubspec.yaml` | 版本 2.0.3+18 → 2.0.4+19（webview_flutter 依赖已有，未动） |

### 自动填码的设计决策（触发条件与防重复填）

- **触发条件**：每次 `onPageFinished`（含授权流程里登录页 → 输码页 → 授权页的每一次整页跳转）都注入一次 JS。JS 只认「可见的、单字符文本输入框」——type 为 text/tel 或无 type、带 maxlength 属性且 <=2、有实际尺寸且未被隐藏——**恰好 8 个才填**；不是 8 个（登录页/选账号页/授权页）直接 `return 'skip'` 什么都不做，等下一次页面加载完再触发。
- **填法**：设备码剔掉连字符（只留字母数字）得 8 字符，逐格用 `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set` 原生 setter 赋值（绕过前端框架包装过的 value 属性），并依次 `dispatchEvent` `input`(bubbles) 与 `change`，保证 GitHub 前端脚本能感知。
- **防重复填（Dart 侧守卫）**：`Set<String> _filledKeys` 记「页面 URL + 设备码」组合，且**只有 JS 回传 `filled`（真的填上 8 格）才记 key**。没填上不记——用户手动刷新后同一 URL 再次加载完还会再试一次；已记 key 的 URL 再次 `onPageFinished` 直接跳过，不覆盖用户的手改。JS 全段 try/catch 回传状态串，Dart 侧 `runJavaScriptReturningResult` 异常也静默吞掉，不影响用户手动输入（WebView 内正常打字有 GitHub 自带的自动跳格）。

## 2.0.2 变更（2026-10-22，WB-202 第二批：第 2、4 项 + 第 3 项补充）

- 设置页 A 方案重组：新增二级页 `lib/pages/course_tools_page.dart`（路由 `/course-tools`，收课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 / 日期备注，路由全部复用）；「高级与数据」拆解——AI 桥入口并入 `lib/pages/ai_settings_page.dart`（与接口地址 / 模型 / Key / 测试对话同页，测试对话在最底部），备份 / 恢复 / 导出 ICS / 数据管理与导入课表、学期管理同组「学期与数据」，权限与关于小马课表上浮一级页各单列一行；`/advanced` 路由与 `lib/pages/advanced_page.dart` 移除（文件留占位说明，提交时 `git rm`）。「界面设置」改名「外观」（`ui_settings_page.dart` 标题同步），上课播报开关从外观页移入设置页「提醒」组。
- 全 App 统一弹窗（长期规范）：新增 `lib/widgets/app_dialog.dart`（`AppDialog` / `showAppInfoDialog` / `showAppConfirmDialog` / `AppInfoIconButton`，圆角取 `AppRadii.dialog`=20，`lib/ui/app_styles.dart` 新增该常量）；长说明（领 Key、桥页顶部说明）改为条目标题旁 ⓘ 信息弹窗；设置区与主页高频确认弹窗（settings / ui_settings / data_manage / week_view）已切该组件，规范条文写进 DEV_STATE.md。
- 冷启动页码修复（WB-202 第 3 项补充）：`lib/pages/week_view_page.dart` 的 PageController 改为学期就绪后首次 build 懒创建，initialPage 取纯函数 `weekViewInitialPage(displayWeek, totalWeeks)`（与 DisplayWeekNotifier 同一套 clampForPage 口径），修掉「标题第 6 周、网格第 1 周」；单测 `test/week_view_initial_page_test.dart`。

## 2.0.1 变更（2026-10-22，真机反馈修复包 P1–P7）

- 设置页分组：低频项（AI 桥 / 权限 / 数据管理 / 关于）收进新二级页 `lib/pages/advanced_page.dart`，路由 `/advanced`（main.dart 注册）；设置页本体重排为学期设置 / 界面设置 / 提醒设置 / 课程与工具 / 备注 / AI 设置（智能助手）/ 高级与数据。
- `UiSettings` 新增字段 `showClassBroadcast`（上课播报，默认关）；`showWeekParity` 语义由「左上角药丸」改为「标题单双周后缀」，默认 `true → false`（`showParityLabel` 字段保留兼容旧数据）。
- 底栏主页按钮 56→48px、课表网格底部留 `kBottomBarHeight`(=72) 内边距（`lib/ui/grid_metrics.dart` 新增常量，main.dart 底栏与 week_view_page 网格共用）。
- AI 桥改 GitHub 设备码登录：`BridgeService` 新增 `githubClientId` 常量与 `requestDeviceCode`/`pollDeviceToken`/`fetchGithubLogin`/`checkMailboxRepo`/`createMailboxRepo`/`saveDeviceLogin`/`disconnect`/`testConnection`；复用既有 `bridge_token`/`bridge_owner`/`bridge_repo` 三个 app_settings 键，无新表结构、无新依赖（url_launcher 已有）。信箱协议 / 同步 / 执行器未动。

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

## 数据表结构（v4，app_settings / notes / chat_sessions / operation_log 走版本升级补建，其余建库时一次性建好，含阶段五预留字段/表）

- **semesters**：`id` PK、`name`、`startDate`(TEXT, ISO yyyy-MM-dd)、`totalWeeks`(默认20)、`isCurrent`(0/1)
- **time_slots**：`section` PK(1~12)、`startTime`、`endTime`（首启内置 12 节默认时间）
- **courses**：`id` PK、`semesterId` FK、`name`、`teacher?`、`classroom?`、`colorValue`(ARGB int)、`dayOfWeek`(1~7)、`startSection`、`endSection`、`weeksJson`(周次数组 JSON)、`weekType`(0全部/1单/2双)、`note?`、`examDate?`(毫秒时间戳，阶段五预留)；索引 `idx_courses_semester(semesterId, dayOfWeek)`
- **course_overrides**（阶段五预留）：`id` PK、`courseId` FK、`originalWeek`、`targetWeek`(-1=停课标记 `CourseOverride.cancelFlag`)、`targetDayOfWeek?`、`targetStartSection?`、`targetEndSection?`、`targetClassroom?`
- **app_settings**（v2 新增，阶段四提醒设置持久化）：`key` PK、`value`；当前键 `reminder_enabled`("1"/"0")、`reminder_advance_minutes`("15")、`ongoing_enabled`("1"/"0")、`theme_mode`("system"/"light"/"dark"，阶段五)、`lunch_after_section`("5")、`dinner_after_section`("9")（阶段六·作息三段化）、`last_error_log`（1.3.1 全局异常日志，只留最近一条「时间 + 摘要」）。`_dbVersion=4`，`onUpgrade` 对 v1 库补建 app_settings、对 v1/v2 库补建 notes、对 v1~v3 库补建 chat_sessions 与 operation_log。1.3.6 新增 AI 桥五键：`bridge_owner` / `bridge_repo` / `bridge_token`（**只存本机，注意"备份到文件"会把它们带上，别外发备份**）/ `processed_command_ids`(JSON 数组，最多 200 条) / `bridge_pending`(JSON 数组，待确认队列) / `last_bridge_sync`（时间 + 摘要文案）。2.0.0 新增内置 AI 三键 `ai_base_url` / `ai_model` / `ai_api_key`（**同样只存本机、同样会被备份带走**）与首次权限引导标记 `permissions_asked_v1`（'1' = 已引导过）。
- **notes**（v3 新增，AI 备注）：`id` PK、`date`(TEXT, yyyy-MM-dd)、`content`、`createdAt`(毫秒时间戳)；索引 `idx_notes_date(date)`。与学期/课程无外键，备注页维护，供常驻通知与桌面小部件按日取用；`onCreate`（新装）与 `onUpgrade(oldVersion<3)`（老用户无感升级）都会建这张表。
- **chat_sessions**（v4 新增，智能助手对话历史）：`id` PK、`title`、`createdAt`(毫秒时间戳)、`updatedAt`(毫秒时间戳)、`messagesJson`(整段消息数组 JSON)。一段对话一行，消息整体存 messagesJson；历史记录页维护。
- **operation_log**（v4 新增，AI / AI 桥操作撤回）：`id` PK、`createdAt`(毫秒时间戳)、`source`("ai"/"bridge")、`summary`、`snapshotJson`(执行前快照 JSON)、`undone`(0/1)。`onUpgrade(oldVersion<4)`（老用户无感升级）与 `onCreate`（新装）都会建这张表。

首启自动创建：默认学期（2026-09-07 开学、20 周、isCurrent=1）+ 12 节默认节次时间。

## 核心 Provider（lib/providers/providers.dart）

- `currentSemesterProvider` — `CurrentSemesterNotifier extends AsyncNotifier<Semester>`：`updateSemester()` 改开学日期/总周数后即时刷新；`reload()` 重新加载；`setDirectly()` 免 Loading 直接写入（切学期专用，防闪烁）
- `semestersProvider` — `SemestersNotifier extends AsyncNotifier<List<Semester>>`：学期列表 + `addSemester()` / `updateSemester()`（编辑，改到当前学期时同步内存 + 三联动）/ `switchTo()` / `deleteSemester()`（删除当前学期抛异常兜底）
- `timeSlotsProvider` — `TimeSlotsNotifier extends AsyncNotifier<List<TimeSlot>>`
- `coursesProvider` — `CoursesNotifier extends AsyncNotifier<List<Course>>`（watch 当前学期，切学期自动联动）
- `reminderSettingsProvider` — `ReminderSettingsNotifier extends AsyncNotifier<ReminderSettings>`：上课提醒开关 + 提前分钟，读写 `app_settings` 表，改动即持久化并触发 `NotificationService.rescheduleAll()`（阶段四）
- `segmentSettingsProvider` — `SegmentSettingsNotifier extends AsyncNotifier<SegmentSettings>`：作息三段化分段点（午休/晚餐在第几节课之后），读写 `app_settings` 表 `lunch_after_section`/`dinner_after_section`，供作息设置页与周视图共用（阶段六）
- `notesProvider` — `NotesNotifier extends AsyncNotifier<List<Note>>`（1.3.5 AI 备注）：全量备注按日期升序；`addNote/updateNote/deleteNote` 末尾联动「备注常驻通知 refreshNoteNotice + 小部件 refreshWidgets」（不重排课程提醒，两者互不影响）

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

## 1.3.1·五项防御性修复（2026-10-22）

| 文件 | 改动 |
|---|---|
| `lib/utils/week_calc.dart` | 新增 `WeekCalc.clampForPage(week, totalWeeks)`：页面定位用周次钳到 [1, totalWeeks]；`totalWeeks<=0`（学期未加载）只保下限 1，保持原行为 |
| `lib/pages/week_view_page.dart` | `initState` 的 `PageController.initialPage` 与 `_goToday()` 都走 `WeekCalc.clampForPage`——`WeekCalc.currentWeek` 语义不变（允许超过总周数），但页码越界会崩 |
| `lib/providers/providers.dart` | `DisplayWeekNotifier` build/setWeek/goToday 一律经 `clampForPage`（新增 `_totalWeeks()` 读当前学期；未加载返回 0 = 不限上限） |
| `lib/pages/course_edit_page.dart` | `_load()` 的 `firstWhere((c) => c.id == _editId)` 改为循环安全查找；找不到时 SnackBar「课程已不存在」+ `Navigator.pop`，不再抛 StateError |
| `lib/main.dart` | `runZonedGuarded` 包住整个启动；`FlutterError.onError` 记录；`ErrorWidget.builder` 换中文兜底界面 `_FriendlyErrorWidget`（自带 Directionality/DefaultTextStyle，不依赖 Theme）；两条路都写 `Dao.setSetting('last_error_log', 时间+摘要)`，写失败吞掉；通知/字体初始化抽到 `_initServices()`，各自 try/catch 不阻断 runApp |
| `lib/models/semester.dart` | 新增 `Semester.startDateParsed`：`DateTime.tryParse(startDate)`，失败回退「今天所在周一」（`WeekCalc.alignToMonday(DateTime.now())`） |
| 11 处 `DateTime.parse(<semester>.startDate)` | 全部换成 `startDateParsed`：providers(todayWeek)、week_view(×2)、next_class、reminder_plan、widget_data、ics_export、share_image_page、free_time_page、import_page(×2)。与学期无关的 `DateTime.parse`（如设置页 `tryParse` 日期串）未动 |
| `lib/database/dao.dart` | 新增 `runInTransaction<T>(action)`；`insertCourse/updateCourse/deleteCourse` 加可选 `DatabaseExecutor? txn`（不传时行为完全不变） |
| `lib/pages/import_review_page.dart` | 落库循环（删旧课 + 插新课）整体包进 `runInTransaction`，返回 (imported/skipped/overwritten)；事务外的 provider reload 与作息校准原样保留 |

## 1.3.1·防御性修复设计决策（2026-10-22）

- **钳制只在「消费端」做，`WeekCalc.currentWeek` 语义不动**：它按设计会返回超过总周数的实际周数（学期结束了还在数），这是正确的教学语义；越界是「拿它当页码」时才成立的，故在周视图与 DisplayWeekNotifier 两处消费端钳制。学期未加载（`totalWeeks = 0`）时不限制上限，避免引入新的首帧抖动。
- **开学日期回退选「今天所在周一」而非固定 2026-09-07**：固定日期在若干年后会算出上千周、在若干年前也让周次远超总周数，页面定位照样越界；回退到本周一恒等于第 1 周，任何周次计算与 PageView 定位都落在合理区间内，是最安全的兜底。
- **兜底界面不依赖 Theme/Material**：出错时祖先未必存在，`Theme.of` 会二次抛错，因此自带 `Directionality` + `DefaultTextStyle`，且只显示中文提示不显示堆栈原文。
- **异常日志写库必须可失败**：`last_error_log` 写入包在 try/catch 里静默吞掉——兜底路径再抛异常会变成二次崩溃，比原错误更糟。只留最近一条（覆盖式写入）。
- **导入事务只包「写」，不包「读 + 弹窗 + 校准」**：冲突预读与清单页在事务之前（纯内存），provider reload 与作息校准在事务之后（副作用/可静默失败），只有删旧课 + 插新课这一段需要原子性，中途失败整体回滚不留半批数据。

## 1.3.2·启动提速（2026-10-22）

| 文件 | 改动 |
|---|---|
| `lib/main.dart` | ① `initialRoute` 由 `'/splash'` 改 `'/'`，删掉 `/splash` 路由与 `SplashPage` 的 import（应用内停留 900ms + 400ms 淡入的人为延迟整体取消）；② `_initServices()` 只留 `FontsService.init()`（防字体闪烁必须留在 runApp 前），新增 `_initNotifications()` 挂在 `runApp` 之后的 `addPostFrameCallback` 里（`unawaited`）；③ `HomeShell.initState` 的提醒重排 / 常驻通知 / 小组件刷新 / QuickActions 注册整体挪进 `addPostFrameCallback`，由 `_runStartupTasks()` 用 `Future.wait` 并发触发，外层再包 try/catch |
| `lib/services/notification_service.dart` | `initialize()` 由「bool 标记幂等」改为「共享 Future 幂等」（`_initFuture ??= _initialize()`），保证首帧后初始化与 `rescheduleAll` 的兜底初始化共用一次、且排期前一定等到真正完成 |
| `lib/pages/week_view_page.dart` | `initState` 的 `_loadChannel()`（公告/更新，读本地状态文件 + `PackageInfo` 平台通道）挪到 `addPostFrameCallback`；`_loadChannel` 内部 5 项读取改为「一次性发起、逐个 await」的并行写法 |
| 未改动 | Android 原生启动主题（`res/values/styles.xml` 的 `LaunchTheme` → `@drawable/launch_background`）保持原样，Flutter 首帧之前一直铺着品牌底图，删启动页不会白闪 |

### 1.3.2·启动提速设计决策（2026-10-22）

- **删的是「应用内停留」，不是「启动画面」**：原生启动窗口背景在进程启动时就画好、一直显示到 Flutter 首帧，本身就是免维护的启动画面；原来多出来的 Dart `SplashPage` 只是在原生背景之上又白等 900ms。删掉它等于把「打开到看见课表」缩短约 1 秒，且深浅色都由原生 drawable 负责，不会白闪。
- **首帧不是空白页**：`'/'` → `_RootGate` 读 `onboarding_done` 期间是 `CircularProgressIndicator`，进 `HomeShell` 后 `WeekViewPage` 在 `currentSemesterProvider` 未就绪时也是加载态（数据到了自动重建成课表），不存在「坏掉的空白页」。
- **runApp 前只留字体**：字体的 family 注册必须在首帧前完成，否则首帧用默认字体、字体到位后再换一次会肉眼可见地跳一次字体；通知（时区库 + 插件通道）与首帧无关，挪走是纯收益。
- **通知初始化改成共享 Future 而非 bool 标记**：挪到首帧后，`rescheduleAll()`（HomeShell 首帧后并发触发）很可能比 `_initNotifications()` 先跑。旧写法 `_initialized = true` 在真正初始化完成前就置位，第二个调用者会立刻返回并拿未就绪的插件去排期（异常被 rescheduleAll 吞掉 → 提醒静默不排）。共享 Future 后，谁先调用谁负责初始化，另一个 await 同一个 Future，语义与「runApp 前串行初始化」等价。
- **并发而非串行**：四项启动联动（重排 / 常驻通知 / 小组件 / 快捷入口）彼此无数据依赖，全部读库或走通道，`Future.wait` 一次性并发；各自内部已有 try/catch，外层再加一层只为兜住 `Future.wait` 自身的错误，行为与之前「三个 unawaited」一致，只是不占首帧。
- **没做的并行化（有意为之）**：`ReminderSettingsNotifier` / `SegmentSettingsNotifier` 的 build 各有 2 次串行单行读库，但那是已开库上的单行查询（亚毫秒级），且这些 provider 之间本身就并发；`DbHelper.database` 的 `_db ??= await _open()` 在启动瞬间会被多个 provider 同时触发（sqflite 默认 `singleInstance: true` 会复用同一实例，不重复建表），改成共享 Future 需在 `resetAllData` 里同步清理，收益小而风险点新，故未动。

## 1.3.3·导入周次推断 + 手动建课冲突检测（2026-10-22）

| 文件 | 改动 |
|---|---|
| `lib/utils/week_infer.dart`（新建） | 纯函数 `WeekInfer.maxWeek(drafts)`（一批草稿里最晚的上课周次，空则返回 0）+ `WeekInfer.inferredTotalWeeks(drafts, totalWeeks)`（不超过总周数返回 null，超过则返回应调整到的周数） |
| `lib/pages/import_review_page.dart` | 顶部新增周次溢出提示条（`_weekOverflowBanner`，仅当推断值 > 目标学期总周数时出现）：文案「导入的课程最晚到第 X 周，超过当前学期的总周数 Y 周」+ 默认勾选的复选框「保存时把总周数调整为 X 周」（状态 `_extendTotalWeeks`，默认 true）；`_importAll` 在课程落库 + `coursesProvider.reload()` 之后按勾选 `Dao.updateSemester` 扩总周数，成功则完成弹窗多一行「《学期名》的总周数已调整为 X 周（原 Y 周）」 |
| `lib/pages/course_edit_page.dart` | `_save()` 落库前新增冲突预检：`_findConflicts(candidate)` 用 `ConflictDetector.detect` 比对 `coursesProvider`（当前学期课程），编辑时传 `ignoreCourseId: _editId` 排除自身；有冲突先弹 `_showConflictDialog`（列出 `CourseConflict.describe()`），「返回修改」直接返回不落库，「仍要保存」才继续 |
| `test/week_infer_test.dart`（新建） | 5 个用例：空草稿/空周次返回 0、多草稿取最大值、单双周不改最晚周次、不超过总周数返回 null、超过时返回推断值 |
| `test/conflict_detector_test.dart` | 新增 2 个用例：手动改课场景（池里含自身，只检出与另一门课的冲突）、周次端点相交算冲突（与导入链路同一语义） |

### 1.3.3·设计决策（2026-10-22）

- **扩总周数放在落库成功之后**：课程已安全入库，这一步失败只 `debugPrint` 静默（与作息校准同一策略），绝不回滚已导入的课程，也不弹「导入失败」误导用户。
- **同步内存状态复用导入页改开学日期的写法**：`Dao.updateSemester` 只改库，Provider 不知道；故目标学期是当前学期时 `currentSemesterProvider.notifier.setDirectly(updated)`（免 AsyncLoading，todayWeekProvider 与周视图的 displayWeek 钳制随即用上新总周数），再 `semestersProvider.notifier.reload()` 刷新学期列表。非当前学期只改库 + 刷列表。
- **推断只看 `weeks` 绝对值、不看 `weekType`**：单双周是在已选周次上再过滤一次，最晚周次不会被它改变；`WeekInfer` 是纯函数，UI 每次 build 重算（草稿被编辑/删除后提示条自动出现或消失）。
- **手动建课复用 `ConflictDetector` 而非另写一套**：与导入链路同一语义（同星期 + 周次有交集 + 节次重叠），候选课的 `weeks`/`weekType` 直接取表单值传给检测器，无需任何换算。冲突池取 `coursesProvider`（恒为当前学期）——新建的课程由 `addCourse` 盖当前学期 id，编辑的课程本就来自这份列表。
- **冲突是警告不是阻断**：保留「仍要保存」出口（同单次调课页的既有口径），因为实际存在同格叠放的正常场景（合班课/保留两者）。

## 1.3.4·提醒窗口拉长 + 自举静音渠道 + 小部件跨天切换（2026-10-22）

| 文件 | 改动 |
|---|---|
| `lib/services/notification_service.dart` | ① `_windowDays` 7 → 30（今天 + 未来 29 天，长假不开 App 也有提醒）；② 新增渠道常量 `kBootstrapChannelId = 'course_bootstrap_silent'` / `kBootstrapChannelName = '课程提醒自举'` 与 `_ensureBootstrapChannel()`（importance=low、不震动、不显角标）；③ `_bootstrapDetails()` 从复用课程提醒渠道改为走这个新渠道（playSound/enableVibration=false、channelShowBadge=false） |
| `lib/utils/widget_data.dart` | 新增纯函数 `widgetDayKey(d)`（yyyy-MM-dd）与 `buildWidgetPayloadDays(...)`（默认 7 天，今天用真实 now、未来某日用该日 00:00 作 now） |
| `lib/services/widget_service.dart` | `refreshWidgets()` 除原 `widget_payload` 外再写 `widget_payload_days`（JSON 对象：日期 → 该日 payload）；原写入 + 回读校验逻辑不变 |
| `android/.../CourseWidgetProvider.kt` | 新增 `resolvePayload(data)`：`onUpdate` 改由它取 payload——先按本地今天日期从 `widget_payload_days` 取、取不到回退 `widget_payload`；全程 `runCatching`，复用原 `parsePayload`。`dbg_widget_*` 自检写入未动 |
| `test/widget_data_test.dart` | 新增 6 个用例：键为今天起 7 天 yyyy-MM-dd、今天那份与 buildWidgetPayload 逐字一致、未来某日 00:00 构建（整天入选 + 顶栏该日）、无课顺延次日、整体可 JSON 编码且字段齐全、无学期时 7 份兜底 |

### 1.3.4·设计决策（2026-10-22）

- **通知 ID 不会撞自举 ID**：`rescheduleAll` 先 `cancelAll` 再从 1 单调递增，上限是「30 天 × 每天节次数」（12 节满课约 360），与 `kBootstrapNotificationId`（0x7FFFFFFF ≈ 21.4 亿）差 6 个数量级，无溢出无重复；Android AlarmManager 活跃闹钟上限约 500，360 仍在安全区。
- **自举通知只能换渠道 id，不能改旧渠道**：Android 8+ 渠道重要性一经创建即由系统固化，通知侧 `importance` 不再生效——原来复用 IMPORTANCE_HIGH 的「课程提醒」渠道，0 点会被真正弹醒。新渠道 id 首次被插件使用时自动创建，`_ensureBootstrapChannel()` 只是让它在初始化时就落地。
- **逐日 payload 由 Dart 端算、原生端只做「按日期取值」**：跨天判断依赖学期/周次/调课等业务逻辑，原生侧不具备；让 Dart 一次算好 7 天，Kotlin 只做一次 `JSONObject` 取值，原生保持哑渲染。
- **今天那份必须与原 `widget_payload` 逐字一致**：逐日表里 offset=0 用真实 `now` 构建（而不是 00:00），保证老逻辑（今天剩余课 / 没课换明天）一比一复刻；只有未来某日才用该日 00:00（让当天课程全部「未结束」而完整入选）。
- **回退优先于报错**：`widget_payload_days` 缺失 / 日期不在范围 / JSON 损坏，一律回退 `widget_payload`；整条解析链 `runCatching`，绝不能让小部件退回黑框错误态（1.2.7 的教训）。
- **日期键用 `Locale.US` 的 SimpleDateFormat**：格式与 Dart `widgetDayKey` 对齐；固定公历避免个别地区佛历/和历导致年份对不上，时区取设备本地与 Dart 本地日期同口径。

## 1.3.5·AI 备注 + 指令执行器（2026-10-22）

| 文件 | 职责 |
|---|---|
| `lib/models/note.dart`（新建） | `Note` 模型（id/date(yyyy-MM-dd)/content/createdAt）+ toMap/fromMap/copyWith |
| `lib/database/db_helper.dart` | `_dbVersion` 2→3；新增 `_createNotesTableSql`；`createSchema` 建 notes 表 + `idx_notes_date`；`onUpgrade` 对 `oldVersion<3` 补建（新装走 onCreate，老库无感升级） |
| `lib/database/dao.dart` | 备注 CRUD：`getAllNotes`（日期升序、同日按 id）/ `getNotesByDate` / `getNotesByDates(List)`（小组件一次取 7 天，空列表直接返回）/ `insertNote` / `updateNote` / `deleteNote`（返回受影响行数） |
| `lib/pages/notes_page.dart`（新建） | 备注页（路由 `/notes`）：按日期倒序分组（标题「今天/明天/yyyy年M月d日 周X」）、新增/编辑对话框（日期选择器 + 内容必填）、删除二次确认、空状态与加载失败走 EmptyState |
| `lib/pages/settings_page.dart` | 「备注」分区新增一行入口（跳 `/notes`） |
| `lib/main.dart` | 注册 `/notes` 路由；注释说明备注常驻通知在 `rescheduleAll` 内部刷新，不在启动任务里另起一项 |
| `lib/utils/note_notice.dart`（新建） | 纯逻辑：`noteDayKey(d)` + `buildNoteNotice({now, notes, maxLines})` → `NoteNotice(title, text)`；今天明天都没有返回 null |
| `lib/services/notification_service.dart` | 新增 `kNoteChannelId='note_ongoing_channel'` / `kNoteChannelName='备注'` / `kNoteNotificationId=0x7FFFFFFE`；`_ensureNoteChannel()`（importance=low、不震动、不显角标）；`refreshNoteNotice()`（无则 cancel、有则 ongoing + BigTextStyle 展示）；`rescheduleAll` 的两条出口（提醒关闭提前返回 / 排完自举）都调用它 |
| `lib/services/widget_service.dart` | `_notesByDateFrom(now, days: 7)` 一次批量读备注并分桶（读失败吞掉按无备注继续），传入 `buildWidgetPayload` 与 `buildWidgetPayloadDays` |
| `lib/utils/widget_data.dart` | `WidgetPayload` 新增可选 `notes`（`toJson` 多一个键，最多 `kWidgetMaxNotes=3`）；`buildWidgetPayload` / `buildWidgetPayloadDays` 新增 `notesByDate` 参数，按**实际展示的那天**取备注；私有 `_widgetNotes` 去空白截断 |
| `android/.../CourseWidgetProvider.kt` | `Payload` 新增 `notes` 字段（默认空列表）、`parseNotes`（MAX_NOTES=3，非数组/缺字段都容错）、`notesText`（MAX_NOTE_LINES=2，首行「备注：」前缀）；`render` 把尾注与备注拼到底部 `widget_footer` 一起显示，未新增任何布局/XML |
| `lib/services/command_executor.dart`（新建） | 地基层：`CommandExecutor.execute/executeAll` + `CommandRegistry`（destructive 集中登记）+ `CommandResult` + 内部 `_CommandError`；一期五条指令 add_course / set_course_color / add_note / delete_note / add_exam |
| `test/note_dao_test.dart`（新建，7 例）、`test/note_notice_test.dart`（新建，8 例）、`test/command_executor_test.dart`（新建，19 例）、`test/widget_data_test.dart`（+4 例） | 沿用仓库测试基建：Dao 类用 sqflite_common_ffi 内存库 + `DbHelper.useDatabaseForTest`，纯逻辑直接断言 |

### 1.3.5·设计决策（2026-10-22）

- **备注用独立表 + 版本号 +1，而不是塞进现有键值表**：备注要「按日期查、按全部排序」，塞 `app_settings` 就得自己维护序列化的顺序与并发覆盖，查询能力也没了。建新表的代价只是一次 `onUpgrade`（`CREATE TABLE IF NOT EXISTS` 级别的单条 SQL），老库数据零改动，属本轮唯一允许的表结构变化。
- **索引打在 date 上**：备注的主查询是「某天/某几天有什么」，几乎不按 id 单独查；`idx_notes_date` 让小组件的 `date IN (...)` 走索引，量级是「手写的备注」无需分表或分区。
- **常驻通知必须紧跟 `rescheduleAll` 的 cancelAll 重建**：`rescheduleAll` 第一步就是 `cancelAll`（清全部已排通知），备注通知会被顺手清掉。因此两条出口都补一次 `refreshNoteNotice()`——否则「开关一下上课提醒」就会把备注通知整没了，看起来像随机 bug。
- **备注通知单独一个渠道 + 一个大 id**：渠道重要性 low 且不响铃不震动（备注是「瞥一眼」的常驻信息，不是打扰），id 取自举 id 减 1（同样在「数亿」量级，远离滚动窗口的 1~几百，不会撞号）。与「今日课程」那条 MethodChannel 前台服务的常驻通知互不影响。
- **跨天仍需打开 App 才刷新**：本地通知没有「触发瞬间回调」，0 点无法唤醒 Dart 重算。备注通知的重建挂在 App 启动时那次 `rescheduleAll` 里，语义等价于 0 点自举那条链路——与常驻通知、桌面小部件是同一条已知限制，没有假装做后台重排。
- **小部件备注跟「实际展示那天」走**：`buildWidgetPayload` 今天没课时会顺延到明天，备注若按「今天」传就会「顶栏是明天、底下是今天的备忘」。故统一在 payload 里按最终选定的 `day` 取备注，与顶栏日期口径一致。
- **小部件不新增布局，只复用 footer**：4×2 的空间有限，改 XML 会动到已有行权重与 1.2.7 修过的兼容性写法。尾注「还有 N 节课」与备注拼在同一个 `widget_footer` 里（备注最多 2 行），老 payload 没有 notes 字段时 `parsePayload` 给默认空列表、渲染与升级前逐字一致。
- **Kotlin 侧零新增 trade-off**：`notes` 数组用 `optJSONArray` + `optString(i, "")`，缺字段/非数组/元素非串统统吞掉返回空列表；整条 `onUpdate → 渲染` 仍在 `runCatching` 里，绝不能因为备注把小部件变回黑框（1.2.7 的教训）。
- **执行器刻意不碰 Riverpod / BuildContext**：它只依赖 Dao，于是可以在单测、后台 isolate、AI 桥里直接跑。**provider 刷新 / 通知重排 / 备注通知刷新 / 小部件刷新一律由调用方负责**（已写进类注释）——副作用留在调用方，批 10 条指令就只刷新一遍，而不是每条各刷三处。
- **destructive 集中在 `CommandRegistry` 登记**：一期只有 `delete_note` 为 true。桥侧将来只认这一个入口决定「要不要弹确认」，不散落 `if (type == 'xxx')`；新增指令忘了登记会被 `execute` 判为不支持，漏登记的成本被显式化。
- **冲突仍是提示不是拦截**：`add_course` 落库前跑 `ConflictDetector`（与手动建课/导入同一语义），冲突只在结果的 message 里写明哪几周哪几节撞了，课程照常入库。AI 侧拿到的「成功但带警告」比「直接拒绝」更可控——用户可能就是想叠放。
- **单条失败不中断整批**：每条指令独立 try/catch，参数错误用内部 `_CommandError` 抛、由 `execute` 兜成失败结果 + 中文原因；`executeAll` 顺序返回结果。批量场景（AI 一次回一串指令）里第 3 条参数写错不该让第 4、5 条石沉大海。
- **`set_course_color` / `add_exam` 的定位限定在当前学期**：课程列表取 `getCoursesBySemester(当前学期)`，重名多门时批量全改——与 App 里「切学期即隔离」的口径一致，避免跨学期误伤同名课程。
- **没有独立 Exam 模型，不要新造**：仓库目前考试的载体就是 `Course.examDate`（毫秒时间戳，课程编辑页与考试倒计时页的数据源，阶段五定下的口径）。因此 `add_exam` 的语义是「给指定课程设置考试日期」（可带 HH:mm，不带则落当天零点），将来若拆独立考试表，改落库目标即可，指令签名不变。
- **停课/调课的现成机制（供下一包接 stop_course）**：已有 `course_overrides` 表 + `CourseOverride` 模型（`targetWeek = CourseOverride.cancelFlag(-1)` 即停课，`targetWeek = originalWeek` 为周内调星期/节次/教室），`Dao.upsertOverride/deleteOverride` 与 `CourseOverridesNotifier` 已是完整链路（含周视图渲染、提醒、常驻通知、小组件四处联动），下一包直接在此基础上加 `stop_course` / `move_course` 指令即可，本轮未新建任何调课机制。

## 1.3.6·AI 桥（App 端同步）（2026-10-22）

上一包落地了 `CommandExecutor`（地基层），本包把它接到 GitHub 私有仓这个「命令信箱」上：**外部 AI 往仓库里放指令文件，App 来拉、执行、写回、上传快照**。App 侧不引任何新依赖（HTTP 复用 `dart:io` 的 HttpClient，与 ChannelService 同款写法），不改任何表结构。

### 仓库内文件布局（**这一段就是给外部 AI 看的对接文档**）

所有 JSON 均为 UTF-8。

| 路径 | 谁写 | 谁读 | 结构 |
|---|---|---|---|
| `commands/<id>.json` | 外部 AI | App | `{id, createdAt, note?, commands:[…CommandExecutor 指令…]}` |
| `results/<id>.json` | App | 外部 AI | `{id, executedAt, status, results:[{index, type, success, message, state}]}` |
| `state/snapshot.json` | App | 外部 AI | `{app, snapshotVersion, generatedAt, semester, courses, notes, exams}` |

- **`<id>` 字符集**：`[A-Za-z0-9][A-Za-z0-9._-]*`（最长 64）。App 会直接拒绝含 `/` 或 `..` 的文件名——id 会被拼进 API 路径去写回，不收紧就会被改写仓库任意路径。
- **`createdAt`**：任意能被 `DateTime.tryParse` 读的值；解析不出来按 0 处理（排最前，先到先处理）。
- **`results[].state`**：`executed`（真执行过，看 `success` 知成败）/ `pending`（破坏指令在等用户确认）/ `rejected`（用户拒了）。
- **`results[].status`**（整批）：`done` / `partial`（有失败或被拒）/ `awaiting_confirm`（还有条在等确认）。优先级：**等确认 > 有失败 > 全成功**。
- **是否重复执行**：App 把处理过的 id 记在 `processed_command_ids`（最近 200 条），写过的批不会再跑第二遍。
- **快照**（每次同步后无条件重传，先 GET 取 sha 再带 sha 更新）：`semester{name,startDate,totalWeeks,todayWeek}`、`courses` 精简字段（`name/teacher?/classroom?/dayOfWeek/startSection/endSection/weeks/weekType/note?/examDate?`，日期为 `yyyy-MM-dd[ HH:mm]`）、`notes` 按日期分组（`{'2026-10-23': ['交作业']}`）、`exams` 单独一份。**快照里只有课表与备注数据，结构上不带任何设置或令牌**。
- **一期指令集**（`CommandRegistry`，`commands[]` 的 `type` 取值）：`add_course` / `set_course_color` / `add_note` / `delete_note` / `add_exam`；只有 `delete_note` 是 destructive（要走 App 内确认）。指令参数见 `lib/services/command_executor.dart` 注释。

一句话流程（外部 AI 视角）：**写 `commands/<id>.json` → 让用户 App 同步一次 → 读 `results/<id>.json` 看成败 → 读 `state/snapshot.json` 回答关于课表的问题**。

### 新增/改动文件

| 文件 | 职责 |
|---|---|
| `lib/utils/bridge_codec.dart`（新建） | 纯函数区：指令批解析（`sanitizeCommandId`/`parseCommandBatch`/`sortByCreatedAt`）、destructive 拆分（`splitByDestructive`）、results 编解码与合并（`BridgeResultEntry`/`statusOfEntries`/`mergeResultEntries`/`buildResultsJson`）、去重裁剪（`keepRecentProcessed`/`parseProcessedIds`）、待确认队列（`BridgePendingItem`/`parsePendingList`/`describePendingCommand`）、配置清理（`BridgeSettings.clean`）、快照组装（`buildSnapshotJson`） |
| `lib/services/bridge_service.dart`（新建） | IO 编排：`syncNow()`（列目录 → 过滤已处理 → 按 createdAt 升序 → 逐批执行 → 写回 results → 上传快照 → 落 `processed_command_ids` 与 `last_bridge_sync`）、`resolvePending()`（确认/拒绝后补写 results 并出队）、Contents API 三件套（`readRemoteFile`/`writeRemoteFile`/内部 `_listCommandFiles`）、配置与队列读写 |
| `lib/pages/bridge_page.dart`（新建，路由 `/bridge`） | 配置区（owner/repo/token，token 遮挡显示 + 眼睛按钮，留空不改令牌）/ 状态区（上次同步摘要 + 立即同步，同步中禁用并转圈）/ 待确认区（`describePendingCommand` 的人话标题 + 执行/拒绝） |
| `lib/pages/settings_page.dart` | 「AI 桥」分区一行入口（跳 `/bridge`） |
| `lib/main.dart` | 注册 `/bridge` 路由；`HomeShell` 改 `ConsumerStatefulWidget`，`_runStartupTasks` 并发列表新增 `_silentBridgeSync()`，`_applyBridgeChanges()` 做桥改数据后的联动 |
| `test/bridge_codec_test.dart`（新建，35 例） | id 安全字符集、指令批解析/兜底/排序、destructive 拆分、状态判定与按 index 合并、去重裁剪、队列往返与人话描述、配置清理、快照字段与「不含 token」隐私断言 |

### 1.3.6·设计决策（2026-10-22）

- **信箱用 Contents API 而不是 Git Data API**：Contents API 的 GET/PUT 自带 base64 与 sha 语义（「PUT 不带 sha = 新建、带 sha = 更新」正是我们要的），一次请求完成读改写；Git Data API 要自己拉 tree/blob/commit 再指向 ref，步骤多且更容易把仓库写坏。代价是每次写会产生一个 commit——对「指令 + 结果 + 快照」这种低频、可追溯的场景反而是优点（仓库历史就是审计日志）。
- **网络层复用 `dart:io` 的 HttpClient，不引 http/dio**：与 `ChannelService` 同一套写法（8~15s 超时 + 静默失败），满足「不新增依赖」这条硬约束。
- **纯函数下沉到 `utils/bridge_codec.dart`**：协议编解码、destructive 拆分、状态判定、合并策略全在里面，不碰网络与数据库——于是这 35 个用例可以在纯 Dart 环境里跑。服务层只负责编排。**destructive 判定只读 `CommandRegistry.destructiveOf`**，不另写一份黑名单，将来新增破坏指令改注册表一处即可。
- **写回 results 一律「先 GET 后 PUT」**：GET 同时拿到 sha（已有文件 PUT 必须带）与旧条目，`mergeResultEntries` 按 index 覆盖后再 PUT。于是「整批首次写回」和「用户事后确认某几条」走的是同一条路径——后者不会把先前写的结果冲掉。
- **破坏指令不自动执行、也不自动丢弃**：它们被装进本地队列（`bridge_pending`，带批 id、下标、指令原文、到达时间与一句人话描述），等人在 BridgePage 点按钮。外部 AI 在 `results` 里看到的是 `awaiting_confirm` + 具体哪几条在排队，用户在 App 里点完之后，那几条的结果会补写回同一个 results 文件。
- **单条/单批失败不中断整轮**：每个文件、每批指令、快照上传各自 try/catch，错误进 `errors` 列表并汇总成一句中文写进 `last_bridge_sync`。信箱里混进一个坏文件不该让后面的指令石沉大海，这是全仓库一致的容错口径。
- **副作留用给调用方**：`BridgeService` 与 `CommandExecutor` 一样不碰 Riverpod/BuildContext，只回一个 `changed` 标记；provider 失效 + 提醒重排 + 常驻通知 + 小部件这四处联动由 `BridgePage._applyBridgeChanges` 与 `HomeShell._applyBridgeChanges` 各自执行（两份同一口径，注释互指）。一批 10 条指令因此只联动刷新一遍。
- **未配置是合法状态**：配置没填全时 `syncNow()` 立即返回 `unconfigured`，不报错、不弹窗——启动时的静默同步天天会走这条路径。
- **令牌安全**：`Authorization: Bearer` 请求头是令牌唯一允许出现的地方；错误摘要只带 HTTP 状态码与异常描述（且截断 120 字），不打印完整 URL。`buildSnapshotJson` 的入参只有学期/课程/备注，结构上不可能带出设置或令牌。**已知边界**：备份 JSON 走 `getAllSettings()`，会包含 `bridge_token`，已在页面底部与本文 keys 说明里写明「别外发备份文件」。
- **已处理 id 只留最近 200 条**：信箱里的批是「处理完就没用」的一次性文件，保留最近 200 条足以覆盖「用户很久没同步、期间 AI 攒了一堆」的场景，不至于让 app_settings 里那行 JSON 无限膨胀。

## 1.3.7·小部件三项修缮（预览图 / 尺寸自适应 / 负一屏复核，2026-10-22）

纯 Android 原生改动，Dart 业务逻辑、payload 契约（仍最多 4 行）与布局结构一律未动。

| 文件 | 改动 |
|---|---|
| `android/.../res/xml/course_widget_info.xml` | 新增 `android:previewImage="@drawable/widget_preview"`；`previewLayout`、`targetCellWidth/Height`、`minWidth/Height`、`resizeMode`、`updatePeriodMillis`、`widgetCategory` 全部原样保留 |
| `android/.../res/drawable-nodpi/widget_preview.png` | 既有 400×300 预览图（仿真实部件绘制），供 HyperOS 走老 `previewImage` 路径的选择器/负一屏列表使用 |
| `android/.../res/layout/course_widget.xml` | **仅顶部注释**加一行「尺寸度量在 `WidgetMetrics` 同步维护」；布局结构、字号、id 零改动 |
| `android/.../CourseWidgetProvider.kt` | ① `onUpdate` 逐实例读 `OPTION_APPWIDGET_MAX_HEIGHT` 并传入 `render`；② `render` 按 `planRows` 只渲染放得下的整行，溢出节数经 `mergeFooter` 并进 footer；③ 新增 `onAppWidgetOptionsChanged` 在尺寸变化后重渲染；④ 新增 `WidgetMetrics`（与布局逐条对齐的 dp 常量）与 `RowPlan` |
| `android/.../AndroidManifest.xml` | **未改动**（负一屏可用性复核通过，见下） |

### 设计决策

- **预览图双轨并存**：AOSP / Android 12+ 的选择器优先用 `previewLayout`（真实布局渲染，最准）；小米 HyperOS 的选择器与负一屏列表走老的 `previewImage`，缺了才回退成应用图标。两个属性同时声明互不冲突，各取所需，不删 `previewLayout`。
- **尺寸度量与布局常量硬对齐**（`WidgetMetrics`）：根 padding 14×2=28dp、顶栏 22dp、单行 36dp（色条固定高，比 15sp+12sp 两行文字更高，取大者）、行间距 12dp（四个行块都带 marginTop）、footer 行高 16dp + 间距 8dp。改 `course_widget.xml` 的这几项必须同步常量，否则会重新出现「最后一行被底边切一半」。
- **裁剪只在原生渲染层做**：Dart 仍按业务口径产出最多 4 行 + 原有 footer，Kotlin 只按当前实例的物理高度决定显示几行；同一份 payload 在 2×2 与 4×4 尺寸下各自裁剪，不需要 Dart 感知尺寸。
- **footer/备注先占位，课程行后填**：备注是用户手写内容，优先级最高（规格要求），所以先从高度预算里扣掉 footer（尾注 + 最多 2 行备注），剩下的除以行块高得到可见行数；溢出的课程行数并进 footer 文案。
- **两个「还有 N 节课」合并**：Dart 的 footer 在总课次 >4 时本来就是「还有 N 节课」，被裁行后若直接追加会变成「还有 2 节课 还有 1 节课」。`mergeFooter` 认出自家格式时把数量相加（N + 被裁行数），其它任意 footer 文案才按「原样 + 空格 + 还有 X 节课」追加。
- **极端缩档保一行课程**：可用内容高度连「1 行 + footer」都放不下时（约 110dp 的最小高度就是这一档），优先显示 1 行课程并隐藏 footer，避免出现「只剩标题 + 还有 N 节课」的空壳；这是唯一让备注让位的分支，已在代码注释写明。
- **options 取不到一律全显**：`maxHeightDp()` 全程 `runCatching`，`OPTION_APPWIDGET_MAX_HEIGHT` 缺失/为 0/实例 id 失效都返回 null，`render` 走升级前的老行为（4 行全显）。整套计算不参与 `RemoteViews` 的必填动作，任何异常都不会产生黑框。
- **`onAppWidgetOptionsChanged` 不硬编码插件偏好名**：该回调拿不到 `HomeWidgetProvider` 注入的 `SharedPreferences`，故发一条显式的 `ACTION_APPWIDGET_UPDATE` 广播回自己，复用与系统刷新完全相同的 `onReceive → onUpdate` 取数链路（也顺带刷新 `dbg_widget_*` 自检记录）。广播在宿主写完新 options 之后发出，读到的就是新尺寸。
- **不改布局、不新增 id**：沿用 `widget_row_1..4` / `widget_footer` / `widget_empty`，只是可见性由「payload 有几行」变成「高度放得下几行」。

### 负一屏（HyperOS 智慧助手）复核结论

- `AndroidManifest.xml` 的 receiver 声明完整且是标准写法：`android:name=".CourseWidgetProvider"`、`android:exported="true"`（宿主在别的进程，必须导出）、`android:label="今日课程"`、`intent-filter` 含 `android.appwidget.action.APPWIDGET_UPDATE`、`meta-data android:name="android.appwidget.provider"` 指向 `@xml/course_widget_info`。
- `course_widget_info.xml` 的 `widgetCategory="home_screen"` 是标准桌面小部件分类，负一屏的「安卓小部件」列表读的就是这套标准 appwidget 元信息；没有任何 `enabled=false`、权限限制或厂商专属字段会把部件排除在外。
- **添加路径**：负一屏 → 添加小部件 → 安卓小部件 → 小马课表（列表里显示名可能是「今日课程」，取决于宿主读 receiver label 还是 app label）。
- 不需要厂商审核或额外声明。HyperOS 的「小米小部件」精品画廊是另一套上架体系（需提交商店/平台审核），自用分发不走那条路，与负一屏可用性无关。

## 1.3.8·学期编辑（当前学期也能改，2026-10-22）

| 文件 | 改动 |
|---|---|
| `lib/widgets/semester_form_dialog.dart` | `showSemesterFormDialog`/`SemesterFormDialog` 新增可选 `initial`（非 null 即编辑模式）：`initState` 回填名称 / 开学日期（`WeekCalc.alignToMonday(initial.startDateParsed)`）/ 总周数；标题「编辑学期」、按钮「保存」；返回 `initial.copyWith(...)` 保留 id 与 isCurrent。校验抽成纯函数 `validateSemesterForm`（名称非空 + 周数 1~30），新建与编辑共用同一套 |
| `lib/providers/providers.dart` | ① `SemestersNotifier.updateSemester(updated)`：改库 → 被改的是当前学期时 `currentSemesterProvider.setDirectly(updated)` → `reload()` → `displayWeekProvider.clampToTotalWeeks()` → `_notifyDataChanged()`；非当前学期只改库 + 刷列表。② 新增库内共享函数 `_notifyDataChanged()`（提醒重排 + 常驻通知 + 小组件三联动），`switchTo` 与 `CourseOverridesNotifier._notifyServices` 改为调用它，杜绝三处散落副本漂移。③ `DisplayWeekNotifier` 新增 `clampToTotalWeeks()` |
| `lib/pages/semester_manage_page.dart` | 每个学期（含当前学期）的菜单都含「编辑学期」；当前学期仍然只有这一项（不给切换/删除）。`_editSemester` 走表单 → `updateSemester` → 中文 SnackBar |
| `test/semester_manage_test.dart` | 新增 2 例：编辑当前学期后内存同步（名称/日期/总周数 + todayWeek=1 + 浏览周 20→8 钳制 + 库与列表同步）、编辑非当前学期（当前学期状态不变、目标学期已改） |
| `test/semester_form_dialog_test.dart`（新建） | 5 例：`validateSemesterForm` 三组边界；编辑模式回填 + 原样保存返回带 id/isCurrent；改名改周数后保存返回更新值 |

### 1.3.8·设计决策

- **编辑入口不区分是否当前学期**：表单、校验、落库路径只有一条，差别只在「改完之后要不要同步内存」。当前学期的菜单只保留「编辑学期」（切换/删除仍是禁区，与既有约束一致）；其它学期菜单是「编辑 / 切换 / 删除」三项。
- **内存同步复用导入页改开学日期的现成写法**：`Dao.updateSemester` 只改库，Provider 不知情，故当前学期走 `setDirectly`（免 AsyncLoading，下游 todayWeekProvider / coursesProvider / 周视图无闪烁重建）+ `semestersProvider.reload()`。非当前学期不参与任何当前数据的计算，只改库 + 刷列表，**不多做一次服务联动**。
- **后处理复用同一份三联动**：把「提醒重排 + 常驻通知 + 小组件」抽成 `_notifyDataChanged()`，与课程增删改、单次调课、切换学期完全同一口径。开学日期/总周数变了会改变未来 30 天的提醒计划与「第几周」文案，所以编辑当前学期必须挂这一处。
- **总周数改小时必须钳浏览周**：`displayWeek` 直接用作 PageView 页码，越界会崩（1.3.1 的教训）。新增 `clampToTotalWeeks()` 只在越界时收敛，不越界不动用户当前浏览的周——不是「回到本周」那种跳页。
- **开学日期确认弹窗只在日期真变了才弹**：编辑常是只改名/改周数，每次都弹「确认开学日期」是噪音；沿用 1.2.1 的防错等级（复用 `showSemesterStartConfirmDialog`），只有归一化后的日期与原值不同才弹。
- **校验抽纯函数而非留在对话框里**：`validateSemesterForm` 不碰 BuildContext，可以在纯 Dart 环境断言「空名 / 0 周 / 31 周 / 非数字」，比 widget 测便宜且稳；对话框本身只做回填与返回。

## 2.0.0·内置 AI 助手 + 界面改版 + 首次权限（2026-10-22）

三件事一起收官：**App 里自带 AI**（不用再靠 GitHub 信箱绕一圈）、**底栏改成三键**、**首次启动把权限一次说清**。无新增依赖（HTTP 仍复用 `dart:io`），无表结构变化（AI 配置与权限标记都走 `app_settings`）。

### 新增/改动文件

| 文件 | 职责 |
|---|---|
| `lib/utils/ai_context.dart`（新建） | 纯函数区：`parseAiReply`（抽 fenced json 指令块并把代码块从正文摘掉）、`buildTimetableContext`（学期/本周课表/临近考试/今明备注）、`buildSystemPrompt`（身份 + 上下文 + 指令协议） |
| `lib/utils/command_describe.dart`（新建） | 指令的**人话描述**唯一实现（五条指令 + 未知兜底），`describeCommand` / `isDestructiveCommand`；AI 桥的 `describePendingCommand` 改为委托它 |
| `lib/services/ai_service.dart`（新建） | OpenAI 兼容 chat/completions 客户端：`AiSettings`（baseUrl/模型/Key）+ `loadSettings/saveSettings/chat` + `extractReplyText`；Key 只进请求头，日志只带状态码 |
| `lib/pages/ai_chat_page.dart`（新建，路由 `/ai-chat`，也是底栏左键） | 消息列表 + 输入框 + 发送中 + 失败重试；未配置的引导空状态（跳 `/ai-settings`）；指令确认卡片（非破坏一键执行、破坏标红逐条「仍要执行」） |
| `lib/pages/ai_settings_page.dart`（新建，路由 `/ai-settings`） | `AiSettingsForm`（接口地址/模型/Key 遮挡，设置页内嵌同一份）+ `AiSettingsTips`（智谱免费领 Key 三步） |
| `lib/services/permission_service.dart`（新建） | 权限收敛：三项状态查询、申请/跳转、首次引导标记 `permissions_asked_v1` |
| `lib/widgets/permission_guide.dart`（新建） | 首次启动三步引导（通知 → 精确闹钟 → 电池优化），每步可跳过 |
| `lib/pages/permission_page.dart`（新建，路由 `/permissions`） | 三项状态（已授权/未授权）+ 补开入口 + 应用详情兜底 |
| `lib/main.dart` | HomeShell 底栏三键（自绘 `_HomeBottomBar`）；默认停在**主页**；首帧后触发权限引导；注册 `/ai-chat`、`/ai-settings`、`/permissions` |
| `lib/pages/week_view_page.dart` | 右上角「新建」（+，原「新建」页签的落地）；左上角单双周小标识（`WeekCalc.parityLabel`，受 `showWeekParity` 控制） |
| `lib/pages/settings_page.dart` | 新增「AI 助手」一组（含三个字段）、「权限」入口行、「课程与工具」（课程搜索/空闲时段/考试倒计时/导出课表图片） |
| `lib/utils/week_calc.dart` | 新增 `parityLabel(week, {totalWeeks})`：未开学或超过总周数返回 null（不显示） |
| `lib/models/ui_settings.dart` / `lib/pages/ui_settings_page.dart` | 新增 `showWeekParity`（默认开） |
| `android/.../MainActivity.kt` | 新增 `device` MethodChannel：查三项权限状态 + 跳通知设置/闹钟和提醒/电池优化/应用详情 |
| `test/ai_context_test.dart`（新建，20 例）、`test/ai_service_test.dart`（新建，8 例）、`test/week_parity_test.dart`（新建，5 例） | 纯函数测试；基线 307 → 340 |

### 设计决策

- **上下文现取不缓存**：每次发送都重新读 `currentSemester/courses/overrides/notes` 组装（经 `effectiveCoursesForWeek` 应用单次调课，与周视图同一口径）。缓存会让「刚让 AI 加了一门课，再问它有什么课」答错，代价只是每次多读几张表。
- **指令块解析放在纯函数里，且只认 `{"commands":[…]}` 的 json 块**：模型讲解格式时常写示例代码块（```dart），按语言标记先过滤；块里没有 commands 字段就原样留在正文。解析出的块一律从正文摘掉——用户看到的是正文 + 确认卡片，不是原始 JSON。
- **执行前必须确认，且描述与 AI 桥同源**：`describeCommand` 是唯一的人话实现（桥的 `describePendingCommand` 改成委托它，行为逐字不变）。破坏性只读 `CommandRegistry.destructiveOf`，不另写黑名单。非破坏指令默认可「一键执行」，破坏指令单独标红、按钮写「仍要执行」并给「忽略」出口。
- **执行力复用 `CommandExecutor`，联动复用调用方那一套**：AI 侧不碰 Riverpod 之外的东西——执行完由聊天页失效 `coursesProvider/notesProvider` 并重排提醒、刷新备注通知、常驻通知、小部件（与 BridgePage / HomeShell 同一口径）。一批指令只联动一遍。
- **AI 配置与令牌口径对齐 AI 桥**：三个键存 `app_settings`；Key 留空表示不改（输入框是遮挡的）；日志/错误摘要只带 HTTP 状态码与截断 120 字的异常描述。**已知边界同桥**：备份 JSON 会带走 Key，设置页里已写明别外发。
- **底栏自绘而非 NavigationBar**：一是中间「主页」要凸起且明显大于两侧，二是 `NavigationDestination` 长按会浮出 label 气泡（用户发过截图明确不要）。自绘按钮常显小字名称、不包任何 Tooltip，长按无反馈。
- **原页签目的地一个不丢**：底栏从「课表/新建/设置」改成「AI/主页/设置」后，「新建」上移到主页右上角（+，内容与原来逐字一致），课表/考试/导入/数据管理/学期管理等照旧在设置页（新增「课程与工具」补齐课程搜索/空闲时段/考试倒计时/导出课表图片）。对照表见 DEV_STATE.md。
- **权限收成一处**：以前通知权限/精确闹钟散落在提醒开关里（开提醒顺带申请、被拒给个 SnackBar）。现在 `PermissionService` 是唯一入口：申请通知仍走插件 API（不重复造），查状态与跳系统页走新增的 `device` 通道，电池优化跳系统白名单页、跳不过去回退应用详情页。
- **首次引导的标记先写再引导**：`permissions_asked_v1` 在引导开始前就落库，因此每一步「跳过」、中途杀 App、或者干脆拒绝，都不会再弹第二次；补开入口长期留在「设置 → 权限」。三项都不是硬门槛——没开只是提醒可能延迟或被省电掐掉，App 照常能用。

## 工具类

- `AiContext`（lib/utils/ai_context.dart）：`parseAiReply`（抽/摘指令块）+ `buildTimetableContext`（课表上下文）+ `buildSystemPrompt`；**20 个单元测试**（test/ai_context_test.dart）
- `CommandDescribe`（lib/utils/command_describe.dart）：`describeCommand` / `isDestructiveCommand`——内置 AI 确认卡片与 AI 桥待确认列表共用的人话描述唯一实现
- `AiService`（lib/services/ai_service.dart）：OpenAI 兼容客户端，`extractReplyText` 等纯函数 **8 个单元测试**（test/ai_service_test.dart）
- `WeekCalc.parityLabel`（lib/utils/week_calc.dart）：单双周小标识文本，学期外返回 null；5 个单元测试（test/week_parity_test.dart）
- `BridgeCodec`（lib/utils/bridge_codec.dart）：AI 桥协议编解码 + destructive 拆分/合并/去重策略；**35 个单元测试**（test/bridge_codec_test.dart）
- `WidgetData`（lib/utils/widget_data.dart）：`buildWidgetPayload` / `widgetDayKey` / `buildWidgetPayloadDays`（跨天逐日表）；**13 个单元测试**（test/widget_data_test.dart，1.3.5 增至 17，新增当日备注一组）
- `NoteNotice`（lib/utils/note_notice.dart）：`buildNoteNotice`（今天/明天分组的多行文案，均无则 null）+ `noteDayKey`；8 个单元测试（test/note_notice_test.dart）
- `WeekInfer`（lib/utils/week_infer.dart）：`maxWeek`(草稿里最晚周次) / `inferredTotalWeeks`(要不要扩学期总周数)；5 个单元测试（test/week_infer_test.dart）
- `WeekCalc`（lib/utils/week_calc.dart）：`alignToMonday` / `currentWeek`(未开学返回0，允许超过总周数) / `clampForPage`(1.3.1 页面定位钳制) / `isOddWeek` / `weekDates` / `weekDatesOf` / `weekTitle`；20 个单元测试全绿（test/week_calc_test.dart）
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
- ~~**启动页**：`SplashPage` 停留 900ms …~~ **已于 1.3.2 移除**（见下方专节）：`initialRoute` 直接是 `'/'`，不再有人为停留；`lib/pages/splash_page.dart` 不再被引用（文件待删）。首屏白屏窗口改由 Android 原生启动窗口背景（LaunchTheme 的 `launch_background`）兜住。


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
| `lib/pages/semester_manage_page.dart` | 学期管理页：列表（名称/开学日期/总周数/「当前学期」徽标）、新建表单对话框（名称 + 日期选择器自动对齐周一 + 总周数默认 20）、**编辑学期（1.3.8：所有学期含当前学期，复用同一套表单与校验）**、切换/删除二次确认；当前学期隐藏切换与删除入口 |
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
