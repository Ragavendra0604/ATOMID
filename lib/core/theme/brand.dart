import 'package:flutter/material.dart';

/// Single source of truth for the Atomid mark.
///
/// Every surface that shows the logo — splash, app bar, invoice PDFs, price
/// tags — reads from here, so replacing the artwork is a one-file change.
class Brand {
  const Brand._();

  /// Primary mark: black atom with the AD monogram, on transparent.
  static const String logo = 'assets/images/logo.png';

  /// The mark reads as black line-art, so it needs a light ground on both
  /// themes rather than being tinted or inverted.
  static const Color logoGround = Color(0xFFFFFFFF);

  static const String appName = 'Atomid';
}

/// The logo on its light ground, sized and rounded consistently.
class BrandMark extends StatelessWidget {
  final double size;
  final double padding;

  const BrandMark({super.key, this.size = 96, this.padding = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Brand.logoGround,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: Image.asset(
        Brand.logo,
        fit: BoxFit.contain,
        // Falls back to a glyph if the artwork has not been dropped in yet,
        // so a missing asset never blocks startup.
        errorBuilder: (context, _, _) =>
            Icon(Icons.storefront, size: size * 0.6, color: Colors.black87),
      ),
    );
  }
}

/// Status colours that stay readable on whichever theme is showing.
///
/// The screens previously used raw `Colors.orange` / `Colors.red` /
/// `Colors.green` for status text. Those are tuned to be vivid, not legible:
/// `Colors.orange` on a white card measures about 2.4:1 against a WCAG AA
/// requirement of 4.5:1, which the accessibility guideline test in
/// `test/widget/accessibility_guidelines_test.dart` fails on.
///
/// A single darker shade would fix the light theme and break the dark one, so
/// these resolve against the current brightness: a deep shade on a light
/// ground, a light shade on a dark one.
extension StatusColors on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  /// Low stock, pending, awaiting action.
  Color get warningColor =>
      _isDark ? const Color(0xFFFFB74D) : const Color(0xFFB35309);

  /// Out of stock, overdue, failed.
  Color get dangerColor =>
      _isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);

  /// In stock, received, settled.
  Color get successColor =>
      _isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);

  /// Secondary text — the muted grey that had been hardcoded.
  Color get mutedColor => Theme.of(this).colorScheme.onSurfaceVariant;
}
