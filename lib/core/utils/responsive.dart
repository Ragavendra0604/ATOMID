import 'package:flutter/material.dart';
import 'dart:math';

class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double maxFormWidth = 1200;
  static const double maxCardWidth = 350;
}

class ResponsiveHelper {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < ResponsiveBreakpoints.mobile;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= ResponsiveBreakpoints.mobile &&
      MediaQuery.of(context).size.width < ResponsiveBreakpoints.tablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= ResponsiveBreakpoints.tablet;

  /// Used for dialogs according to specs:
  /// Mobile: Full Screen Dialog (not handled here, handled by builder)
  /// Tablet: 60% Width
  /// Desktop: 40-60% Width
  /// Maximum: 800px
  static double getDialogWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return width; // usually handled by full screen dialog anyway
    }
    return min(width * 0.6, 800);
  }
}

class ResponsivePadding {
  static EdgeInsets getScreenPadding(BuildContext context) {
    if (ResponsiveHelper.isDesktop(context)) {
      return const EdgeInsets.all(32.0);
    } else if (ResponsiveHelper.isTablet(context)) {
      return const EdgeInsets.all(24.0);
    } else {
      return const EdgeInsets.all(16.0);
    }
  }
}

class ResponsiveSpacing {
  static double get sectionSpacing {
    return 24.0;
  }

  static double get elementSpacing {
    return 16.0;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context) mobileBuilder;
  final Widget Function(BuildContext context)? tabletBuilder;
  final Widget Function(BuildContext context) desktopBuilder;

  const ResponsiveBuilder({
    super.key,
    required this.mobileBuilder,
    this.tabletBuilder,
    required this.desktopBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ResponsiveBreakpoints.tablet) {
          return desktopBuilder(context);
        } else if (constraints.maxWidth >= ResponsiveBreakpoints.mobile) {
          return tabletBuilder != null
              ? tabletBuilder!(context)
              : desktopBuilder(
                  context,
                ); // Fallback to desktop if tablet not provided, or mobile? Usually fallback to mobile is safer but let's assume desktop for tablet space. Actually, fallback to mobile is more common if tablet is missing, but we will always provide them when needed.
        } else {
          return mobileBuilder(context);
        }
      },
    );
  }
}
