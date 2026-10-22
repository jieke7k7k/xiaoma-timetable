import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../ui/app_styles.dart';

/// AI 助手设置（设置 → AI 助手 的那一组，也可整页打开：/ai-settings）
///
/// 三个字段（接口地址 / 模型名 / API Key）都是纯文本，存 app_settings，
/// 只落本机。预设值给的是智谱（open.bigmodel.cn）的 OpenAI 兼容地址与
/// Flash 型号——免费额度够日常问答；换成任何 OpenAI 兼容服务只改前两项。
///
/// 表单抽成 [AiSettingsForm] 是为了两处复用：设置页里内嵌一组（用户要求
/// 「设置页加 AI 助手一组」），聊天页顶部齿轮再整页打开同一份表单，
/// 不用把三个字段与保存逻辑写两遍。
class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: const [
          AiSettingsForm(),
          AiSettingsTips(),
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
                  Text(
                    '接口（OpenAI 兼容）',
                    style: Theme.of(context).textTheme.titleSmall,
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

/// 领 Key 的说明（整页与设置页「AI 助手」那组共用同一份文案）
class AiSettingsTips extends StatelessWidget {
  const AiSettingsTips({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '怎么领一个免费的 Key',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.s),
                const Text(
                  '1. 打开 open.bigmodel.cn，注册并登录（手机号即可）；\n'
                  '2. 右上角「API Keys」→ 添加新的 API Key；\n'
                  '3. 复制那串 Key，粘回上面的输入框保存。\n\n'
                  '智谱的 Flash 型号有免费额度，日常问答基本够用；'
                  '若官方出了更新的 Flash 型号，直接改模型名即可。',
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  '也可以换成任意 OpenAI 兼容服务：改接口地址与模型名，'
                  '再填那家的 Key，其它逻辑完全一样。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Text(
            'API Key 只保存在本机、只用于请求头，不会写进日志；'
            '备份文件里也不含密钥，可以放心导出（恢复时以本机这边的密钥为准）。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ),
      ],
    );
  }
}
