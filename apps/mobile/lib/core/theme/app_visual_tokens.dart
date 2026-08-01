import 'package:flutter/material.dart';

@immutable
class AppVisualTokens extends ThemeExtension<AppVisualTokens> {
  const AppVisualTokens({
    required this.background,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceRaised,
    required this.surfaceInteractive,
    required this.textPrimary,
    required this.textSecondary,
    required this.brand,
    required this.onBrand,
    required this.focus,
    required this.outlineSoft,
    required this.info,
    required this.infoSurface,
    required this.attention,
    required this.attentionSurface,
    required this.danger,
    required this.dangerSurface,
    required this.success,
    required this.successSurface,
    required this.dataBlue,
    required this.dataViolet,
    required this.dataCoral,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceRaised;
  final Color surfaceInteractive;
  final Color textPrimary;
  final Color textSecondary;
  final Color brand;
  final Color onBrand;
  final Color focus;
  final Color outlineSoft;
  final Color info;
  final Color infoSurface;
  final Color attention;
  final Color attentionSurface;
  final Color danger;
  final Color dangerSurface;
  final Color success;
  final Color successSurface;
  final Color dataBlue;
  final Color dataViolet;
  final Color dataCoral;
  final Color shadow;

  static const dark = AppVisualTokens(
    background: Color(0xFF08110F),
    surface: Color(0xFF101A17),
    surfaceSubtle: Color(0xFF15221E),
    surfaceRaised: Color(0xFF1A2924),
    surfaceInteractive: Color(0xFF1D302A),
    textPrimary: Color(0xFFF2F6F3),
    textSecondary: Color(0xFFA8B6B0),
    brand: Color(0xFF69E0BD),
    onBrand: Color(0xFF07352B),
    focus: Color(0xFF9AAEA6),
    outlineSoft: Color(0xFF2B3A35),
    info: Color(0xFF9CB7FF),
    infoSurface: Color(0xFF1B2944),
    attention: Color(0xFFF2C470),
    attentionSurface: Color(0xFF342918),
    danger: Color(0xFFFF8E86),
    dangerSurface: Color(0xFF3B201F),
    success: Color(0xFF82DE9A),
    successSurface: Color(0xFF183322),
    dataBlue: Color(0xFF75A7FF),
    dataViolet: Color(0xFFC8A5FF),
    dataCoral: Color(0xFFFF9E86),
    shadow: Color(0xB3000000),
  );

  static const light = AppVisualTokens(
    background: Color(0xFFF6F6F1),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFEEF2ED),
    surfaceRaised: Color(0xFFE7ECE7),
    surfaceInteractive: Color(0xFFE1E9E3),
    textPrimary: Color(0xFF15201C),
    textSecondary: Color(0xFF53625C),
    brand: Color(0xFF087A65),
    onBrand: Color(0xFFFFFFFF),
    focus: Color(0xFF687B73),
    outlineSoft: Color(0xFFD5DDD8),
    info: Color(0xFF3F6399),
    infoSurface: Color(0xFFE7EEFC),
    attention: Color(0xFF7A5700),
    attentionSurface: Color(0xFFFFF1CF),
    danger: Color(0xFFB23B36),
    dangerSurface: Color(0xFFFFE9E6),
    success: Color(0xFF1D7045),
    successSurface: Color(0xFFE2F3E7),
    dataBlue: Color(0xFF416BA5),
    dataViolet: Color(0xFF72569A),
    dataCoral: Color(0xFF9A5547),
    shadow: Color(0x26081410),
  );

  static const space = AppVisualTokens(
    background: Color(0xFF070814),
    surface: Color(0xFF101329),
    surfaceSubtle: Color(0xFF171A38),
    surfaceRaised: Color(0xFF20244A),
    surfaceInteractive: Color(0xFF292E5C),
    textPrimary: Color(0xFFF6F3FF),
    textSecondary: Color(0xFFD4CFEA),
    brand: Color(0xFF67E8F9),
    onBrand: Color(0xFF07272C),
    focus: Color(0xFFC4B5FD),
    outlineSoft: Color(0xFF353B68),
    info: Color(0xFFA5B4FC),
    infoSurface: Color(0xFF1D254A),
    attention: Color(0xFFF6C76E),
    attentionSurface: Color(0xFF352A18),
    danger: Color(0xFFFF8E9E),
    dangerSurface: Color(0xFF3B1D2A),
    success: Color(0xFF7EE2B8),
    successSurface: Color(0xFF14342D),
    dataBlue: Color(0xFF6CB6FF),
    dataViolet: Color(0xFFC4A7FF),
    dataCoral: Color(0xFFFF9CA8),
    shadow: Color(0xC4070814),
  );

  @override
  AppVisualTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceRaised,
    Color? surfaceInteractive,
    Color? textPrimary,
    Color? textSecondary,
    Color? brand,
    Color? onBrand,
    Color? focus,
    Color? outlineSoft,
    Color? info,
    Color? infoSurface,
    Color? attention,
    Color? attentionSurface,
    Color? danger,
    Color? dangerSurface,
    Color? success,
    Color? successSurface,
    Color? dataBlue,
    Color? dataViolet,
    Color? dataCoral,
    Color? shadow,
  }) {
    return AppVisualTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceInteractive: surfaceInteractive ?? this.surfaceInteractive,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      focus: focus ?? this.focus,
      outlineSoft: outlineSoft ?? this.outlineSoft,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
      attention: attention ?? this.attention,
      attentionSurface: attentionSurface ?? this.attentionSurface,
      danger: danger ?? this.danger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      dataBlue: dataBlue ?? this.dataBlue,
      dataViolet: dataViolet ?? this.dataViolet,
      dataCoral: dataCoral ?? this.dataCoral,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppVisualTokens lerp(AppVisualTokens? other, double t) {
    if (other == null) return this;
    return AppVisualTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceInteractive:
          Color.lerp(surfaceInteractive, other.surfaceInteractive, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      attentionSurface:
          Color.lerp(attentionSurface, other.attentionSurface, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      dataBlue: Color.lerp(dataBlue, other.dataBlue, t)!,
      dataViolet: Color.lerp(dataViolet, other.dataViolet, t)!,
      dataCoral: Color.lerp(dataCoral, other.dataCoral, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppVisualTokensContext on BuildContext {
  AppVisualTokens get visualTokens {
    final theme = Theme.of(this);
    return theme.extension<AppVisualTokens>() ??
        (theme.brightness == Brightness.dark
            ? AppVisualTokens.dark
            : AppVisualTokens.light);
  }
}
