import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LogoVariant {
  full,
  icon,
  wordmark,
  horizontal,
}

class AppLogo extends StatelessWidget {
  final double size;
  final LogoVariant variant;
  final bool forceDark;
  final bool forceLight;

  const AppLogo({
    super.key,
    this.size = 64,
    this.variant = LogoVariant.full,
    this.forceDark = false,
    this.forceLight = false,
  });

  String _getAssetPath(bool isDark) {
    final dark = forceDark || (isDark && !forceLight);
    switch (variant) {
      case LogoVariant.full:
        return dark
            ? 'assets/branding/pinoy_pos_logo_dark.svg'
            : 'assets/branding/pinoy_pos_logo.svg';
      case LogoVariant.icon:
        return dark
            ? 'assets/branding/pinoy_pos_icon_white.svg'
            : 'assets/branding/pinoy_pos_icon.svg';
      case LogoVariant.wordmark:
        return dark
            ? 'assets/branding/pinoy_pos_wordmark_white.svg'
            : 'assets/branding/pinoy_pos_wordmark.svg';
      case LogoVariant.horizontal:
        return dark
            ? 'assets/branding/pinoy_pos_logo_dark.svg'
            : 'assets/branding/pinoy_pos_logo_horizontal.svg';
    }
  }

  double get _aspectRatio {
    switch (variant) {
      case LogoVariant.full:
        return 200 / 250;
      case LogoVariant.icon:
        return 1.0;
      case LogoVariant.wordmark:
        return 200 / 60;
      case LogoVariant.horizontal:
        return 400 / 200;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetPath = _getAssetPath(isDark);

    double width;
    double height;
    if (_aspectRatio >= 1) {
      width = size;
      height = size / _aspectRatio;
    } else {
      height = size;
      width = size * _aspectRatio;
    }

    return SvgPicture.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  final double size;
  final bool forceDark;

  const AppIcon({
    super.key,
    this.size = 48,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppLogo(
      size: size,
      variant: LogoVariant.icon,
      forceDark: forceDark,
    );
  }
}