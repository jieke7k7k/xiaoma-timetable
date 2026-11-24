# WB_SPEC_259：选校器索引栏按住拖动快速选择

## §0 需求（用户原话）

右侧字母轴为啥不能按住之后滑动快速选择。改：按住索引栏上下拖动，手指滑到哪个字母就跳到哪组；松手结束。点按单个字母仍要能跳转（现有行为保留）。

## §1 现状（代码事实，lib/pages/school_picker_page.dart）

- `_buildIndexBar`（:407 起）：每个字母一个 GestureDetector，只有 onTap，调 `_jumpToLetter(letter, offsets)`。没有任何拖动手势处理。
- 所以按住拖动时：手指离开最初按下的字母后什么都不发生（onTap 要求按下抬起都在同一字母内）；矮屏时拖动还可能被外层 SingleChildScrollView 当成滚动吃掉。
- `_jumpToLetter`（:397）：按 offsets 表 jumpTo，clamp 到 maxScrollExtent。已有，直接复用，不改。
- 索引栏只在非搜索态、键盘未弹出时渲染；只显示有学校的字母；itemHeight 按可用高度自适应（12.0–20.0）。
- 现有 widget 测试：test/pages/school_picker_page_test.dart「254：30 所学校分组、索引栏跳转与搜索态隐藏索引栏/最近使用区」覆盖点按跳转（tester.tap('Z')）与搜索态隐藏。

## §2 首选方案（用户定）

- 整栏一个 Listener（挂在 Column 上），onPointerDown / onPointerMove / onPointerUp（+ onPointerCancel）。选 Listener 而不用 GestureDetector 的原因：指针事件不进手势竞技场，矮屏时不会被外层 SingleChildScrollView 抢走拖动；点按（按下无移动）与原来 onTap 行为一致（按下即跳）。
- 触点换算：details.localPosition.dy（相对 Column 本身，Column 高 = 字母数 × itemHeight）除以 itemHeight，floor 后 clamp 到 0..letters.length-1，取 letters[index]。
- 按下即跳（onPointerDown 就跳一次）；拖动中每次 onPointerMove 都算一次，字母变了才调 _jumpToLetter（字母不变不重复跳，防抖动）。
- Listener 设 behavior: HitTestBehavior.opaque（去掉每字母 GestureDetector 后，字母间空白处也要能接住指针），每字母的 GestureDetector 全部删掉。
- 状态：`String? _dragLetter`（当前拖到的字母，null = 没在拖）。setState 驱动两处视觉反馈：
  1. 栏内当前字母高亮：主色 + 加粗（FontWeight.w700），其余字母样式不变。
  2. 大字母气泡：_buildGroupedBody 返回 Stack 包住 Row，气泡居中（Center），64×64，圆角 12，主色底 + 白色 32sp 字母；只在 _dragLetter != null 时显示；松手（up/cancel）后清掉；气泡包 IgnorePointer，不拦截触摸。
- 约束：不动 _jumpToLetter 与 offsets 逻辑；不动 itemHeight 自适应与键盘/搜索态隐藏；不动「只显示有学校字母」；保留 ValueKey('school_index_bar')（现有测试靠它定位）；每字母的 SizedBox 尺寸与 Text 字号不变（只加高亮分支）；不改动列表本体与 ListView。

## §3 测试（加进 test/pages/school_picker_page_test.dart，复用现有 30 所学校脚手架与 drain）

1. 按住 A 拖到 Z：startGesture 落在栏内 A 字母中心，moveTo 到 Z 字母中心，断言列表 offset 跳到 Z 组（与现有测试同一 expectedZOffset 算法）、气泡显示 Z；up 后 pump，气泡消失。
2. 点按仍跳转：保留现有 tap('Z') 测试，不新增（回归由现有测试覆盖）。
3. 拖到栏底之外不崩：moveTo 到栏底下方，断言不抛异常、offset 停在最后一个字母对应的位置。

## §4 版本

新交互能力，按版本号规矩升中号：2.15.0+53。

## §5 已知局限（非 259 引入，原有行为）

- `_jumpToLetter` 按 `maxScrollExtent` 做 clamp，而 `SliverChildBuilderDelegate` 的 maxScrollExtent 是预估值，在列表未全量布局时偏小：拖/点到最后一个字母时可能落点比真实底部略短（实测 30 所学校用例：跳 # 时按 1381 落点，随后才收敛到 1445），但 # 组本身可见。修它要改 _jumpToLetter 的 clamp 机制（涉及点按行为），另立规格，不在本版做。
