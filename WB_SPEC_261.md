# WB_SPEC_261：全 App 大扫除——文案精简、权限去嵌套、导出同步、图标统一、长按框、搜索框

## 1. 用户原话（2026-11-25）

- 「还有更新日志和使用帮助等里面的文字，言简意赅，正式化语言」
- 「不止这里，整个软件你看看别的地方，语言有没有啰嗦的，都改了」
- 「权限自检打开就一个子项目，进去只能点击这个。搞这么麻烦干嘛」
- 「还有这种不合理的，也检查一下」
- 「右边那个回到本周，长按为啥有个框，不好看」「检查别的地方有没有这种，改了」
- 「课程搜索里面这个搜索框，为啥显示成这样？」「整个软件都检查一下，还有没有这种问题，都改了」
- 「课表工具里面，怎么只能导出本周课表没有整学期的，跟主页那个怎么不同步？」
- 「还有这里的图标风格怎么跟设置页不一样，是你故意设计的吗？」
- 跑马灯已另立 WB_SPEC_260 并落盘，不在本规格内。

## 2. 审计结论（三份报告，均为只读审计、逐项核实到代码）

- 文案：`~/workspace/goals/app/hidden_files/copy_audit_20261125.md`，181 条（lib 171 条 + CHANGELOG.md 10 条代表性改写）。
- 结构：见本旁聊 2026-11-25 结构审计报告（权限、导出、图标）。
- 交互与输入框：见本旁聊 2026-11-25 交互审计报告（长按框、搜索框）。

## 3. 文案精简（181 条 + CHANGELOG 批量）

- 按文案审计报告逐条落盘：原文逐字匹配、改后逐字替换。纯字符串替换走脚本，脚本必须断言每条原文在文件里恰好出现 1 次；出现 0 次或多次的，停下报出来人工处理，不许猜。
- 两处合并且改结构的条目，需读代码后动手，不许只换字符串：
  - `week_view_page.dart:537-538`：『今天是周日』／『今天是周日，本周已结束』两句合并为一句『今日为周日，本周已结束』。
  - `course_edit_page.dart:381-383`、`time_settings_page.dart:166-168`、`import_review_page.dart:1083-1084`：标题问号去掉、正文同步改，见报告。
  - `about_page.dart:119-123`：多行说明整体改写，保留 4 个要点与事实。
- 同步改的重复文案（报告末尾已列）：导入方式 4 条（import_page 与 onboarding_page 两处）、分享文案（week_view_page:3005 与 share_image_page:1477）、备份/恢复副标题 2 条（data_manage_page 与 settings_sections 两处）、『开始节次不能大于结束节次哦』（course_edit_page:366 与 course_override_page:120）。
- CHANGELOG.md：报告所列 10 条按原文改写；其余约 60 条按同一风格批量精简（只改语言、不改事实、不动版本号与日期）；文件中间误放的「# 更新日志」总标题移到文件顶部。
- 不动的：固定叫法「午间」「晚间」「回到本周」；页标题与按钮名；含异常对象的技术提示（如『加载课程失败：$e』）。
- **例外**：`course_tools_page.dart:28` 副标题不按文案报告改（见 §6，导出同步后副标题要反映两种导出方式）。

## 4. 权限去嵌套（方案 A：直接改路由）

- 现状：设置页「权限自检」行（`settings_page.dart:140-146`）→ 路由 `/settings-permissions` → `PermissionsSettingsPage`（`settings_sections.dart:1030-1040`，body 只有一行 `_PermissionSummaryTile`）→ 点进 `/permissions` 的 `PermissionPage`（已平铺三项）。
- 改法（5 处 + 1 处测试）：
  1. `settings_page.dart:145`：`route: '/settings-permissions'` → `route: '/permissions'`。
  2. `main.dart:319`：删除整行 `'/settings-permissions'` 路由。
  3. `settings_sections.dart:1029-1040`：删除 `PermissionsSettingsPage` 类及其注释。
  4. `settings_sections.dart:1131-1205`：删除 `_PermissionSummaryTile` 与 `_PermissionSummaryTileState` 及其注释（删后 `PermissionService` 仍被 :505、:551、:585、:617 使用，import 不动）。
  5. `settings_sections.dart:47`：文件头注释里删掉 `PermissionsSettingsPage` 那一行。
  6. `test/settings_icon_box_test.dart:375-378`：该测试 pump 的是将被删的 `PermissionsSettingsPage`，改写为 pump 设置页、断言「权限自检」行（或删除）。
- 取舍（已定）：中间页的实时摘要（『通知 已授权 · 闹钟 已授权 · 电池 已授权』）随中间页一起拿掉，不做上移。理由：用户抱怨的是嵌套本身；三项授权状态在 `/permissions` 页内一目了然，功能无损失。入口副标题保持静态文字『通知、精确闹钟与电池优化授权状态』。
- 其余单项子页：审计已扫完全仓，没有第二处同类问题（`WidgetSettingsPage` 有 3 项，已排除），本次只修权限页。

## 5. 回到本周长按框

- 成因（已查明）：`_BackToWeekRail`（`week_view_page.dart:1113-1175`）的 `InkWell` 没有 `borderRadius`，按压高亮与水波纹被裁成直角矩形铺满 30dp 竖条；父级 `Material` 只做了左侧圆角且无 `clipBehavior`，方形角盖住竖条左侧圆角，长按手指不抬就一直糊在那里，看着像个框。不是 Tooltip（全仓 `Tooltip(` 计数为 0），不是 SelectionArea，无 onLongPress。
- 改法：给 `InkWell` 加与 `Material` 同款的左侧圆角（`BorderRadius.only(topLeft: Radius.circular(AppRadii.card), bottomLeft: Radius.circular(AppRadii.card))`），水波纹与高亮按竖条形状裁剪，按压反馈保留。
- 不做：`splashColor/highlightColor` 置透明或改 `GestureDetector`（反馈全丢，不采纳）。
- 同类检查结果：全仓 25 处 InkWell、10 处 GestureDetector、76 处 ListTile、25 处 IconButton 已扫完，只有这一处是真问题。次要一处顺手改：`settings_sections.dart:501`（`_exactAlarmHint` 精确闹钟提示行）的 `InkWell` 补 `borderRadius: BorderRadius.circular(8)`（可点区整行宽、内容只占左半截，长按整行空白高亮像空框）。其余整行矩形 InkWell 高亮与形状一致，不用改。24 处 `IconButton` 的 `tooltip:` 是标准 Material 行为、有意为之，不去掉；`week_view_page.dart:836` 的 tooltip 文案按文案报告 §20 改（『添加/修改』→『添加或修改』），不另动。

## 6. 课表工具导出与主页导出同步

- 现状：工具页「导出课表图片」（`course_tools_page.dart:24-35`）onTap 直接 `Navigator.pushNamed(context, '/share-image')`，只导本周；主页 ⋮ 菜单同名项（`week_view_page.dart:443-445`）调顶层函数 `showExportBottomSheet(context, ref)`（`week_view_page.dart:2874`），弹出三行：整学期一张 PNG 分享、整学期 PNG 存相册、当前周 PNG。纠正：没有 PDF 选项，三行全是 PNG。
- 改法（方案 A，最小改动）：`course_tools_page.dart` 加 `flutter_riverpod` 与 `week_view_page.dart` 的 import，类由 `StatelessWidget` 改 `ConsumerWidget`，导出行 onTap 改为 `showExportBottomSheet(context, ref)`。`week_view_page.dart` 没有 import `course_tools_page.dart`，无循环引用。`displayWeekProvider` 是全 App 的，从工具页读到的仍是用户正在浏览的那一周，语义不变。`/share-image` 路由保留（BottomSheet 的周行仍用它）。
- 副标题同步改（取代文案报告 :28 条）：『将整学期或当前周导出为图片』。
- 不做：整学期导出图与单周导出图样式不一致是独立遗留问题（两个渲染器不同源：整学期用 `SemesterSingleImageSheet` 离屏渲染、单周用真实周视图截图），统一它需重构渲染器，另立项，本次只同步入口。
- 图标（同页，见 §7）与导出行改动在同一文件，一并做。

## 7. 课表工具图标统一为设置页风格

- 现状：工具页 6 个入口 leading 全是裸 `Icon(Icons.xxx_outlined)`，无底块、无分类色；设置页全部入口用 `SettingsIconBox`（`lib/ui/settings_icon_box.dart:100`，32×32 圆角方块底 + 20dp 描边图标 + 语义分类色）。不是故意设计，是两套写法没统一。
- 改法：`course_tools_page.dart` 顶部加 `import '../ui/settings_icon_box.dart';`，6 处把 `leading: const Icon(Icons.xxx_outlined)` 改为 `leading: const SettingsIconBox(icon: Icons.xxx_outlined, category: SettingsIconCategory.xxx)`（图标本身不动，只换容器）：
  - 导出课表图片：`schedule` 蓝
  - 考试倒计时：`reminder` 橙
  - 空闲时段：`schedule` 蓝
  - 课程搜索：`system` 灰
  - 日期备注：`reminder` 橙
  - 菜单管理：`appearance` 紫

## 8. 课程搜索框移出 AppBar（与选校器统一）

- 成因（已核实，三条机制叠加）：
  1. 棕色边框：`InputBorder.none` 根本没生效。`InputDecorator` 会对 decoration 里为 null 的字段用 `InputDecorationTheme` 补默认值；该 decoration 只写了 `border`，没写 `enabledBorder / focusedBorder`，于是聚焦态走了主题 `focusedBorder`（CleanGap，`primary` 1.5dp，即截图里的棕色粗边框）。主题五态全给了值，本地 `border` 是死代码，永远不会被用到。`autofocus: true` 让它进页面就常驻聚焦态。文件内 :70-71 的注释（称走不到自画边框）与实际机制不符，随本次改掉。
  2. 框子太高顶满 AppBar：主题 `contentPadding` 上下共 28dp，框高约 52dp，塞进 56dp 的 AppBar 上下几乎贴边。
  3. 提示文字「贴边、像被裁一半」是观感问题（逐像素核对：文字没有被真正裁掉）：无 `prefixIcon`、1.5dp 主色描边紧贴文字、框又高又宽。`filled: true` 与 CleanGap 自画填充叠了双层填充是 latent 问题（同色 token，肉眼不可见），随本次一并去掉。
- 改法（推荐方案，与选校器统一）：把搜索框从 `AppBar.title` 移到 body 顶部，照抄选校器写法（`school_picker_page.dart:264-283`）：AppBar 标题改回纯文字『课程搜索』；body 改为 `Column`，顶 `Padding(16, 12, 16, 8)` + `TextField(prefixIcon: 搜索图标，suffixIcon: 有查询时显示清空按钮，isDense: true)`，边框与内边距全部走主题，不再手写 `border / filled / contentPadding`；下面 `Expanded` 包原有三态 body（空态 / 无结果 / 结果列表）。
- 顺带修一个 latent bug：现行清空按钮（AppBar actions 里）只 `setState(() => _query = '')`，TextField 没有 controller，框里文字清不掉。改后加 `TextEditingController`，清空时 `_controller.clear()` 并同步 `_query`。
- 提示文案按文案报告 §4 改：hint『搜索课名、老师或教室』；无结果提示『请更换关键词，或确认课程属于当前学期』。
- 顺手：`school_picker_page.dart:267-283` 的 `border: OutlineInputBorder(borderRadius: 12)` 同样是死代码（主题五态全覆盖），删掉，不改显示。
- 同类检查结果：全仓 17 处 `TextField / TextFormField` 已扫完，只有课程搜索框一处是同款问题，其余全部走全局主题，正常。

## 9. 测试

- 权限：改写 `test/settings_icon_box_test.dart:375-378`（见 §4 第 6 条）；新增设置页「权限自检」行点按直达 `/permissions` 的 widget 测试。
- 导出同步：新增测试——pump `CourseToolsPage`，点「导出课表图片」，断言弹出 BottomSheet 且含整学期与当前周两行。
- 搜索框：新增测试——pump `CourseSearchPage`，断言搜索框在 body 内、有 prefixIcon、输入后出结果、点清空后框与结果同时清空。
- 回到本周：新增测试——断言 `_BackToWeekRail` 的 `InkWell.borderRadius` 与 `Material` 的左侧圆角一致。
- 全量回归：`flutter test --no-pub` 全部通过；`flutter analyze` 无新增问题。已知 flaky（`school_picker_page_test` 链式进入、`wb231_course_multi_slot_test`，全量负载下时序 flaky，单跑全绿）不是回归。

## 10. 发版

- 版本：预计 2.16.0（跑马灯为新功能，按规矩升中号），发版前定。
- 流程按既定发布管线：提交 → CI → 验包 → Release → 通道 → 云盘备份 → 双推 → 文档同步（需求文档变更记录、本旁聊 MEMORY、主 MEMORY）。
- 复审：打包前换模型只读复审（DeepSeek flash），复查方拿用户原始需求原话；跳过复审须在发版汇报里如实说明。
