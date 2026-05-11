import 'package:flutter/animation.dart';

/// Motion tokens for calm, healthcare-appropriate UI transitions.
abstract final class CareMotion {
  static const instant = Duration(milliseconds: 80);
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const guided = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 480);

  static const quickCurve = Curves.easeOut;
  static const standardCurve = Curves.easeInOut;
  static const guidedCurve = Curves.easeInOutCubic;
  static const slowCurve = Curves.easeOutCubic;
}
