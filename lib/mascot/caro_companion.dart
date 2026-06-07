import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../design_system/care_colors.dart';
import '../design_system/care_motion.dart';
import 'caro_state.dart';

/// Calm companion prompt used for orientation, empty states, and safe guidance.
class CaroCompanion extends StatelessWidget {
  const CaroCompanion({
    required this.state,
    required this.title,
    required this.message,
    this.compact = false,
    super.key,
  });

  final CaroState state;
  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final colors = _CaroColors.from(context, state);
    final content = Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CaroMark(state: state, compact: compact),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.foreground.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return content;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: CareMotion.slow,
      curve: CareMotion.slowCurve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: value,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}

class _CaroMark extends StatelessWidget {
  const _CaroMark({required this.state, required this.compact});

  final CaroState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 46.0 : 58.0;

    return CaroCharacter(state: state, size: size);
  }
}

/// Caro companion artwork used across auth, dashboard, and prompts.
class CaroCharacter extends StatefulWidget {
  const CaroCharacter({required this.state, required this.size, super.key});

  final CaroState state;
  final double size;

  @override
  State<CaroCharacter> createState() => _CaroCharacterState();
}

class _CaroCharacterState extends State<CaroCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!_runningInWidgetTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inWidgetTest = _runningInWidgetTest;
    if (widget.size >= 96 && !inWidgetTest) {
      return _Caro3DCharacter(state: widget.state, size: widget.size);
    }

    final colors = _CaroColors.from(context, widget.state);
    if (inWidgetTest) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _CaroCharacterPainter(
          state: widget.state,
          colors: colors,
          progress: 0,
        ),
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = reduceMotion ? 0.0 : _controller.value;
        final floatY = math.sin(progress * math.pi * 2) * widget.size * 0.025;
        return Transform.translate(
          offset: Offset(0, floatY),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _CaroCharacterPainter(
              state: widget.state,
              colors: colors,
              progress: progress,
            ),
          ),
        );
      },
    );
  }

  bool get _runningInWidgetTest {
    var running = false;
    assert(() {
      running = WidgetsBinding.instance.runtimeType.toString().contains(
        'AutomatedTest',
      );
      return true;
    }());
    return running;
  }
}

class _Caro3DCharacter extends StatefulWidget {
  const _Caro3DCharacter({required this.state, required this.size});

  final CaroState state;
  final double size;

  @override
  State<_Caro3DCharacter> createState() => _Caro3DCharacterState();
}

class _Caro3DCharacterState extends State<_Caro3DCharacter> {
  final Flutter3DController _controller = Flutter3DController();
  bool _loaded = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_runningInWidgetTest) {
      final colors = _CaroColors.from(context, widget.state);
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _CaroCharacterPainter(
          state: widget.state,
          colors: colors,
          progress: 0,
        ),
      );
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fallback = _CaroPaintedCharacter(
      state: widget.state,
      size: widget.size,
    );

    if (_failed) return fallback;

    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _loaded ? 1 : 0.01,
            duration: CareMotion.guided,
            curve: CareMotion.slowCurve,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.size * 0.18),
              child: Flutter3DViewer(
                src: kIsWeb
                    ? 'assets/assets/models/caro_agent.glb'
                    : 'assets/models/caro_agent.glb',
                controller: _controller,
                activeGestureInterceptor: false,
                enableTouch: false,
                progressBarColor: Colors.transparent,
                onLoad: (_) {
                  if (!mounted) return;
                  setState(() => _loaded = true);
                  if (!reduceMotion) {
                    _startModelMotion();
                  }
                },
                onError: (_) {
                  if (mounted) setState(() => _failed = true);
                },
              ),
            ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _loaded ? 0 : 1,
              duration: CareMotion.standard,
              child: fallback,
            ),
          ),
        ],
      ),
    );
  }

  void _startModelMotion() {
    try {
      _controller.setCameraTarget(0, 0.92, 0);
      _controller.setCameraOrbit(0, 72, 5.6);
      _controller.playAnimation(animationName: 'caro-breathe');
    } catch (_) {
      // The 3D controller reports loading races synchronously; the fallback
      // remains visible if the platform view cannot accept commands yet.
    }
  }
}

bool get _runningInWidgetTest {
  var running = false;
  assert(() {
    running = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    return true;
  }());
  return running;
}

class _CaroPaintedCharacter extends StatefulWidget {
  const _CaroPaintedCharacter({required this.state, required this.size});

  final CaroState state;
  final double size;

  @override
  State<_CaroPaintedCharacter> createState() => _CaroPaintedCharacterState();
}

class _CaroPaintedCharacterState extends State<_CaroPaintedCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (!_runningInWidgetTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    final colors = _CaroColors.from(context, widget.state);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = reduceMotion ? 0.0 : _controller.value;
        final floatY = math.sin(progress * math.pi * 2) * widget.size * 0.025;
        return Transform.translate(
          offset: Offset(0, floatY),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _CaroCharacterPainter(
              state: widget.state,
              colors: colors,
              progress: progress,
            ),
          ),
        );
      },
    );
  }
}

class _CaroCharacterPainter extends CustomPainter {
  const _CaroCharacterPainter({
    required this.state,
    required this.colors,
    required this.progress,
  });

  final CaroState state;
  final _CaroColors colors;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final accent = colors.accent;
    final urgent =
        state == CaroState.concerned || state == CaroState.simulation;
    final glowColor = urgent ? const Color(0xFFFF6B7A) : accent;
    final pulse = 0.5 + math.sin(progress * math.pi * 2) * 0.5;

    final shadowPaint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.045);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.50, s * 0.88),
        width: s * 0.66,
        height: s * 0.12,
      ),
      shadowPaint,
    );

    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.016
      ..color = glowColor.withValues(alpha: 0.12 + pulse * 0.10);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(s * 0.50, s * 0.49),
        width: s * 0.72,
        height: s * 0.84,
      ),
      math.pi * 1.08,
      math.pi * 1.24,
      false,
      haloPaint,
    );

    _paintEar(canvas, size, left: true);
    _paintEar(canvas, size, left: false);

    final bodyRect = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.52),
      width: s * 0.58,
      height: s * 0.78,
    );
    canvas.drawOval(
      bodyRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.32, -0.55),
          radius: 1.08,
          colors: const [
            Color(0xFF7595FF),
            Color(0xFF5D79F2),
            Color(0xFF405ED2),
          ],
        ).createShader(bodyRect),
    );
    canvas.drawOval(
      bodyRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.014
        ..color = Colors.white.withValues(alpha: 0.48),
    );

    _paintFurTexture(canvas, bodyRect, size);

    final bellyRect = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.58),
      width: s * 0.36,
      height: s * 0.50,
    );
    canvas.drawOval(
      bellyRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.18, -0.4),
          radius: 0.95,
          colors: const [
            Color(0xFFFFF8ED),
            Color(0xFFFFEAD3),
            Color(0xFFEBCBAE),
          ],
        ).createShader(bellyRect),
    );
    canvas.drawOval(
      bellyRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.01
        ..color = Colors.white.withValues(alpha: 0.62),
    );

    final blink = progress > 0.86 && progress < 0.90;
    final eyeHeight = blink ? s * 0.010 : s * 0.052;
    _paintEye(
      canvas,
      Offset(s * 0.43, s * 0.40),
      eyeHeight,
      const Color(0xFF171B22),
      s,
    );
    _paintEye(
      canvas,
      Offset(s * 0.57, s * 0.40),
      eyeHeight,
      const Color(0xFF171B22),
      s,
    );

    canvas.drawCircle(
      Offset(s * 0.5, s * 0.46),
      s * 0.034,
      Paint()..color = const Color(0xFF171B22),
    );
    final smile = Path()
      ..moveTo(s * 0.43, s * 0.51)
      ..quadraticBezierTo(s * 0.50, s * 0.57, s * 0.57, s * 0.51);
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF171B22),
    );

    _paintArm(canvas, size, left: true);
    _paintArm(canvas, size, left: false);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.40, s * 0.84),
        width: s * 0.17,
        height: s * 0.08,
      ),
      Paint()..color = const Color(0xFFEACCAE),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.60, s * 0.84),
        width: s * 0.17,
        height: s * 0.08,
      ),
      Paint()..color = const Color(0xFFEACCAE),
    );

    canvas.drawCircle(
      Offset(s * 0.5, s * 0.68),
      s * (0.060 + pulse * 0.006),
      Paint()
        ..color = glowColor.withValues(alpha: 0.66)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
    );
    _paintHeart(canvas, Offset(s * 0.5, s * 0.675), s * 0.044);

    canvas.drawCircle(
      Offset(s * (0.74 + math.sin(progress * math.pi * 2) * 0.018), s * 0.37),
      s * 0.045,
      Paint()..color = glowColor.withValues(alpha: 0.84),
    );
    canvas.drawCircle(
      Offset(s * 0.77, s * 0.32),
      s * 0.026,
      Paint()..color = const Color(0xFFFF7A8B).withValues(alpha: 0.9),
    );
  }

  void _paintEar(Canvas canvas, Size size, {required bool left}) {
    final s = size.width;
    final x = left ? s * 0.34 : s * 0.66;
    final rect = Rect.fromCenter(
      center: Offset(x, s * 0.20),
      width: s * 0.17,
      height: s * 0.19,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 0.9,
          colors: const [Color(0xFF7C98FF), Color(0xFF4D6FE6)],
        ).createShader(rect),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, s * 0.21),
        width: s * 0.08,
        height: s * 0.09,
      ),
      Paint()..color = const Color(0xFFFFEAD3).withValues(alpha: 0.92),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.010
        ..color = Colors.white.withValues(alpha: 0.50),
    );
  }

  void _paintEye(
    Canvas canvas,
    Offset center,
    double height,
    Color eyeColor,
    double s,
  ) {
    final rect = Rect.fromCenter(
      center: center,
      width: s * 0.052,
      height: height,
    );
    canvas.drawOval(rect, Paint()..color = eyeColor);
    if (height > s * 0.02) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(s * 0.010, -s * 0.010),
          width: s * 0.014,
          height: s * 0.014,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.76),
      );
    }
  }

  void _paintArm(Canvas canvas, Size size, {required bool left}) {
    final s = size.width;
    final start = left
        ? Offset(s * 0.28, s * 0.53)
        : Offset(s * 0.67, s * 0.43);
    final end = left ? Offset(s * 0.22, s * 0.66) : Offset(s * 0.33, s * 0.24);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        left ? s * 0.19 : s * 0.48,
        left ? s * 0.60 : s * 0.28,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.06
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF5575EC),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: end,
        width: s * (left ? 0.14 : 0.18),
        height: s * (left ? 0.11 : 0.15),
      ),
      Paint()..color = const Color(0xFFFFEAD3),
    );
    if (!left) {
      for (final offset in const [-0.045, 0.0, 0.045]) {
        canvas.drawCircle(
          end.translate(s * offset, -s * 0.035),
          s * 0.017,
          Paint()..color = const Color(0xFFEBCBAE),
        );
      }
    }
  }

  void _paintHeart(Canvas canvas, Offset center, double size) {
    final path = Path()
      ..moveTo(center.dx, center.dy + size * 0.45)
      ..cubicTo(
        center.dx - size,
        center.dy - size * 0.12,
        center.dx - size * 0.42,
        center.dy - size * 0.88,
        center.dx,
        center.dy - size * 0.28,
      )
      ..cubicTo(
        center.dx + size * 0.42,
        center.dy - size * 0.88,
        center.dx + size,
        center.dy - size * 0.12,
        center.dx,
        center.dy + size * 0.45,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  void _paintFurTexture(Canvas canvas, Rect bodyRect, Size size) {
    final s = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.16);
    for (var i = 0; i < 34; i++) {
      final t = i / 33;
      final x = bodyRect.left + bodyRect.width * (0.12 + 0.76 * t);
      final y =
          bodyRect.top +
          bodyRect.height * (0.24 + 0.55 * math.sin(t * math.pi));
      final path = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + math.sin(i * 1.7) * s * 0.018,
          y + s * 0.045,
          x + math.cos(i * 1.2) * s * 0.014,
          y + s * 0.075,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaroCharacterPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.state != state ||
        oldDelegate.colors != colors;
  }
}

class _CaroColors {
  const _CaroColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.accent,
    required this.markBackground,
  });

  final Color background;
  final Color foreground;
  final Color border;
  final Color accent;
  final Color markBackground;

  static _CaroColors from(BuildContext context, CaroState state) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final border = scheme.outline.withValues(alpha: dark ? 0.55 : 0.85);

    final accent = switch (state) {
      CaroState.confirming =>
        dark ? CareColors.statusNormalDark : CareColors.statusNormal,
      CaroState.concerned =>
        dark ? CareColors.statusCautionDark : CareColors.statusCaution,
      CaroState.simulation =>
        dark ? CareColors.statusSimulationDark : CareColors.statusSimulation,
      CaroState.unavailable =>
        dark ? CareColors.statusDisabledDark : CareColors.statusDisabled,
      CaroState.handoff =>
        dark ? CareColors.statusInfoDark : CareColors.statusInfo,
      _ => scheme.primary,
    };

    return _CaroColors(
      background: dark ? CareColors.surfaceSoftDark : CareColors.surfaceSoft,
      foreground: scheme.onSecondaryContainer,
      border: border,
      accent: accent,
      markBackground: accent.withValues(alpha: dark ? 0.18 : 0.12),
    );
  }
}
