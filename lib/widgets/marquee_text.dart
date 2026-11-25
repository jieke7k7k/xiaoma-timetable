import 'package:flutter/material.dart';

/// 跑马灯文本（WB_SPEC_260，Neon 实现）。
///
/// 文字超宽时自动横向滚动（无缝循环），不超宽时静止渲染普通 [Text]。
/// 滚动速度恒定（逻辑像素/秒），两份文本之间隔开 [gap]。
/// 父组件频繁重建时：文字未变不触碰动画，文字变了从头开始滚动。
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 36.0,
    this.gap = 48.0,
  })  : assert(velocity > 0, 'velocity must be positive'),
        assert(gap >= 0, 'gap must be non-negative');

  final String text;
  final TextStyle? style;

  /// 滚动速度（逻辑像素 / 秒）
  final double velocity;

  /// 首尾两份文本之间的间隔（逻辑像素）
  final double gap;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _isScrolling = false;
  Duration _activeDuration = Duration.zero;
  bool _needsReset = false;

  bool _syncScheduled = false;
  bool _pendingShouldScroll = false;
  Duration _pendingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _needsReset = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSync({
    required bool shouldScroll,
    required double cycleWidth,
  }) {
    final targetDuration = shouldScroll
        ? Duration(
            milliseconds: (cycleWidth / widget.velocity * 1000)
                .round()
                .clamp(500, 600000),
          )
        : Duration.zero;

    final stateChanged = shouldScroll != _isScrolling ||
        (shouldScroll && targetDuration != _activeDuration) ||
        _needsReset;

    if (!stateChanged) return;

    _pendingShouldScroll = shouldScroll;
    _pendingDuration = targetDuration;

    if (_syncScheduled) return;
    _syncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;

      final reset = _needsReset;
      _needsReset = false;

      if (!_pendingShouldScroll) {
        if (_controller.isAnimating || _controller.value != 0.0) {
          _controller.stop();
          _controller.value = 0.0;
        }
        _isScrolling = false;
        _activeDuration = Duration.zero;
        return;
      }

      final durationChanged = _pendingDuration != _activeDuration;
      if (reset) {
        _controller.stop();
        _controller.value = 0.0;
      }

      if (durationChanged) {
        _controller.duration = _pendingDuration;
        _activeDuration = _pendingDuration;
      }

      if (reset || !_controller.isAnimating || durationChanged) {
        _controller.repeat();
      }
      _isScrolling = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        DefaultTextStyle.of(context).style.merge(widget.style);
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          _scheduleSync(shouldScroll: false, cycleWidth: 0);
          return Text(
            widget.text,
            style: effectiveStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout();
        final textWidth = painter.width;
        final textHeight = painter.height;
        painter.dispose();

        // S4-5：无障碍开启「移除动画」时停止滚动，回退为静态省略号文本
        final shouldScroll = !disableAnimations && textWidth > maxWidth + 0.5;
        final cycleWidth = textWidth + widget.gap;

        _scheduleSync(shouldScroll: shouldScroll, cycleWidth: cycleWidth);

        if (!shouldScroll) {
          return Text(
            widget.text,
            style: effectiveStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final singleText = Text(
          widget.text,
          style: effectiveStyle,
          maxLines: 1,
          softWrap: false,
        );

        final scrollingRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            singleText,
            SizedBox(width: widget.gap),
            ExcludeSemantics(child: singleText),
          ],
        );

        return SizedBox(
          width: maxWidth,
          height: textHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: textHeight,
              child: AnimatedBuilder(
                animation: _controller,
                child: scrollingRow,
                builder: (context, child) {
                  final offsetX =
                      _needsReset ? 0.0 : -_controller.value * cycleWidth;
                  return Transform.translate(
                    offset: Offset(offsetX, 0),
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
