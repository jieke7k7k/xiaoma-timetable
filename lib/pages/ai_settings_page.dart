import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../ui/app_styles.dart';
import '../widgets/app_dialog.dart';

/// 领 Key 说明全文（WB-202 第 4 项：从长说明卡片平铺改为条目标题旁 ⓘ 弹窗，
/// 正文一字不改）。
const String kFreeKeyGuide =
    '1. 打开 open.bigmodel.cn，注册并登录（手机号即可）；\n'
    '2. 右上角「API Keys」→ 添加新的 API Key；\n'
    '3. 复制那串 Key，粘回上面的输入框保存。\n\n'
    '智谱的 Flash 型号有免费额度，日常问答基本够用；'
    '若官方出了更新的 Flash 型号，直接改模型名即可。\n\n'
    '也可以换成任意 OpenAI 兼容服务：改接口地址与模型名，'
    '再填那家的 Key，其它逻辑完全一样。';

/// 智能助手设置（设置 → 智能助手 → 智能助手设置）：/ai-settings
///
/// 2.0.2（WB-202 第 2 项·A 方案）起本页是智能助手的二级页，与设置页一级
/// 界面的两行入口配套，内容包括四块：
/// 1. 接口地址 / 模型名 / API Key 表单（[AiSettingsForm]）；
/// 2. 「怎么领一个免费的 Key」长说明——不再卡片平铺，改为表单标题旁的 ⓘ
///    信息图标弹窗（正文见 [kFreeKeyGuide]，一字未改）；
/// 3. AI 桥入口（原「高级与数据」组并入本页）；
/// 4. 测试对话（放最底部，配好 Key 后发一句话验证连通）。
class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('智能助手设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: const [
          AiSettingsForm(),
          _KeySecurityNote(),
          _BridgeEntry(),
          _AiTestChat(),
        ],
      ),
    );
  }
}

/// AI 配置表单：接口地址 / 模型名 / API Key（遮挡）+ 保存
class AiSettingsForm extends StatefulWidget {
  const AiSettingsForm({super.key});

  @override
  State<AiSettingsForm> createState() => _AiSettingsFormState();
}

class _AiSettingsFormState extends State<AiSettingsForm> {
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();

  bool _obscureKey = true;
  bool _saving = false;
  bool _configured = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AiService.instance.loadSettings();
    if (!mounted) return;
    // 从没配过时直接填预设（智谱），用户只补一个 Key 就能用
    setState(() {
      _baseUrl.text = s.baseUrl.isEmpty ? AiSettings.defaultBaseUrl : s.baseUrl;
      _model.text = s.model.isEmpty ? AiSettings.defaultModel : s.model;
      _configured = s.configured;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final urlError = AiService.validateBaseUrl(_baseUrl.text);
    if (urlError != null) {
      _snack(urlError);
      return;
    }
    setState(() => _saving = true);
    try {
      await AiService.instance.saveSettings(
        baseUrl: _baseUrl.text,
        model: _model.text,
        apiKey: _apiKey.text,
      );
      final s = await AiService.instance.loadSettings();
      if (!mounted) return;
      setState(() {
        _configured = s.configured;
        _apiKey.clear();
      });
      _snack(_configured ? '已保存，可以去聊天了' : '已保存，但 API Key 还是空的，暂时用不了');
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: _loaded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题旁的 ⓘ（WB-202 第 4 项）：领 Key 长说明移入信息弹窗，
                  // 不再以整张卡片平铺占地方；正文见 kFreeKeyGuide（一字未改）
                  Row(
                    children: [
                      Text(
                        '接口（OpenAI 兼容）',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      AppInfoIconButton(
                        tooltip: '怎么领一个免费的 Key',
                        onPressed: () => showAppInfoDialog(
                          context,
                          title: '怎么领一个免费的 Key',
                          message: kFreeKeyGuide,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s),
                  TextField(
                    controller: _baseUrl,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '接口地址',
                      hintText: 'https://open.bigmodel.cn/api/paas/v4',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  TextField(
                    controller: _model,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '模型名',
                      hintText: 'glm-4-flash',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  TextField(
                    controller: _apiKey,
                    obscureText: _obscureKey,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'API Key（留空表示不修改）',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '当前状态：${_configured ? '已配好' : '还没填 API Key'}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('保存'),
                    ),
                  ),
                ],
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

/// 密钥安全小注（原说明卡片底部的补充文案，不是长说明，保留为小字）
class _KeySecurityNote extends StatelessWidget {
  const _KeySecurityNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Text(
        'API Key 只保存在本机、只用于请求头，不会写进日志；'
        '备份文件里也不含密钥，可以放心导出（恢复时以本机这边的密钥为准）。',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

/// AI 桥入口（WB-202 第 2 项：原「高级与数据」组并入智能助手二级页）
class _BridgeEntry extends StatelessWidget {
  const _BridgeEntry();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.hub_outlined),
      title: const Text('AI 桥'),
      subtitle: const Text('把私有仓库当命令信箱：外部 AI 下指令改课表，删除类指令会先等你确认'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, '/bridge'),
    );
  }
}

/// 测试对话（WB-202 第 2 项·A 方案）：配好 Key 后在这里发一句话验证连通。
///
/// 放在智能助手设置页最底部：不占用聊主页，也不写进聊天历史；只发用户这句
/// 原文（不带课表上下文），成功显示回复、失败显示中文原因，用来判断
/// 「接口地址 / 模型名 / Key 有没有配错」，不用切到底栏左键去试。
class _AiTestChat extends StatefulWidget {
  const _AiTestChat();

  @override
  State<_AiTestChat> createState() => _AiTestChatState();
}

class _AiTestChatState extends State<_AiTestChat> {
  final TextEditingController _input = TextEditingController();

  bool _sending = false;

  /// 最近一次回复（成功时）
  String? _reply;

  /// 最近一次失败原因（中文）
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _reply = null;
      _error = null;
    });
    final result = await AiService.instance.chat(
      [AiMessage(role: 'user', content: text)],
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.ok) {
        final t = result.text.trim();
        _reply = t.isEmpty ? '（接口返回了空回复）' : result.text;
      } else {
        _error = result.error ?? '请求失败';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '测试对话',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '配好后在这里发一句话，验证接口通不通，不用切到聊天页',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _input,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: '例如：你好，确认一下连通',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: const Text('发送'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
            if (_reply != null) ...[
              const SizedBox(height: AppSpacing.s),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(_reply!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
