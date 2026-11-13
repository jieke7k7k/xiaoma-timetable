import 'package:flutter/material.dart';

import '../ui/app_styles.dart';
import 'time_settings_page.dart' show SectionRulesBody;

/// WB_SPEC_228 §4.4《节次数量与分段规则》。
///
/// 第 3 层专项子页：全平铺，正文由 [SectionRulesBody] 承接（作息父页原 4 张卡
/// 的控件按「节次数量 / 分段设置 / 休息时段」三个线框组归拢，逻辑不动）。
class SectionRulesPage extends StatelessWidget {
  const SectionRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('节次数量与分段规则'),
        centerTitle: true,
      ),
      body: ListView(
        children: const [
          SectionRulesBody(),
          SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }
}
