import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    this.size = 32,
    this.color,
    this.semanticLabel = 'MyLifeGraph',
    super.key,
  });

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Explicit colors retain the scalable monochrome mark for themed controls.
    if (color == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/brand/app_icon_glass.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
        ),
      );
    }
    return SvgPicture.asset(
      'assets/brand/app_brand_mark.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
      colorFilter: ColorFilter.mode(
        color ?? Theme.of(context).colorScheme.primary,
        BlendMode.srcIn,
      ),
    );
  }
}
