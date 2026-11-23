# WB_SPEC_256：UI 交互与按钮统一

## §0 目标与依据

- 目标：把全 App 的交互呈现（底部弹层 / 对话框 / 弹出菜单 / 整页 / 系统选择器 / 轻提示）与按钮（层级、高度、触摸目标、位置）收敛到同一套规则，消除“同一位置不同形态、同类内容三种形态、同类按钮多档样式”的割裂感。
- 依据：审计文件 `~/workspace/goals/app/hidden_files/ui-interaction-audit.md`（190 处触发点全表；底部弹层 14、对话框 49、弹出菜单 3、整页跳转 42、日期选择 7、SnackBar 75）与 Neon 提案 `~/workspace/goals/app/hidden_files/neon_256_proposal.md`（2026-11-23，Gemini 新对话，Neon，低推理强度）。
- 本规格以 Neon 提案为底稿，并做以下三处修正（均已拿代码核对）：
  1. 三处裸 AlertDialog 的行号取源码中 AlertDialog( 构造调用行：`import_review_page.dart:487`、`:615`，`school_picker_page.dart:173`；审计文件记录的是对应方法入口行 :484、:607、:165（Neon 提案写的正是审计的行号，不是源码行）。
  2. 需由 40dp 升至 48dp 的底部操作栏主按钮是 7 处，不是 Neon 提案 2.3 节写的 6 处（见 §6.3 与 §7 清单逐项计数）。
  3. 当前学期行的 ⋮ 菜单仅 1 项（编辑学期），与 §2“禁止单项菜单”冲突，处理办法见 §3.2（改为行尾直接编辑入口，不再用 ⋮ 菜单）。
- 2026-11-23 审阅轮：另一模型（页面标注 Hydrogen，高思考等级）按 P0/P1/P2 审出 14 条，已逐条拿代码核对：13 条采纳并入各节，驳回 1 条（P1-3：引导页「跳过」实际在页面顶部右角，40dp 已合规，见 §9）；P1-4 的举例有误（所指「应用」按钮实为色盘弹窗的 AppDialogAction）且恢复 / 恢复出厂确认键已为 destructive，仅采纳入口行着色部分。审阅原文见 `~/workspace/goals/app/hidden_files/neon_256_review.md`。
- 范围：只改呈现形态与按钮形态，不改业务逻辑、不改文案内容、不改配色与导航结构（见 §9）。

## §1 交互呈现映射规则

触发类型决定呈现形态，按下表执行，不得自选：

| 触发类型 | 呈现形态 | 强制组件 / 做法 | 理由 |
|---|---|---|---|
| 顶栏快捷分流 / 行尾多操作（2～6 项纯动作） | 弹出菜单 | PopupMenuButton + buildAppPopupMenuItem | 紧贴触发锚点展开，视线位移最短，不打断当前视野 |
| 有限枚举单选（纯文本选项列表） | 底部弹层 | 统一复用 showAppSelectSheet | 拇指单手热区友好，列表可滚动且保留上方页面上下文 |
| 可视化 / 空间选择器（颜色、配色、动效、迷你周视图选时段） | 底部弹层 | 定制 showModalBottomSheet（统一拖拽条、标题栏、圆角） | 需要色块、预览卡片或网格画布，居中对话框宽度与操作空间受限 |
| 内容轻预览 / 长按上下文菜单（点课程卡、同格多课、长按课程） | 底部弹层 | showModalBottomSheet | 保持课表视觉上下文，支持轻扫关闭与单手操作 |
| 阻断式二次确认（删除、覆盖、放弃、权限引导、冲突确认） | 居中对话框 | 统一走 showAppConfirmDialog（基于 AppDialog） | 强打断机制防止误触，视线聚焦屏幕中央 |
| 必须阅读的阻断信息 / 异常报告（公告、失败原因、条目 ⓘ 说明、隐私） | 居中对话框 | 统一走 showAppInfoDialog / AppDialog | 需要用户明确阅读并点击确认，信息量超出轻提示承载能力 |
| 极简表单（≤3 个轻量字段、无需滚动） | 居中对话框 | 基于 AppDialog 封装表单 | 无需离开当前页面，填完即落库，减少页面跳转感 |
| 复杂表单 / 多步主流程 / 独立管理页（≥4 个字段或含复杂复合控件） | 整页跳转 | Navigator.push | 提供完整视口、键盘避让空间与独立返回栈，避免在弹窗内塞长表单 |
| 日历日期选择 / 本地文件读写 | 系统原生选择器 | showDatePicker / 平台文件选择器 | 符合 Android 系统肌肉记忆，避免自造日历与文件浏览器 |
| 瞬时操作结果反馈（成功、轻度校验提示） | 轻提示 | SnackBar（2～3 秒自动消失） | 不阻断后续操作；凡需展示详细报错或提供“复制错误报告”的一律升格为 AppDialog |
| 异步加载与进度 | 分层呈现 | 短耗时（小于 3 秒）用按钮内 16dp 转圈态；全库写入 / 安装包下载用模态进度 AppDialog | 避免轻量操作频繁闪现进度弹窗，同时保证重度不可中断任务锁死误操作 |

## §2 全局交互铁律

- 禁止“弹层叠弹窗”：严禁在 showModalBottomSheet 之上直接叠加 AppDialog。凡从底部弹层触发任何需要居中对话框的动作（新建学期、自定义颜色、删除确认），必须先关闭（pop）当前底部弹层，再打开目标对话框。
- 禁止裸 AlertDialog：全 App 所有居中对话框必须使用 AppDialog（圆角 AppRadii.dialog = 24dp + AppDialogAction），彻底清除原生 AlertDialog。验收时全仓 grep `AlertDialog(` 应无命中（AppDialog 内部封装与系统选择器内部实现除外——AppDialog 本身就是包着 AlertDialog 的壳，壳内的那一处不算）。
- 禁止单项菜单：PopupMenuButton 选项数量必须 ≥2 项；仅 1 项时严禁使用 ⋮ 溢出菜单，必须改为直接入口。
- barrierDismissible 统一口径：默认所有对话框允许点击外部关闭；仅「不可中断的进度遮罩」与「会导致全量数据丢失的终极确认」设为不可点外关闭（例外清单见 §8）。
- 轻提示三者边界：SnackBar 仅用于用户操作后的瞬时结果反馈；顶部横幅（_ChannelBanner）仅用于非阻断的全局通知（版本更新、普通公告）；悬浮胶囊仅用于页面模式状态提示（进入编辑模式）。

## §3 五处交互改造

### §3.1 主页顶栏 +（底部弹层）vs ⋮（弹出菜单）

- 将主页顶栏 + 号由 showModalBottomSheet 改为 PopupMenuButton + buildAppPopupMenuItem，包含「手动新建课程 / 导入课表 / 新建课表」3 项，与相邻的 ⋮ 保持完全一致的顶栏弹出菜单形态。
- 注意：弹出菜单项只承载标题与图标，+ 弹层现有的三行副标题（「逐项填写课程信息」「ICS / 图片 OCR / PDF，支持冲突检测」「新建一个学期，建好直接切换」）不迁移。
- 补齐顶栏 + 号 tooltip: '新建或导入'（见 §6.5）。

### §3.2 ⋮ 在三处含义不同

- 主页顶栏 ⋮：保留为动态工具溢出菜单（2～6 项），符合 §1 规则。
- 设置页顶栏 ⋮：仅 1 项「关于小马课表」，彻底移除顶栏 ⋮，将「关于小马课表」下沉为设置页最底部的标准入口行（与其他分类入口行一致），设置页顶栏回归纯标题。
- 学期管理行尾 ⋮：非当前学期行保留为行内操作菜单（编辑学期 / 切换到该学期 / 删除该学期，3 项），符合 §1 规则。
- 当前学期行：其 ⋮ 菜单仅 1 项（编辑学期），与 §2“禁止单项菜单”冲突。处理：当前学期行改用行尾直接编辑入口（编辑图标按钮，带 tooltip「编辑学期」），不再使用 ⋮ 菜单。

### §3.3 同类表单三种形态 & “选一个值”三种形态

- 表单按字段复杂度收敛为两档：≤3 个轻量字段统一用 AppDialog（学期表单：名称、开学日期、总周数；确认开学日期；备注表单；导入草稿编辑）；≥4 个字段或含周次 / 时段等复杂控件统一用整页（新建 / 编辑课程、调整本次课程）。
- 迷你周视图选时段归类为“可视化空间选择器”，保持底部弹层。
- “选一个值”按数据类型收敛：有限纯文本枚举全部统一复用 showAppSelectSheet（目标学期、提前提醒分钟、作息模板）；课程表单下拉项已走 AppSelectField → showAppSelectSheet，保持现状不动；可视化预览选择（主题色、配色、动效、选时段）用定制底部弹层；自由数字输入（总周数）归入极简表单用 AppDialog；日期全部用 showDatePicker。

### §3.4 两套对话框实现（3 处裸 AlertDialog）

- 将以下 3 处全部迁移至 AppDialog + AppDialogAction，统一 24dp 圆角与按钮间距（行号为源码中 AlertDialog( 构造调用行；审计文件记录的是对应方法入口行 :484、:607、:165）：
  1. 导入核对页「作息不同」（`import_review_page.dart:487`）。
  2. 导入核对页「周数不一致」（`import_review_page.dart:615`）。
  3. 选校器「确认开学日期」（`school_picker_page.dart:173`，直接复用或对齐 showSemesterStartConfirmDialog）。

### §3.5 导入流程弹层叠 Dialog & 删课两种关闭顺序

- 导入流程：在导入页「选择目标学期」底部弹层中点「新建学期」时，改为先关闭底部弹层，再弹出新建学期 AppDialog（showSemesterFormDialog）；创建成功后自动选中新学期并给 SnackBar 反馈。
- 外观设置同步改：主题色底部弹层点「自定义」时，改为先关闭底部弹层再弹 HSV 颜色 AppDialog。
- 删课顺序：统一执行“先关弹层，再弹确认”。课程详情底部弹层中点击「删除」时，先关闭详情弹层，再弹出 showAppConfirmDialog，与编辑模式长按菜单删课保持完全一致。
- 导出失败顺序：主页 ⋮ →「导出课表图片」打开的 showExportBottomSheet 内，导出 / 保存失败时同样先关闭底部弹层，再弹出错误 AppDialog（涉及 week_view_page.dart:2961、3001、3007、3020、3047、3053 六处 showAppInfoDialog 调用）。注意：其中 :3001（分享阶段失败）与 :3047（保存阶段失败）两处在 `popped == true` 分支里，弹层在分享/保存调用前已经收起，**不得再 pop 一次**（否则会把主页也弹掉），只加 `parentContext.mounted` 守卫即可；其余四处（读课程失败、生成阶段失败）弹层还开着，先 pop 再弹错。

## §4 按钮层级与全局主题

- 必须在 main.dart 的 ThemeData 中建立全局按钮主题（FilledButtonTheme、OutlinedButtonTheme、TextButtonTheme），禁止散落手写局部尺寸与圆角覆盖。圆角统一取 AppRadii 中的按钮圆角常量；若尚无该常量则新增并统一引用，禁止各处手写数值。全局按钮主题默认高度为 40dp；48dp 底部操作栏按钮必须通过统一的底部栏按钮样式常量或封装组件声明，禁止各页面零散手写 48dp 魔法数字。
- 层级规范：

| 层级 | 组件 | 样式 | 用途 |
|---|---|---|---|
| 主操作（Primary） | FilledButton | primary 实底 + onPrimary 字 | 单个页面、弹层或对话框内最多 1 个 |
| 次操作（Secondary - 有边界） | OutlinedButton | 透明底 + outline 描边 | 与主按钮并排的次级动作（如保存本地、手动补录、新增时段） |
| 次操作（Secondary - 轻量） | TextButton | 无底色无边框 | 取消、跳过、卡片内联入口、对话框次要选项 |
| 弱引导单一行动点 | FilledButton.tonal | 浅色实底 | 仅用于空态页、错误重试区或弹层内单一辅助推荐动作 |
| 破坏性操作（入口态） | TextButton / IconButton | error 色前景，无底色 | 触发二次确认前的删除 / 放弃入口，不得使用红实底或粉底 |
| 破坏性操作（确认态） | FilledButton（经 AppDialogAction） | error 实底 + onError 白字 | 仅用于 AppDialog 内执行不可逆删除 / 覆盖的最终确认键 |
| 悬浮主操作（FAB） | FloatingActionButton.extended | primary 实底，56dp 高 | 仅限列表管理页的全局“新建”入口（例外见 §8） |

## §5 高度、触摸目标与位置规则

- 两档视觉高度（由位置唯一决定）：48dp 高——所有页面底部操作栏与底部弹层底部操作栏的主按钮（以及与其同排 / 上下配对的次按钮）；40dp 高——所有对话框内（AppDialog）、卡片内、顶栏、列表行内的按钮。紧凑内联下限 36dp：卡片内辅助文字按钮与快捷周次芯片视觉高度不低于 36dp（废除 32dp 与 34dp），且依赖 padded 补足 48dp 命中区。
- 最小触摸目标硬红线：全 App 所有可点元素触摸命中区必须 ≥48×48dp。严禁对任何按钮设置 tapTargetSize: shrinkWrap。严禁对 IconButton 使用 visualDensity: compact 将命中区压至 48dp 以下。严禁用裸 GestureDetector + 小尺寸 Container 实现小于 48×48dp 的可点块。所有顶栏与行尾 IconButton 必须配置中文 tooltip。
- 位置规范：顶栏仅放返回、图标操作（IconButton / PopupMenuButton）或单一状态退出（如编辑模式「完成」），严禁顶栏与底部同时存在两个「保存」按钮。页面 / 弹层底部操作栏：单操作全宽 48dp；双操作为「左次（OutlinedButton）+ 右主（FilledButton）」，间距 12dp；严禁 3 个等宽按钮并排挤在一行。双操作文案较长时（如调课页「保存调整」与「撤销本次调整」），允许采用上主下次全宽 48dp 垂直堆叠（间距 12dp）。对话框底部：统一走 AppDialogAction 右对齐，左次右主；三选时按「取消 → 次要 / 红色放弃 → 主操作」从左到右排列。

## §6 五处按钮改造

### §6.1 课程详情页底部三个等宽按钮（删除 / 新增时段 / 编辑）

- 废弃自定义 _DetailAction 与 shrinkWrap（`widgets/course_detail_sheet.dart:145–215`，当前为高 44dp 的三等宽按钮行，flex 3/4/4，间距 10dp）。
- 底部操作栏改为双键布局（高度统一 48dp，间距 12dp）：左侧 OutlinedButton.icon「新增时段」（flex 4）+ 右侧 FilledButton.icon「编辑」（primary 实底，flex 5），360dp 窄屏下完全不触发省略号。
- 「删除」移出底部操作栏，放置于课程详情弹层右上角，改为纯 error 色 IconButton（delete_outline，48×48dp，带 tooltip「删除课程」），彻底远离底部右手主操作热区并拉开主次。
- 点击删除时先关闭详情弹层，再弹出 showAppConfirmDialog（见 §3.5）。

### §6.2 课程编辑页两个「保存」权重不同

- 删除顶栏右侧的 TextButton「保存」，仅保留底部操作栏中的 48dp 高 FilledButton「添加课程 / 保存修改」。
- 底部操作栏保持固定可见（无需滚动到底即可点击）。

### §6.3 主按钮高度两档无规则（48dp vs 40dp）

- 严格执行“底部操作栏 48dp / 其余位置 40dp”。以下 7 处底部操作栏按钮统一由 40dp 升至 48dp（Neon 提案 2.3 节写的“6 处”有误，按 §7 清单逐项计数为 7 处；课程编辑页保存已是 48dp，不在其中）：
  1. 导入页「继续」。
  2. 导入核对页「确认导入」。
  3. 导入核对页「手动补录」。
  4. 导入冲突页「按此处理并导入」。
  5. 导出图片页「保存到本地」。
  6. 导出图片页「分享图片」。
  7. 选时段弹层「确认选定」。

### §6.4 删除红三档不统一

- 统一收敛为“入口态纯红无底 + 确认态红实底”二档制：
  - 课程详情「删除」去掉粉底，改为右上角 error 色图标按钮（见 §6.1）。
  - 设置页「删除所选字体」（两处重复实现需合并为一处复用组件）由默认主色改为 error 色 TextButton.icon。
  - 备注页行尾删除图标、导入核对页草稿行尾「删除此条」图标由默认色改为 error 色，并确认具备 tooltip。
  - 所有 AppDialog 删除确认键保持 error 实底 FilledButton（经 AppDialogAction，destructive）。

### §6.5 周数选择小芯片 38×34 + 顶栏 + 号无 tooltip + ⓘ 疑似 44×44

- 周数选择小芯片（_WeekButton，`widgets/week_picker.dart:253`，现为裸 GestureDetector + 固定 38×34）：废弃裸 GestureDetector 与 38×34 固定尺寸，改为 Material 可点击控件（带水波纹）。视觉块 40×40dp，Wrap 的 spacing 与 runSpacing 统一改为 8dp（废除现有的 6dp：40+6=46dp 中心距 < 48dp，命中区会互相重叠）；每块外层用 48×48dp 的透明命中容器包裹视觉块（命中区 ≥48×48dp，相邻中心距 ≥48dp，互不重叠）；每行排布由 Wrap 自适应（360dp 屏约 6 个一行），不得为凑满每行 7 个而压缩命中区。_QuickButton 视觉高从 34dp 升至 36dp。
- 顶栏 + 号（`week_view_page.dart:873`）补齐 tooltip: '新建或导入'。
- ⓘ 说明图标（AppInfoIconButton）移除 visualDensity: compact，保留 18dp 视觉图标大小的同时恢复标准 48×48dp 触摸目标。
- 顺带规范：导入冲突页顶部 3 个批量 OutlinedButton（全部跳过 / 全部覆盖 / 全部保留）降级为 TextButton 或收进顶栏 ⋮ 批量菜单，避免与底部主按钮抢视觉；编辑课程「在课表上选」与教务网页导入「诊断建议」两个 32dp 按钮视觉高度提升至 36dp。

## §7 按页面迁移清单

- 全局主题与基础弹窗（main.dart、widgets/app_dialog.dart、widgets/update_download_dialog.dart、widgets/week_picker.dart）：1. 在 ThemeData 中新增全局 FilledButtonTheme / OutlinedButtonTheme / TextButtonTheme（默认高 40dp、padded 48dp 命中区、统一圆角）。2. AppInfoIconButton 移除 visualDensity: compact，恢复 48×48dp 触摸目标。3. UpdateDownloadDialog 底部 5 阶段共 11 颗裸按钮全部替换为 AppDialogAction，外壳改用 AppDialog（现为 AlertDialog，见 update_download_dialog.dart:169，必须替换，否则 §10.5 的 grep 验收不通过）。4. _WeekButton 替换裸 GestureDetector，改为 40×40dp 视觉块 + 外层 48×48dp 命中容器，Wrap spacing / runSpacing 统一 8dp；_QuickButton 视觉高从 34dp 升至 36dp。5. 全仓 IconButton 逐一排查，补齐所有顶栏、搜索框及行尾 IconButton 的中文 tooltip。
- 周视图（主页）week_view_page.dart：1. 顶栏 + 号补齐 tooltip: '新建或导入'。2. 顶栏 + 号呈现方式由 showModalBottomSheet 改为 PopupMenuButton + buildAppPopupMenuItem。3. showExportBottomSheet 内导出 / 保存失败时，先关闭底部弹层再弹出错误 AppDialog（六处调用见 §3.5）。
- 课程详情弹层 widgets/course_detail_sheet.dart：1. 废弃 _DetailAction 与 shrinkWrap。2. 底部改为双键 48dp 布局：左「新增时段」（OutlinedButton.icon）+ 右「编辑」（FilledButton.icon）。3. 「删除」移至弹层右上角，改为 error 色 IconButton（48×48dp，带 tooltip）。4. 点击删除时改为先关闭详情弹层，再弹出 showAppConfirmDialog。
- 课程编辑页 course_edit_page.dart：1. 移除顶栏右侧 TextButton「保存」，仅保留底部固定 48dp FilledButton。2. 「在课表上选」内联按钮视觉高从 32dp 调整为 36dp。
- 选时段弹层 widgets/select_time_sheet.dart：底部「确认选定」FilledButton 高度由 40dp 升至 48dp。
- 设置首页与分区 settings_page.dart、settings_sections.dart：1. 移除设置首页顶栏 ⋮ 菜单，将「关于小马课表」下沉为设置页最底部的标准入口行。2. 「提前提醒」底部弹层改用统一 showAppSelectSheet。3. 「主题色」弹层点「自定义」时，改为先关闭底部弹层再弹 HSV AppDialog。4. 合并两处重复的字体操作区代码；「删除所选字体」改为 error 色 TextButton.icon。5. 「从备份恢复」入口行标题改为 error 色（其确认键已为 destructive，保持）。
- 导入页 import_page.dart：1. 「目标学期」选择底部弹层统一复用 showAppSelectSheet 承载已有学期枚举；「新建学期」改为弹层底部 footer 按钮（showAppSelectSheet 已有 footer 参数，现为置顶高亮项，位置随之由顶部移至底部），点击先关闭底部弹层，再弹出 showSemesterFormDialog。首次打开弹层不预勾任何学期（复审 #53：恢复 WB_SPEC_220「引导新建」语义——用户首次导入通常是新学期课表，默认勾当前学期会误导；选过之后 _target 保持为上次选择；当前学期仍以「当前使用中」标注在行文案里）。2. 底部「继续」FilledButton 高度由 40dp 升至 48dp。
- 选校器页 school_picker_page.dart：1. 「确认本学期开学日期」由原生 AlertDialog + 裸按钮迁移至 AppDialog + AppDialogAction（直接复用或对齐 showSemesterStartConfirmDialog）。
- 教务网页导入页 web_import_page.dart：诊断卡片内「诊断建议」按钮移除 visualDensity: compact，视觉高从 32dp 升至 36dp。
- 导入核对页 import_review_page.dart：1. 「作息不同」与「周数不一致」两处原生 AlertDialog + 裸按钮全部迁移至 AppDialog + AppDialogAction。2. 底部「手动补录」与「确认导入」高度由 40dp 升至 48dp。3. 草稿卡片行尾「删除此条」IconButton 着色为 error 色并确认带 tooltip。
- 导入冲突页 import_conflicts_page.dart：1. 底部「按此处理并导入」FilledButton 高度由 40dp 升至 48dp。2. 顶部 3 个批量 OutlinedButton（全部跳过 / 覆盖 / 保留）降级为 TextButton 或收进顶栏 ⋮ 批量操作菜单。
- 导出图片页 share_image_page.dart：底部「保存到本地」与「分享图片」高度由 40dp 升至 48dp。
- 备注页 notes_page.dart：备注行尾删除 IconButton 着色为 error 色并确认带 tooltip。
- 作息时间页 time_settings_page.dart：「套用作息模板」底部弹层统一复用 showAppSelectSheet。
- 数据管理页 data_manage_page.dart：「恢复出厂」二次确认弹窗的第二步（终极确认）设置 barrierDismissible: false（showAppConfirmDialog 已有该参数，默认 true）。「从备份恢复」「恢复出厂」入口行标题改为 error 色；确认键已为 destructive，保持。
- 学期管理页 semester_manage_page.dart：当前学期行改用行尾直接编辑入口（编辑图标按钮，带 tooltip「编辑学期」），不再使用 ⋮ 菜单（见 §3.2）；非当前学期行保留 3 项 ⋮ 菜单。

## §8 例外条款与触发条件

- 可视化选择器不强制复用 showAppSelectSheet：适用对象为主题色宫格、课程配色方案、切换动效三选一、迷你周视图选时段；允许条件：选项依赖色块、卡片预览或二维网格交互，纯文本列表无法表达；但必须复用统一的底部弹层外壳规范（圆角、拖拽指示条、标题栏与 48dp 底部主按钮）。
- 极简表单在 AppDialog 中的 3 字段上限例外：适用对象为新建 / 编辑学期（名称、开学日期、总周数）、导入草稿编辑；允许条件：字段数 ≤3 个、单屏无滚动、不嵌套自定义二级弹窗（调用系统 showDatePicker 除外）。若未来需求扩展至 ≥4 个字段或新增周次选择器，必须迁移为整页。
- FAB 用于非“新建”动作的唯一例外：适用对象为教务网页导入页的「抓取本页课表」；允许条件：页面主体为全屏沉浸式 WebView 且底部无固定操作栏，需要悬浮唯一主动作入口。除 WebView 沉浸页外，其余执行类动作一律使用底部 48dp 操作栏，不得使用 FAB。
- barrierDismissible: false 的严格例外：适用对象为恢复备份进度遮罩、更新下载进行中弹窗、恢复出厂终极二次确认；允许条件：仅当「点外关闭会导致写入中断 / 状态损坏」或「即将清空全量本地数据」时启用；下载类弹窗必须提供安全的「取消下载」按钮，其余普通弹窗一律允许点外关闭。
- 周数字块紧凑网格的视觉尺寸例外：适用对象为 week_picker.dart 中的周数字块 1～N；允许条件：为保证 20～30 周在一屏内可快速扫视，允许视觉方块保持 40×40dp（而非 48×48dp），但必须同时满足：Wrap spacing 与 runSpacing 均为 8dp，外层命中容器 48×48dp，相邻中心距 ≥48dp，命中区互不重叠；每行排布由 Wrap 自适应，不得压缩命中区。
- SnackBar 附带操作按钮与延长时长例外：适用对象为首次开启上课提醒后的电池优化引导提示（settings_sections.dart:606）；允许条件：仅当提示对应“一键跳转系统设置即可完成的补救步骤”时，允许附带 1 个 Action 按钮并将展示时长延长至 6 秒；其余 SnackBar 一律纯文本、2～3 秒自动消失。

## §9 不动项

- 配色、主题色、宫格、动效等品牌视觉不动，只改呈现形态与按钮形态。
- 文案内容不动：菜单项标题、提示文案、按钮文案逐字保留；仅 §3.1 注明的 + 菜单三行副标题不迁移（弹出菜单项只承载标题与图标）。
- 导航结构不动：底栏三键、页面层级、返回栈不动。
- 业务逻辑不动：导入检查（作息、周数）、周数统一、选校器、下载续传等行为只改呈现，不改判定与流程。
- SnackBar 文案与触发时机不动（只统一时长与 Action 规则，电池提示例外已列入 §8）。
- 课程卡、午间 / 晚间带子、周视图网格渲染不动。
- 引导页「跳过」位于页面顶部右角，按顶栏按钮规则保持 40dp，不动（审阅曾误以为它在底部，已核对代码否决）。

## §10 验收

- 全量 flutter test 通过，analyze 零问题。
- 新增 / 更新测试（均用本仓 drain 手动泵法，不得用 pumpAndSettle；真实 IO 包 tester.runAsync）：
  1. 详情弹层双键布局：底部行只有「新增时段」（OutlinedButton）与「编辑」（FilledButton）两颗，删除不在底部行，删除为右上角 error 色 IconButton 且带 tooltip；两键高度均为 48dp。
  2. 主页顶栏 + 号：点开为 PopupMenuButton 菜单，含「手动新建课程 / 导入课表 / 新建课表」3 项；+ 号带 tooltip '新建或导入'。
  3. 设置页无顶栏 ⋮ 菜单；设置页最底部有「关于小马课表」标准入口行。
  4. 当前学期行无 ⋮ 菜单，有编辑图标按钮；非当前学期行 ⋮ 菜单含编辑 / 切换 / 删除 3 项。
  5. 全仓 grep `AlertDialog(` 无命中（AppDialog 内部封装与系统选择器内部实现除外）；并确认 UpdateDownloadDialog 已改用 AppDialog 作为外壳。
  6. 全仓 grep `shrinkWrap` 在按钮处无命中；全仓 grep `visualDensity` 确认无任何按钮控件（含 TextButton、OutlinedButton、FilledButton、IconButton、AppInfoIconButton）使用 compact 压缩触摸区域。
  7. 触摸目标：详情弹层两键、周数小芯片外层可点容器渲染尺寸 ≥48×48dp 且相邻中心距 ≥48dp。
  8. 课程编辑页无顶栏 TextButton「保存」，底部 FilledButton「添加课程 / 保存修改」存在且高 48dp。
  9. §6.3 的 7 处底部操作栏按钮高度均为 48dp。
  10. 导入流程与删课：选学期弹层点「新建学期」时先关闭弹层再弹对话框，删课与导出失败同样先关弹层再弹确认；断言目标 AppDialog 可见（findsOneWidget）的同时，原底部弹层（CourseDetailSheet / 目标学期选择弹层 / 导出弹层）在 Widget 树中已销毁（findsNothing）。
- 真机 / 截图验收（重点）：主页顶栏、详情弹层、课程编辑页、设置页、导入流程（弹层 → 对话框的关闭顺序）、周数小芯片手感。

## §11 版本

- 2.13.0（+49）。本次为交互与按钮体系的统一重构（新增全局按钮主题、多处呈现形态变更），按版本号规矩升中号。基线：基于 2.12.0（WB_SPEC_254）递增；构建号按合入时 pubspec.yaml 现有构建号 +1（预期 +49）。
