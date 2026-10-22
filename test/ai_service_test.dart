import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/services/ai_service.dart';

/// AI 服务里的纯函数：配置清理 / 接口地址拼装 / 响应解析（不碰网络）
void main() {
  group('AiSettings', () {
    test('三项非空才算配好', () {
      expect(
        AiSettings.clean(
          baseUrl: ' https://open.bigmodel.cn/api/paas/v4 ',
          model: ' glm-4-flash ',
          apiKey: 'abc',
        ).configured,
        isTrue,
      );
      expect(
        AiSettings.clean(baseUrl: 'x', model: 'y', apiKey: '  ').configured,
        isFalse,
      );
    });

    test('接口地址自动补 /chat/completions（多余斜杠与已带后缀都兼容）', () {
      expect(
        AiSettings.clean(baseUrl: 'https://h/v4', model: 'm', apiKey: 'k')
            .chatCompletionsUrl,
        'https://h/v4/chat/completions',
      );
      expect(
        AiSettings.clean(baseUrl: 'https://h/v4/', model: 'm', apiKey: 'k')
            .chatCompletionsUrl,
        'https://h/v4/chat/completions',
      );
      expect(
        AiSettings.clean(
          baseUrl: 'https://h/v4/chat/completions',
          model: 'm',
          apiKey: 'k',
        ).chatCompletionsUrl,
        'https://h/v4/chat/completions',
      );
    });

    test('Key 留空时沿用旧 Key（输入框遮挡显示，不该被误清）', () {
      final s = AiSettings.clean(baseUrl: 'a', model: 'b', apiKey: '')
          .withKeyFallback('old-key');
      expect(s.apiKey, 'old-key');
      expect(s.configured, isTrue);
    });
  });

  group('AiService.extractReplyText', () {
    test('标准 OpenAI 响应取 choices[0].message.content', () {
      const raw = '{"choices":[{"message":{"role":"assistant",'
          '"content":"明天有两节课"}}]}';
      expect(AiService.extractReplyText(raw), '明天有两节课');
    });

    test('content 为数组时逐段拼接', () {
      const raw = '{"choices":[{"message":{"content":'
          '[{"type":"text","text":"前半"},{"type":"text","text":"后半"}]}}]}';
      expect(AiService.extractReplyText(raw), '前半后半');
    });

    test('兼容服务直接给 choices[0].text 也认', () {
      const raw = '{"choices":[{"text":"兼容格式"}]}';
      expect(AiService.extractReplyText(raw), '兼容格式');
    });

    test('坏数据一律返回 null（由调用方转成中文错误）', () {
      expect(AiService.extractReplyText('not json'), isNull);
      expect(AiService.extractReplyText('{}'), isNull);
      expect(AiService.extractReplyText('{"choices":[]}'), isNull);
      expect(AiService.extractReplyText('{"choices":[{"message":{}}]}'), isNull);
    });
  });

  group('AiService.describeHttpError（复审 C9：不回显响应原文）', () {
    test('OpenAI 风格错误只取 error.message', () {
      final msg = AiService.describeHttpError(
        401,
        '{"error":{"message":"Invalid API key","code":"invalid_api_key"}}',
      );
      expect(msg, contains('HTTP 401'));
      expect(msg, contains('Invalid API key'));
    });

    test('非 JSON 响应走通用文案，原文不出现', () {
      const raw = 'proxy echoed: Authorization: Bearer sk-LEAKED';
      final msg = AiService.describeHttpError(502, raw);
      expect(msg, contains('HTTP 502'));
      expect(msg.contains('sk-LEAKED'), isFalse);
      expect(msg.contains('Authorization'), isFalse);
    });
  });

  group('AiService.validateBaseUrl（复审 C9）', () {
    test('https 通过，http 公网拒绝，本机例外', () {
      expect(AiService.validateBaseUrl('https://open.bigmodel.cn/api/paas/v4'),
          isNull);
      expect(AiService.validateBaseUrl('http://api.example.com/v1'), isNotNull);
      expect(AiService.validateBaseUrl('http://localhost:8080/v1'), isNull);
      expect(AiService.validateBaseUrl('http://127.0.0.1:8080/v1'), isNull);
      expect(AiService.validateBaseUrl('not a url'), isNotNull);
    });
  });
}
