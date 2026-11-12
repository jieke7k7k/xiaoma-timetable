import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/clean_gap_input_border.dart';

/// §12 第二批：点输入框时框先变白、约 200ms 后才变回填充色（真机反馈）。
///
/// 根因：CleanGap 没重写 lerpFrom/lerpTo/scale，焦点切换时 _BorderContainer
/// 的 border 动画经父类 OutlineInputBorder.lerpFrom 退化成普通 OutlineInputBorder
///（只画描边不画填充），filled:false 又让原生填充停掉，动画期间框里是空的。
/// 以下测试直接锁死插值路径：全程必须返回 CleanGap、填充色跟着插值。
void main() {
  const fillA = Color(0xFFE9E1D3);
  const fillB = Color(0xFFD9C2C7);

  CleanGapOutlineInputBorder border({
    Color fillColor = fillA,
    Color sideColor = Colors.black,
    double width = 1.0,
    double radius = 10.0,
    double gapPadding = 6.0,
  }) {
    return CleanGapOutlineInputBorder(
      borderSide: BorderSide(color: sideColor, width: width),
      borderRadius: BorderRadius.circular(radius),
      gapPadding: gapPadding,
      fillColor: fillColor,
    );
  }

  test('lerpFrom：两个 CleanGap 之间插值，全程保持 CleanGap、填充色跟着插值', () {
    final a = border(fillColor: fillA, sideColor: Colors.black);
    final b = border(fillColor: fillB, sideColor: Colors.white, width: 2.0);
    final mid = a.lerpFrom(b, 0.5);

    // 旧代码这里返回的是普通 OutlineInputBorder，测试直接失败
    expect(mid, isA<CleanGapOutlineInputBorder>());
    final midGap = mid as CleanGapOutlineInputBorder;
    expect(midGap.fillColor, Color.lerp(fillB, fillA, 0.5));
    expect(midGap.borderSide.width, 1.5);
    expect(midGap.borderSide.color, Color.lerp(Colors.white, Colors.black, 0.5));
  });

  test('lerpFrom：对端是普通 OutlineInputBorder 时，填充色从透明插值过来', () {
    final a = border(fillColor: fillA);
    final plain = OutlineInputBorder(
      borderSide: const BorderSide(color: Colors.black, width: 1.0),
      borderRadius: BorderRadius.circular(10),
    );
    final mid = a.lerpFrom(plain, 0.5);

    expect(mid, isA<CleanGapOutlineInputBorder>());
    expect(
      (mid as CleanGapOutlineInputBorder).fillColor,
      Color.lerp(Colors.transparent, fillA, 0.5),
    );
  });

  test('lerpTo：两个 CleanGap 之间插值，全程保持 CleanGap、填充色跟着插值', () {
    final a = border(fillColor: fillA);
    final b = border(fillColor: fillB);
    final mid = a.lerpTo(b, 0.5);

    expect(mid, isA<CleanGapOutlineInputBorder>());
    expect((mid as CleanGapOutlineInputBorder).fillColor, Color.lerp(fillA, fillB, 0.5));
  });

  test('scale：返回 CleanGap，填充色不变、圆角按比例缩', () {
    final a = border(fillColor: fillA, radius: 10.0);
    final scaled = a.scale(0.5);

    expect(scaled, isA<CleanGapOutlineInputBorder>());
    expect(scaled.fillColor, fillA);
    expect(scaled.borderRadius, BorderRadius.circular(5.0));
  });

  test('== 与 hashCode：只变填充色也算不相等（深浅切换才重绘）', () {
    final a = border(fillColor: fillA);
    final same = border(fillColor: fillA);
    final differentFill = border(fillColor: fillB);

    expect(a, equals(same));
    expect(a.hashCode, same.hashCode);
    expect(a == differentFill, isFalse, reason: '父类 == 不认 fillColor，这里必须认');
    expect(a.hashCode == differentFill.hashCode, isFalse);
  });

  test('copyWith：不传 fillColor 时保留原值，传了就覆盖', () {
    final a = border(fillColor: fillA);
    expect(a.copyWith().fillColor, fillA);
    expect(a.copyWith(fillColor: fillB).fillColor, fillB);
    expect(a.copyWith().borderSide, a.borderSide);
  });
}
