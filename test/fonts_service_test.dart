import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/services/fonts_service.dart';

/// 导入字体注册表编解码（1.2.1）：往返一致、坏条目过滤、family 命名规则
void main() {
  test('注册表往返一致', () {
    const fonts = [
      ImportedFont(id: 'imp_1', name: '汉仪旗黑', ext: 'ttf'),
      ImportedFont(id: 'imp_2', name: 'Custom Font', ext: 'otf'),
    ];
    final back = FontsService.decodeRegistry(FontsService.encodeRegistry(fonts));
    expect(back.length, 2);
    expect(back[0].id, 'imp_1');
    expect(back[0].name, '汉仪旗黑');
    expect(back[1].ext, 'otf');
    expect(back[0].family, 'Imported_imp_1');
  });

  test('坏数据回退空表，坏条目被过滤', () {
    expect(FontsService.decodeRegistry(null), isEmpty);
    expect(FontsService.decodeRegistry(''), isEmpty);
    expect(FontsService.decodeRegistry('not json'), isEmpty);
    expect(FontsService.decodeRegistry('{"a":1}'), isEmpty);
    final back = FontsService.decodeRegistry(
        '[{"id":"imp_9","name":"好字体","ext":"ttf"},'
        '{"id":"bad_1","name":"前缀不对","ext":"ttf"},'
        '{"id":"imp_10","name":"","ext":"ttf"},'
        '{"id":"imp_11","name":"扩展名坏","ext":"woff"},'
        '{"id":"imp_12","name":"缺扩展"}]');
    expect(back.length, 1);
    expect(back.single.id, 'imp_9');
  });

  test('isImportedId 只认 imp_ 前缀', () {
    expect(FontsService.isImportedId('imp_123'), isTrue);
    expect(FontsService.isImportedId('lxgw'), isFalse);
    expect(FontsService.isImportedId('system'), isFalse);
  });
}
