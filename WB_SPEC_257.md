# WB_SPEC_257：弹出菜单按钮顺序统一

## §0 目标与依据

- 目标：把全 App 3 个弹出菜单的按钮顺序收敛到同一套排序规则，消除"高频功能埋在中间、同一入口两处重复、行操作主次颠倒"的割裂感。只改顺序与一项删除，不改形态（形态已由 256 统一为 PopupMenuButton + buildAppPopupMenuItem）、不改文案、不改图标、不改路由。
- 依据：用户原话（2026-11-24 14:33，他发右上角 ⋮ 菜单截图）"右上角这种菜单里面的按钮顺序你有注意过吗"，随后补一句"所有的这种菜单"；Neon 提案 `~/workspace/goals/app/hidden_files/neon_257_proposal.md`（2026-11-24 15:01，Gemini 对话 c492651f18ba120c，云端浏览器 cj 号，Neon，低推理强度；他 14:58 明确授权云端登 cj，仅限这次）。
- 本规格以 Neon 提案为底稿，并做以下核对与修正（均已拿代码核对）：
  1. Neon 说"设置页数据备份与换机里已有独立入口"属实：导入课表在 DataSettingsPage（settings_sections.dart:694 起，第一行，ICS / 图片 OCR / PDF 导入），不是 data_manage_page.dart。删 ⋮ 里的导入后，入口还剩 + 菜单、数据备份与换机、桌面长按快捷（main.dart _setupQuickActions 的 shortcut_import）、空学期占位按钮（wb231），共 4 处，不会断入口。
  2. Neon 说"老数据里残留的 id: import 直接静默忽略"属实，且代码里已有，无需写迁移：MenuConfig.fromEncoded（menu_config.dart:185 起）以默认配置为模板合并，未知 id 不在模板里自然被丢弃；MenuConfigNotifier.build（providers.dart:850 起）走 fromEncoded；reset()（providers.dart:919）写 MenuConfig.defaults() 并落库。
  3. Neon 提案 2.1 节"+ 菜单保持现状不动"采纳；但注意 + 菜单的"导入课表"项与 ⋮ 菜单的 import 是两个不同的值命名空间（+ 菜单用 onSelected 的 action 值 'import'，见 week_view_page.dart:352/366；⋮ 菜单用 menu_config 的 id 'import'），删 ⋮ 的 import 不影响 + 菜单。
  4. categoryForMenuId（app_popup_menu.dart:58）里 'import' → 数据绿的映射分支保留不动：+ 菜单的导入项图标色是手写值不走这个函数，但映射表按 id 全量覆盖 7 项，删分支只会让 wb230 的全表单测改口径，无收益。
- 2026-11-24 审阅轮：Neon 审出 1 P0 + 1 P1 + 1 P2，三条均采纳并入 §2/§5/§6（P0 是规格自相矛盾：主页 ⋮ 菜单取 homeMenuItems、不含「设置」，规格三处误写「设置」殿后/在最后一位）；审阅原文见 `~/workspace/goals/app/hidden_files/neon_257_review.md`。

## §1 统一排序原则

采用 Neon 提案 §1「高频优先 + 粒度/风险递进」三段式排序规则，从上到下依次排列：

1. 顶部（高频主动作）：该菜单下用户最常点的动作，紧贴触发按钮，手指与视线位移最短。
2. 中段（中低频辅助动作）：按「日常高频 → 低频查询 → 学期级全局管理」降序排列。
3. 底部（低频重度 / 破坏性操作）：破坏性动作（如删除）强制垫底，远离顶部热区防误触；无破坏性动作时，由最低频的全局管理项垫底。

与 256 的衔接：破坏性垫底与 256 §2 的铁律一致；本规格不新增铁律，只给顺序。

## §2 三个菜单的新顺序

| 菜单 | 现状（自上而下） | 新顺序 | 改动点 |
|---|---|---|---|
| + 菜单（week_view_page.dart:338，_buildCreateMenu） | 手动新建课程 / 导入课表 / 新建课表 | 不变 | 不动 |
| ⋮ 菜单（menu_config.dart:28，kCustomMenuItems） | 课程搜索 / 空闲时段 / 导出课表图片 / 学期管理 / 考试倒计时 / 导入课表 | 导出课表图片 / 考试倒计时 / 空闲时段 / 课程搜索 / 学期管理 | 删 import，见 §3 |
| 学期行 ⋮ 菜单（semester_manage_page.dart:131，非当前学期行） | 编辑学期 / 切换到该学期 / 删除该学期 | 切换到该学期 / 编辑学期 / 删除该学期 | 前两项互换；删除垫底不动 |

补充说明：

- 主页 ⋮ 菜单实际渲染的是 homeMenuItems(menuConfig)（week_view_page.dart:615），「设置」经 homeMenuItems 过滤，菜单里只有 5 个自定义项、没有「设置」；visibleMenuItems（5 自定义 + 设置 = 6 行）是完整显示项定义，供菜单管理页与单测使用，不直接渲染主页 ⋮ 菜单。
- 学期行菜单 onSelected 按 value 分发（edit/switch/delete），与顺序无关，不改逻辑。注释 semester_manage_page.dart:115「非当前学期行保留 3 项 ⋮ 菜单（编辑 / 切换 / 删除）」同步改为「（切换 / 编辑 / 删除）」。
- 学期行菜单的三项图标与分类不变：切换（Icons.swap_horiz，数据）、编辑（Icons.edit_outlined，课表）、删除（Icons.delete_outline，破坏性）。

## §3 ⋮ 菜单：删除 import 项

- 从 kCustomMenuItems（menu_config.dart:28-65）删除 import 项（现 :57-64 的 MenuItemSpec，id 'import'，title '导入课表'，route '/import'，icon Icons.upload_file_outlined）。删除后 kCustomMenuItems 剩 5 项，默认顺序即声明顺序（MenuConfig.defaults() 按 kCustomMenuItems 生成，自动跟随，无需另写顺序表）。
- 文档里"六个/六项"同步改为"五个/五项"（只改与 ⋮ 菜单自定义项计数有关的文案）：
  - lib/models/menu_config.dart:7、:27、:123、:125、:130、:133、:164（"移动后 order 重新按 0..5 连续赋值"改为"0..4"）、:216。
  - lib/pages/week_view_page.dart:422（"全部六项工具"）、:867（"六项工具全关"与"列全部六项"）。
  - lib/providers/providers.dart:843、:918（"恢复默认：六项全显示"）。
  - 不动：lib/pages/course_tools_page.dart:26 的"六个工具入口"（那是课表工具箱自己的 6 个入口，与 ⋮ 菜单无关）；lib/database/db_helper.dart:37 的"六项"（信箱同步配置，无关）。
- 不改的函数（均为通用实现，自动适配 5 项）：MenuConfig.fromEncoded（未知 id 丢弃）、visibleMenuItems、homeMenuItems、MenuConfig.reorder、MenuConfigNotifier 的 setVisible / reorder / reset / _runLocked；categoryForMenuId 的 'import' 分支保留（见 §0 第 4 点）。

## §4 升级策略（不强制重置）

- 不写迁移代码、不在启动时改写已存配置。行为由现有代码保证：
  - 从未在菜单管理保存过配置的用户（home_menu_config 键为空/缺失）：build() 走 fromEncoded(null) 回 MenuConfig.defaults()，自动读到新默认顺序，无感切换。
  - 已手动调过顺序或开关的老用户（已有 JSON）：build() 解析时按新模板合并——自定义顺序与显隐保留，残留的 import 项被静默丢弃（§0 第 2 点），其余项不受影响；不弹任何提示。
  - 老用户想切回新默认顺序：在「设置 → 课表工具箱 → 菜单管理」点一次「恢复默认」，reset() 写 MenuConfig.defaults() 并落库。
  - 损坏/空/类型不对的已存配置：fromEncoded 回退全默认（现有行为，不变）。

## §5 不动项

- + 菜单：顺序、文案、图标、三项内容全部不动。
- 固定「设置」项：仍不在模型里，固定显示、不可关闭、不可排序移出；它恒在 visibleMenuItems 末尾，但主页 ⋮ 菜单经 homeMenuItems 过滤后不含「设置」（设置从底部栏进，WB_SPEC_234 起）；菜单管理页也不显示「设置」行（测试已断言 findsNothing）。
- 菜单管理页：行为不动（拖拽排序 + 显隐开关 + 恢复默认），只随配置自动显示 5 行。
- 形态与尺寸：三个菜单仍是 PopupMenuButton + buildAppPopupMenuItem（256 定版），不改形态、不改高度、不改 tooltip。
- 导入课表的其余入口不动：+ 菜单、数据备份与换机（DataSettingsPage）、桌面长按快捷、空学期占位按钮。
- 不改业务逻辑：onSelected 分发、路由、学期切换/编辑/删除的二次确认流程（_confirmSwitch / _confirmDelete）全部不动。

## §6 验收测试

- test/menu_config_test.dart（逐项改；测试名里的"六项"同步改为"五项"）：
  1. 「默认配置」：length 6 改为 5；ids 改为 ['share-image', 'exam-countdown', 'free-time', 'course-search', 'semester-manage']；order 改为 [0, 1, 2, 3, 4]。
  2. 「visibleMenuItems：默认返回」：length 7 改为 6；first.id 'course-search' 改为 'share-image'；last 仍为 settings。
  3. 「visibleMenuItems：全关仍恒含设置」：循环是通用的，改名即可（"六项全关"改为"五项全关"）。
  4. 「homeMenuItems：永远过滤设置」：deduped.length 6 改为 5；first.id 'course-search' 改为 'share-image'；visibleMenuItems(cfg).length 7 改为 6。
  5. 「homeMenuItems：全关 → 去重后为空」：改名；其余通用。
  6. 「copyWithVisible」：byId('import') 改为 byId('semester-manage')（import 已不在模型里；注意 byId 对未知 id 会回退一个默认项，直接断言 byId('import') 会假绿，必须换 id）。
  7. 「reorder」：把最后一项（import，oldIndex 5）拖到最前，改为把最后一项（semester-manage，oldIndex 4）拖到最前，期望顺序与 order 同步改。
  8. 「encode → fromEncoded 往返一致」：copyWithVisible('import', false).reorder(5, 0) 换成现存 id（如 'exam-countdown'）与 reorder(4, 0)。
  9. 「fromEncoded：null/空/损坏回退全默认，缺项补齐」：5 处 length 6 改为 5。
  10. 新增「fromEncoded：旧配置含已下线 import 静默丢弃」：输入含 6 项的旧 JSON（顺序自定义，如 import 在首位、某项 visible=false），期望输出 5 项、无 import；断言口径：按 items.map((e) => e.id).toList() 断言相对顺序与输入一致、且各 visible 状态不变，不 断言 order 值重归一为 0..4（fromEncoded 合并后保留存储的 order 值，只按 order 排序，不重赋值）。
  11. Notifier 组：「默认值」length 6 改为 5、first.id 改为 'share-image'；「reorder 持久化」reorder(5, 0) 改为 reorder(4, 0)；「reset 恢复默认」first.id 'course-search' 改为 'share-image'、last.id 'import' 改为 'semester-manage'；「并发写串行化」两处 first.id 'import' 改为 'semester-manage'、reorder(5, 0) 改为 reorder(4, 0)；「加载未完成时操作」setVisible('import', false) 与 byId('import') 断言换成现存 id。
- test/menu_manage_page_test.dart：
  - 「渲染」：标题表改为新默认顺序 5 项（导出课表图片 / 考试倒计时 / 空闲时段 / 课程搜索 / 学期管理），删「导入课表」；drag_handle 与 Switch 计数 6 改为 5；「设置」仍 findsNothing。
  - 「拖拽排序接线」：首行现为「导出课表图片」，拖下去后「考试倒计时」应排到它上面（断言按新首两项改；比较方式仍用 getTopLeft().dy）。
  - 「显隐开关接线」：通用（第一枚开关现为「导出课表图片」），注释同步。
- 新增 widget 测试：
  - 学期行菜单顺序（首选 test/semester_manage_test.dart，已有页面 pump 与学期数据；若放不下则新建 test/wb257_menu_order_test.dart）：造两个学期（一个当前、一个非当前），点非当前行的 ⋮，断言弹出菜单三项自上而下 y 坐标递增：切换到该学期 < 编辑学期 < 删除该学期（用 tester.getTopLeft 比较 dy，见 menu_manage_page_test 拖拽断言的写法）。
  - ⋮ 菜单渲染顺序（新建 test/wb257_menu_order_test.dart，复用 home_shell_test / week_jumper_outside_tap_test 的 pumpUntil 写法等主页 pump）：点顶栏 ⋮，断言菜单内 5 个自定义项自上而下 y 递增：导出课表图片 < 考试倒计时 < 空闲时段 < 课程搜索 < 学期管理，且「导入课表」findsNothing、「设置」findsNothing（主页 ⋮ 菜单取 homeMenuItems，不含「设置」；「设置」恒在最后一位仅由 menu_config_test 的 visibleMenuItems 单测覆盖，见本节第 2 条）。断言须限定在 PopupMenuItem 子树内（本周无课时空态占位也有「导入课表」按钮，全页 findsNothing 会误判——落盘实测）。
  - 新增测试不少于 3 项（上述第 10 条 fromEncoded 新测 + 这两项 widget 测）。
- 回归排查（审阅 P1 补）：全仓 test/ grep '导入课表' 与 kCustomMenuItems，核对每处命中：仅 menu_config_test.dart 与 menu_manage_page_test.dart 需按本节改；new_semester_entry_test.dart（+ 菜单三行与空学期占位按钮）、wb231_empty_week_placeholder_test.dart（空态按钮）、settings_icon_box_test.dart / settings_sections_test.dart（数据备份与换机行）均与 ⋮ 菜单无关，不动；wb230_unified_style_test.dart（categoryForMenuId 全表）因 §0 第 4 点保留 import 分支而不动。
- 全量：基线 900（2.13.0）→ 903（以实际新增数为准）；flutter test 全量通过、flutter analyze 零问题。注意测试前查 sqlite3 软链（见 256 教训），一次只跑一个 flutter test 进程，widget 测试用 drain 手动泵法、真实 IO 包 tester.runAsync。

## §7 版本

- 2.14.0（+50）。定版理由：改默认行为与删入口是行为变化，不是 bug 修复，按 2026-11-18 定版的版本号规矩（有新功能升中号、只是修复升小号）升中号；与 256 发 2.13.0 的口径一致。
- 发版流程同 2.13.0：提交（显式 pathspec + git commit --only，排除 WB_SPEC_223.md；永不 git stash pop）→ CI（run view 复核）→ 验包（versionCode 2050、指纹）→ Release v2.14.0 → 通道推 2.14.0/2050 → 云盘备份（不公开）→ 双推 → 需求文档同步。

## §8 追问跟进（2026-11-24 16:05 他定：导入页和工具页都改）

- 起因：2.14.0 全量 903/903 通过后，他让问 Neon 还有没有别的不合理的地方；Neon 指出的两处（全文见 hidden_files/neon_257_followup.md）经小马拿源码核实属实，他点选项定两处都改。
- ① import_page.dart 4 张导入卡片重排（Neon 确认，16:07）：从教务官网导入 / 拍照 / 相册识别课表 / 导入 ICS 日历文件 / 导入 PDF 课表文件。理由：教务官网是主路径、成功率最高；截图 OCR 门槛最低、最常用兜底；ICS 与 PDF 属小众文件导入，PDF 依赖教务导出格式，放最末。
- ② course_tools_page.dart 6 个工具入口重排（Neon 确认，16:07）：导出课表图片 / 考试倒计时 / 空闲时段 / 课程搜索 / 日期备注 / 菜单管理。前四项与新 ⋮ 菜单 1:1 一致；日期备注是辅助记录类、放第 5；菜单管理是元配置项、仍垫底（2.1.7 既定）。
- 不动：DataSettingsPage 6 行（从备份恢复夹在中间，Neon 自己说不确定——备份/恢复语义成对，拆开未必更好）；week_view 两处弹层（长按详情 256 已统过；同格多课是数据列表、"调整本次"是单动作、导出弹层只有分享/保存 + 取消，无顺序问题）。
- 测试：Neon 建议的 2 个轻量 widget 顺序回归测试并入 test/wb257_menu_order_test.dart（dy 严格递增断言）：导入页 4 卡片顺序、课表工具页 6 入口顺序。另：course_tools_page_test 的标题表与 wb235 导入页 entries 表顺序同步改新（仅列表顺序，断言不变）；「菜单管理最底部」测不受影响（菜单管理仍最末）。
- 全量：903 → 905（新增 2 项）；其余流程同 §7。
