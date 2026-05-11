import 'package:flutter/material.dart';

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
          _CaroMark(state: state, colors: colors, compact: compact),
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
  const _CaroMark({
    required this.state,
    required this.colors,
    required this.compact,
  });

  final CaroState state;
  final _CaroColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 46.0 : 58.0;

    return AnimatedContainer(
      duration: CareMotion.standard,
      curve: CareMotion.standardCurve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.markBackground,
        borderRadius: BorderRadius.circular(size * 0.35),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.health_and_safety_outlined, color: colors.accent),
          Positioned(
            right: 8,
            bottom: 8,
            child: Icon(_stateIcon(state), size: 14, color: colors.accent),
          ),
        ],
      ),
    );
  }

  IconData _stateIcon(CaroState state) {
    return switch (state) {
      CaroState.neutral => Icons.favorite_border,
      CaroState.greeting => Icons.info_outline,
      CaroState.listening => Icons.hearing_outlined,
      CaroState.confirming => Icons.check_circle_outline,
      CaroState.concerned => Icons.error_outline,
      CaroState.simulation => Icons.science_outlined,
      CaroState.unavailable => Icons.wifi_off_outlined,
      CaroState.handoff => Icons.call_made_outlined,
    };
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
