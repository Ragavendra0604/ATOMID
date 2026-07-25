import 'package:flutter/material.dart';
import 'package:atomid/core/utils/responsive.dart';

class AdaptiveDialog extends StatelessWidget {
  final Widget? title;
  final Widget content;
  final List<Widget>? actions;

  const AdaptiveDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final width = ResponsiveHelper.getDialogWidth(context);

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: title,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () =>
                  Navigator.pop(context, false), // Default to false for cancel
            ),
          ),
          body: Padding(padding: const EdgeInsets.all(16.0), child: content),
          bottomNavigationBar: actions != null && actions!.isNotEmpty
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions!,
                    ),
                  ),
                )
              : null,
        ),
      );
    }

    return AlertDialog(
      title: title,
      content: SizedBox(width: width, child: content),
      actions: actions,
    );
  }
}
