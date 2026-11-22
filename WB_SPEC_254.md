# WB_SPEC_254: 学校库全量拉取 + A-Z 索引

## 0. 目标

把选校器的学校库从只有浙师大 1 条，换成上课 ShangKeSchedule 的全量学校库（约 1,780 所），
并给选校器加 A-Z 分组与右侧索引栏。随 2.12.0 发版（+48，新功能升中号）。

数据来源：github.com/qiqqqqq517/shangkeschedule，Apache-2.0。
只拉数据（校名 + 教务网址 + 系统类型），不抄对方的 JS 适配脚本，不碰任何 AGPL 来源
（NexioSchedule、OpenWakeUp 的数据与代码都不拉）。来源注明写进本规格书与转换脚本头注释
（schools.json 本身是 JSON，没有注释位）。

## 1. 拉取与转换脚本 tools/pull_schools.py（新增）

### 1.1 拉取

只拉一个文件（约 281KB），不要拉 .pb（initial 用 pypinyin 从校名算，见 1.3）：

```
https://raw.githubusercontent.com/qiqqqqq517/shangkeschedule/main/shared/assets/offline_repo/schools/timetable_schools.json
```

上游 JSON 每条字段：id / name / type / url。

### 1.2 依赖

Python 3 + pypinyin（`pip install pypinyin`，本机 venv 在 ~/workspace/.venv-pw）。
脚本开头 import pypinyin 失败时直接报错退出，写清楚缺什么，不要静默降级。
脚本是开发期手动工具：不进 CI、不进 App、不打包；确定性输出，重复跑同一份输入得到同一份文件。

### 1.3 转换步骤（按顺序）

1. 读上游 JSON。
2. type 按下表映射为 system，未知 type 映射为 null（不显示标签）：
   - zhengfang_new -> 正方教务
   - qiangzhi、qiangzhi_old -> 强智教务
   - kingosoft_new、kingosoft -> 青果教务
   - wisedu -> 金智教务
   - chaoxing -> 超星教务
   - urp、urp_new -> URP教务
   - south_soft -> 南软教务
   - allogene、dlut -> 各只有 1 所，转换时打印出来人工确认映射；确认前默认映射为 null（不中断脚本）
3. 校名后缀 " - 研究生" -> 去掉后缀，note 记为 "研究生"（上游共 31 行此类）。
4. 两条覆盖（原位替换，不要被上游旧地址覆盖）：
   - 浙师大：找到上游的 http://jwgl.zjnu.edu.cn/ 那条，原位换成现有条目
     （name 浙江师范大学，url https://jwxt.zjnu.edu.cn/，system null，note null）；
   - 大连海洋大学：按上游 CAS 包装地址精确匹配（见脚本 DLOU_OLD_URL），原位换成
     https://jwxt.dlou.edu.cn/，name 与 system 保留上游的；不按校名匹配，避免误伤同名研究生行。
5. 按 url 去重，保留先出现的（放在覆盖之后，避免覆盖后重新引入重复）。
6. 丢弃以下 URL（按我方 tryFromJson 的口径，见 lib/models/school_entry.dart）：
   - 畸形（缺 scheme、无 host、非 http/https）；
   - 内网地址：10/、172.16-31/、192.168/、127/ 开头，或 host 为 localhost；
   - query 里含 token、sessionid、jsessionid、ticket 参数名的 WebVPN 链接
     （参数名匹配忽略大小写；不带这类参数的 WebVPN 门户地址保留）。
7. initial 计算：把去掉 " - 研究生" 后缀后的完整校名传给 pypinyin（用其词库消歧多音字，
   不要只传首字，否则重庆会归到 Z、长沙会归到 Z、厦门会归到 S），取第一个音节的首字母，大写。
   首字不是中文、或拼音首字母不在 A-Z 内时记为 "#"。
   研究生行用去后缀后的校名算（例如 "南开大学 - 研究生" -> N）。
8. 写回 assets/data/schools.json：保持上游顺序（组内顺序即此顺序，不重排）；
   每条字段为 {name, system, url, note, initial}；timeSlots 一律不写（仍靠 250 机制导入时实测）。
9. 脚本结束打印统计：拉取条数、去重丢掉数、无效丢掉数、token 链接丢掉数、
   initial 为 "#" 的条数、最终条数；并断言：最终条数 > 1500；
   initial 为 A-Z 的占比 >= 95%；浙师大与大连海洋大学的覆盖已生效（断言目标 URL 在结果中）。

## 2. 模型：SchoolEntry 加 initial

lib/models/school_entry.dart：

- 加字段 `final String? initial;`（ctor 可选参数）。
- tryFromJson 解析 `initial`：是 String、trim 后转大写、单个字符且在 A-Z 或 "#" 内 -> 保留；
  否则记 null（坏值只丢 initial，不丢整条；缺 initial 的旧数据也按 null 处理）。
- displayName 不动；其余字段与校验逻辑不动。

## 3. 选校器：分组 + 右侧索引栏

### 3.1 纯函数（新建 lib/utils/school_sections.dart，配单测）

- `List<SchoolSection> groupSchoolsByInitial(List<SchoolEntry> schools)`：
  按 initial 分组，initial 为 null 的按 "#" 计；组按 A-Z 排序，"#" 组在最后；
  组内保持传入顺序（即 schools.json 预设顺序）；空列表返回空。
  SchoolSection 为简单数据类：{letter, schools}。
- 列表拍平与偏移（供索引栏跳转）：
  整个滚动列表拍平成带固定高度的条目，每种条目高度定死：
  - 最近使用节头 28.0；最近使用行 56.0；最近使用后分隔线 16.0（仅有最近使用时才有）；
  - 字母节头 28.0；学校行 56.0。
  - 拍平函数返回每条的起始偏移（prefix sum），并提供 `Map<String, double> indexOffsets(...)`
    （只含字母节头：字母 -> 该节头在列表内的起始偏移）。
- 行高固定的保证（两处缺一不可）：
  - 每个拍平条目外层包 SizedBox(height: item.height) 强约束渲染高度，
    使渲染高度与偏移表 100% 一致（ListTile 默认高度会被大字体与 visualDensity 撑大，
    不能只靠“单行标题 = 56.0”假设；当前 _buildSchoolTile 没有 subtitle，但字体缩放仍会撑高）；
  - ListView.builder 必须传 itemExtentBuilder，按 index 返回对应条目的固定高度
    （本工程 Flutter 3.47 已支持），让底层精确计算总高度与任意偏移，不依赖懒加载估算；
    没有它时 builder 会用已构建元素的平均高度估算未构建区域，1,740 条混排高度下跳转必漂移。
  - 学校行仍用 ListTile 单行标题（title maxLines: 1 + overflow ellipsis）；
    字母节头与最近使用节头用固定高度 28.0 的容器（文字左对齐，padding left 16）。
  - 跳转目标偏移必须 clamp 到 0.0 ~ _scrollController.position.maxScrollExtent
    （点末尾字母时目标可能超过最大可滚动范围）。

### 3.2 选校器页面改动（lib/pages/school_picker_page.dart）

- 非搜索态：主列表区改成 Row[Expanded(ListView.builder + ScrollController), 右侧索引栏]；
  ListView.builder 按拍平条目构建：字母节头渲染字母（labelMedium 样式），学校行复用现有
  _buildSchoolTile（title 加 maxLines: 1 与 ellipsis）；删掉现有的「全部学校」标签
  （由字母节头替代）。
- 右侧索引栏：只显示有学校的字母（按 A-Z 顺序，"#" 在末尾，仅当存在 "#" 组时显示）；
  字号 12，纵向居中排列；每字母高度用 LayoutBuilder 按可用高度自适应（12.0–20.0：
  上限 20.0，27 项共 540.0 在小屏上会溢出，不能写死 20.0；下限 12.0 保证字号不被压扁，
  可用高度不足时整栏纵向滚动）；键盘弹出时隐藏索引栏
  （MediaQuery.of(context).viewInsets.bottom > 0 时不渲染，否则搜索框聚焦未输入时
  可用高度骤降仍会触发 RenderFlex Overflow）。
  点按字母 -> _scrollController.jumpTo(对应偏移，先 clamp)（直接定位，不用 animateTo：
  300ms 内滚 90,000px 会逐帧构建大量中间条目，中低端机必卡顿；通讯录类索引栏通行做法是 jumpTo）。
  ScrollController 由 State 创建并在 dispose 里释放。
- 搜索态：保持现有平面过滤列表（子串匹配，不分组），不显示索引栏；
  最近使用区仍按现有规则在搜索态隐藏；搜索无结果空态不动。
  搜索态列表不用 ScrollController（与非搜索态的列表隔离，互不干扰滚动位置）；
  非搜索态的分组列表独占 _scrollController。
- 最近使用仍置顶显示在列表内（参与偏移计算）；最近使用的学校在分组里仍保留（与现在一致，不去重）。
- 底部「不在列表里？手动输入教务网址」入口不动；§9 开学日期确认流程不动。

## 4. 不动项

- 搜索逻辑（按 name/note 子串匹配）、最近使用存取、手动输入入口、WebImportPage、
  §9 开学日期确认、§8 作息检查与 §9 周数检查、抓取逻辑，全部不动。
- 不新增任何 Dart pub 依赖（不引拼音库；initial 是转换脚本算好的数据）。
- SchoolCatalogService 不用改：parseSchoolsJson 的按 url 去重与静默跳过逻辑原样复用；
  loadSchools 每次打开重新解析约 1,740 条，耗时可忽略。

## 5. 验收

### 5.1 转换产出核对（跑脚本后人工核对打印的统计）

- 最终条数约 1,740（上下浮动以打印为准，断言 > 1500）；
- 无重复 url；浙师大条目 url 是 https://jwxt.zjnu.edu.cn/；
  大连海洋大学条目 url 是 https://jwxt.dlou.edu.cn/；
- 31 行研究生 note 正确（抽查 3 行）；initial 为 A-Z 的占比 >= 95%，"#" 条数打印在统计里；
- 抽查前 50 所 URL 发 HEAD 请求，能通的记数即可（很多教务站只允许校园网访问，
  打不开是数据现状，不是转换错误，不阻塞发版）。

### 5.2 测试

- 模型/服务：tryFromJson 的 initial 解析（合法 A-Z、"#"、非法值、缺失四种）；
  parseSchoolsJson 去重仍有效。
- 新单测 test/utils/school_sections_test.dart：
  分组顺序（S 组在 Z 组前，"#" 组最后）、组内保持传入顺序、initial 为 null 的归入 "#"、
  偏移计算（最近使用区 + 两组各两校的 prefix sum 手算核对；另补无最近使用区的用例，
  验证此时不计入 28.0 节头与 16.0 分隔线）、空列表输入返回空、indexOffsets 只含节头字母。
- Picker widget 测试（在现有 test/pages/school_picker_page_test.dart 里加）：
  用 30 所学校（分属 A、Z、"#" 三组，目标节头初始在视口外——4 所学校只有 308px，
  小于测试默认视口 600px，节头一开始就在屏内，断言会假性通过）：节头出现且顺序正确；
  索引栏只显示有学校的字母（以索引栏容器 key school_index_bar 内断言为准）；
  点字母后断言 ScrollController.offset 变到预期的节头偏移
  （允许小误差），且对应节头滚入可见；搜索态隐藏索引栏与最近使用区
  （索引栏隐藏以容器不在树上为准，不以某个字母缺失为准——后者在搜索态下恒真）。
- 现有 picker 两个测试回归：最近使用仍置顶出现 2 处（最近使用区 + 分组内）；
  「全部学校」文案已删，旧测试不查它，无须改（若将来查到再更新）。
- assets 数据测试扩展（test/services/school_catalog_service_test.dart）：
  每条 initial 合法（null 或单字符 A-Z/#）；浙师大 initial 为 Z；大连海洋大学 initial 为 D。

## 6. 版本

2.12.0（+48）。
