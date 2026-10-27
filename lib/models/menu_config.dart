import 'dart:convert';

import 'package:flutter/material.dart';

/// 主页右上角「更多」菜单的配置模型（WB_SPEC_212 第 4 节）。
///
/// 菜单里可自定义的只有六个功能项；「设置」不在本模型里——它固定显示、
/// 不可关闭、不可排序移出，由主页菜单逻辑单独追加在末尾（见第 2/4 节）。
/// 配置整体以 JSON 数组存 app_settings 的 `home_menu_config` 键，
/// 每项 `{id, visible, order}`；损坏/缺失时回退默认，绝不拖垮启动。

/// 一个菜单功能项的描述（标题 / 路由 / 图标，与主页菜单现状一致）。
class MenuItemSpec {
  const MenuItemSpec({
    required this.id,
    required this.title,
    required this.route,
    required this.icon,
  });

  final String id;
  final String title;
  final String route;
  final IconData icon;
}

/// 六个可自定义菜单项，顺序即默认顺序（第 4 节定版，与改版前现状一致）。
const List<MenuItemSpec> kCustomMenuItems = [
  MenuItemSpec(
    id: 'course-search',
    title: '课程搜索',
    route: '/course-search',
    icon: Icons.search,
  ),
  MenuItemSpec(
    id: 'free-time',
    title: '空闲时段',
    route: '/free-time',
    icon: Icons.free_breakfast_outlined,
  ),
  MenuItemSpec(
    id: 'share-image',
    title: '导出课表图片',
    route: '/share-image',
    icon: Icons.image_outlined,
  ),
  MenuItemSpec(
    id: 'semester-manage',
    title: '学期管理',
    route: '/semester-manage',
    icon: Icons.school_outlined,
  ),
  MenuItemSpec(
    id: 'exam-countdown',
    title: '考试倒计时',
    route: '/exam-countdown',
    icon: Icons.event_note_outlined,
  ),
  MenuItemSpec(
    id: 'import',
    title: '导入课表',
    route: '/import',
    icon: Icons.upload_file_outlined,
  ),
];

/// 固定的「设置」菜单项（第 2 节：常驻兜底入口，不可关闭、不可移出）。
const MenuItemSpec kSettingsMenuItem = MenuItemSpec(
  id: 'settings',
  title: '设置',
  route: '/settings',
  icon: Icons.settings,
);

/// 按 id 查菜单项描述；未知 id（理论上不会）返回 null。
MenuItemSpec? menuItemSpecById(String id) {
  for (final s in kCustomMenuItems) {
    if (s.id == id) return s;
  }
  return null;
}

/// 单个菜单项的配置：id / visible / order。
class MenuItemConfig {
  const MenuItemConfig({
    required this.id,
    required this.visible,
    required this.order,
  });

  final String id;
  final bool visible;
  final int order;

  MenuItemConfig copyWith({bool? visible, int? order}) => MenuItemConfig(
    id: id,
    visible: visible ?? this.visible,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'visible': visible,
    'order': order,
  };

  factory MenuItemConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('菜单项配置必须是 JSON 对象');
    }
    final id = raw['id'];
    if (id is! String) {
      throw const FormatException('菜单项缺少 id');
    }
    return MenuItemConfig(
      id: id,
      visible: raw['visible'] is bool ? raw['visible'] as bool : true,
      order: raw['order'] is int ? raw['order'] as int : 0,
    );
  }
}

/// 主页「更多」菜单的完整配置：六个可自定义项的显隐与顺序。
///
/// [items] 恒为 6 项（对应 [kCustomMenuItems] 六个 id），内部保持按
/// [MenuItemConfig.order] 升序的显示顺序；`byId` 按 id 精确取单条。
class MenuConfig {
  const MenuConfig(this.items);

  /// 按显示顺序排列的六项配置（已按 order 升序）。
  final List<MenuItemConfig> items;

  /// 默认配置：六项全显示，顺序即 [kCustomMenuItems] 的声明顺序。
  factory MenuConfig.defaults() => MenuConfig([
    for (var i = 0; i < kCustomMenuItems.length; i++)
      MenuItemConfig(id: kCustomMenuItems[i].id, visible: true, order: i),
  ]);

  /// 显示顺序副本（防御性拷贝，调用方改动不影响本对象）。
  List<MenuItemConfig> get ordered => List.of(items);

  /// 可见项（按显示顺序）——主页菜单渲染用。
  List<MenuItemConfig> get orderedVisible =>
      items.where((e) => e.visible).toList();

  /// 按 id 取单条；id 不存在（理论不会）时回退默认配置里的对应项。
  MenuItemConfig byId(String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return MenuItemConfig(id: id, visible: true, order: 0);
  }

  /// 切换某项显隐，返回新配置（不改动本对象）。
  MenuConfig copyWithVisible(String id, bool visible) => MenuConfig([
    for (final e in items) e.id == id ? e.copyWith(visible: visible) : e,
  ]);

  /// 按 ReorderableListView.onReorderItem 的 (oldIndex, newIndex) 语义重排。
  ///
  /// 这里的下标是「显示顺序」的下标（同 [ordered]）；`newIndex` 已经是框架
  /// 移除 oldIndex 项之后的插入位置（Flutter 3.41+ 的 onReorderItem 回调已
  /// 代做 `newIndex > oldIndex → newIndex - 1` 调整），直接 removeAt + insert
  /// 即可。移动后 order 重新按 0..5 连续赋值。纯函数、单测覆盖。
  MenuConfig reorder(int oldIndex, int newIndex) {
    final list = ordered;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    return MenuConfig([
      for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ]);
  }

  /// 序列化为 JSON 字符串（数组，每项 id/visible/order）。
  String encode() => jsonEncode([for (final e in items) e.toJson()]);

  /// 从 JSON 字符串解析。null/空/损坏/类型不对一律回退全默认；缺项用默认
  /// 补齐，未知 id 丢弃，order 相同按默认顺序兜底（保证稳定）。
  factory MenuConfig.fromEncoded(String? raw) {
    final defaults = MenuConfig.defaults().items;
    if (raw == null || raw.isEmpty) return MenuConfig(defaults);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return MenuConfig(defaults);
      final byId = <String, MenuItemConfig>{};
      for (final e in decoded) {
        try {
          final cfg = MenuItemConfig.fromJson(e);
          byId[cfg.id] = cfg;
        } catch (_) {
          // 单条损坏跳过，其余仍可用
        }
      }
      // 以默认配置为模板补齐缺失项；未知 id 不在模板里，自然被丢弃
      final canonicalIndex = {
        for (var i = 0; i < defaults.length; i++) defaults[i].id: i,
      };
      final merged = [
        for (final def in defaults)
          byId[def.id] ?? def,
      ];
      merged.sort((a, b) {
        final c = a.order.compareTo(b.order);
        if (c != 0) return c;
        return canonicalIndex[a.id]!.compareTo(canonicalIndex[b.id]!);
      });
      return MenuConfig(merged);
    } catch (_) {
      return MenuConfig(defaults);
    }
  }
}

/// 由配置算出主页「更多」菜单的完整显示项（按显示顺序）。
///
/// 可见的六项在前（按 order），固定的「设置」恒在末尾——即使六项全关，
/// 列表也至少剩「设置」一项，从源头保证任何情况下都有进设置的兜底入口。
List<MenuItemSpec> visibleMenuItems(MenuConfig config) {
  return [
    for (final c in config.orderedVisible)
      menuItemSpecById(c.id) ?? const MenuItemSpec(
        id: 'unknown',
        title: '',
        route: '',
        icon: Icons.help_outline,
      ),
    kSettingsMenuItem,
  ];
}

/// 主页右上角菜单的运行时去重结果（WB_SPEC_213 第 4 节）。
///
/// 底部栏开启（[showBottomBar] 为 true）时过滤掉固定的「设置」项——设置改由
/// 悬浮胶囊进入；关闭时恢复显示。纯函数、只做运行时过滤，**绝不修改 [config]**
/// 持久化的显隐/排序配置数组；菜单管理页仍用 [visibleMenuItems]（不受去重影响）。
List<MenuItemSpec> homeMenuItems(MenuConfig config, {required bool showBottomBar}) {
  final items = visibleMenuItems(config);
  if (!showBottomBar) return items;
  return [for (final e in items) if (e.id != 'settings') e];
}
