import 'package:flutter/material.dart';
import 'package:atomid/core/theme/brand.dart';

class BrandTitle extends StatelessWidget {
  final String name;
  final TextStyle? textStyle;
  final double logoSize;
  final double spacing;

  const BrandTitle({
    super.key,
    required this.name,
    this.textStyle,
    this.logoSize = 32,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BrandMark(
          size: logoSize,
          padding: logoSize * 0.15,
        ),
        SizedBox(width: spacing),
        Flexible(
          child: Text(
            name,
            style: textStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
