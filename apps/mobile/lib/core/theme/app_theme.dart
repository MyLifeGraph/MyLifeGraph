import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import 'app_motion_tokens.dart';
import 'app_visual_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        tokens: AppVisualTokens.dark,
      );

  static ThemeData get light => _build(
        brightness: Brightness.light,
        tokens: AppVisualTokens.light,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppVisualTokens tokens,
  }) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: tokens.brand,
      onPrimary: tokens.onBrand,
      primaryContainer:
          dark ? const Color(0xFF173B32) : const Color(0xFFD9F3EA),
      onPrimaryContainer:
          dark ? const Color(0xFFB9F6E3) : const Color(0xFF075F50),
      secondary: tokens.info,
      onSecondary: dark ? const Color(0xFF12254C) : const Color(0xFFFFFFFF),
      secondaryContainer: tokens.infoSurface,
      onSecondaryContainer: tokens.info,
      tertiary: tokens.attention,
      onTertiary: dark ? const Color(0xFF3C2B00) : const Color(0xFFFFFFFF),
      tertiaryContainer: tokens.attentionSurface,
      onTertiaryContainer: tokens.attention,
      error: tokens.danger,
      onError: dark ? const Color(0xFF450905) : const Color(0xFFFFFFFF),
      errorContainer: tokens.dangerSurface,
      onErrorContainer: tokens.danger,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.focus,
      outlineVariant: tokens.outlineSoft,
      shadow: tokens.shadow,
      scrim: const Color(0xFF000000),
      inverseSurface: dark ? tokens.textPrimary : const Color(0xFF26312D),
      onInverseSurface: dark ? tokens.background : const Color(0xFFF2F6F3),
      inversePrimary: dark ? const Color(0xFF087A65) : const Color(0xFF69E0BD),
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: tokens.background,
      surfaceContainerLow: tokens.surface,
      surfaceContainer: tokens.surfaceSubtle,
      surfaceContainerHigh: tokens.surfaceRaised,
      surfaceContainerHighest: tokens.surfaceInteractive,
    );
    final textTheme = _textTheme(tokens);
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.focus, width: 2);
      }
      return null;
    });
    final interactionOverlay = _interactionOverlay(tokens.brand);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.background,
      canvasColor: tokens.background,
      fontFamily: 'InstrumentSans',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: tokens.focus.withValues(alpha: dark ? 0.34 : 0.24),
      hoverColor: tokens.brand.withValues(alpha: 0.08),
      disabledColor: tokens.textSecondary.withValues(alpha: 0.42),
      extensions: [
        const AppMotionTokens(),
        tokens,
      ],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: textTheme.titleLarge,
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: tokens.surfaceSubtle,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: textTheme.bodyMedium,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: tokens.brand,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary.withValues(alpha: 0.82),
        ),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: tokens.danger),
        errorMaxLines: 3,
        border: _inputBorder(tokens.focus),
        enabledBorder: _inputBorder(tokens.focus),
        focusedBorder: _inputBorder(tokens.focus, width: 2),
        errorBorder: _inputBorder(tokens.danger),
        focusedErrorBorder: _inputBorder(tokens.danger, width: 2),
        disabledBorder: _inputBorder(tokens.outlineSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.onBrand.withValues(alpha: 0.62)
                : tokens.onBrand,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.brand.withValues(alpha: 0.42)
                : tokens.brand,
          ),
          overlayColor: _interactionOverlay(tokens.onBrand),
          side: focusSide,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
          animationDuration: const Duration(milliseconds: 120),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.textSecondary.withValues(alpha: 0.48)
                : tokens.textPrimary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? tokens.surfaceInteractive
                : Colors.transparent,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.focus, width: 2);
            }
            return BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? tokens.outlineSoft
                  : tokens.focus,
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          overlayColor: interactionOverlay,
          animationDuration: const Duration(milliseconds: 120),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.textSecondary.withValues(alpha: 0.48)
                : tokens.brand,
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          side: focusSide,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
          overlayColor: interactionOverlay,
          animationDuration: const Duration(milliseconds: 120),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? tokens.textSecondary.withValues(alpha: 0.42)
                : tokens.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? tokens.surfaceInteractive
                : Colors.transparent,
          ),
          minimumSize: const WidgetStatePropertyAll(Size.square(44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
          side: focusSide,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          overlayColor: interactionOverlay,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.brand,
        foregroundColor: tokens.onBrand,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.surfaceInteractive,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? tokens.textPrimary
                : tokens.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? tokens.brand
                : tokens.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.surfaceInteractive,
        selectedIconTheme: IconThemeData(color: tokens.brand),
        unselectedIconTheme: IconThemeData(color: tokens.textSecondary),
        selectedLabelTextStyle: textTheme.labelLarge,
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? tokens.onBrand
                : tokens.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? tokens.brand
                : tokens.surface,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? tokens.focus
                  : tokens.outlineSoft,
              width: states.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          overlayColor: interactionOverlay,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surface,
        selectedColor: tokens.surfaceInteractive,
        disabledColor: tokens.surfaceSubtle,
        side: BorderSide(color: tokens.outlineSoft),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: tokens.textPrimary,
        ),
        checkmarkColor: tokens.brand,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minTileHeight: 52,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.onBrand
              : tokens.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.brand
              : tokens.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? tokens.focus
              : tokens.outlineSoft,
        ),
        trackOutlineWidth: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? 2 : 1,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.brand
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(tokens.onBrand),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? tokens.focus
                : tokens.textSecondary,
            width: states.contains(WidgetState.focused) ? 2 : 1.5,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.brand
              : tokens.textSecondary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: tokens.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        modalBackgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: tokens.textSecondary,
        showDragHandle: true,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? tokens.surfaceInteractive : const Color(0xFF26312D),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFF2F6F3),
        ),
        actionTextColor: const Color(0xFF69E0BD),
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.brand,
        linearTrackColor: tokens.surfaceRaised,
        circularTrackColor: tokens.surfaceRaised,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: tokens.brand,
        inactiveTrackColor: tokens.surfaceRaised,
        thumbColor: tokens.brand,
        overlayColor: tokens.brand.withValues(alpha: 0.12),
        valueIndicatorColor:
            dark ? tokens.surfaceInteractive : const Color(0xFF26312D),
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: const Color(0xFFF2F6F3),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: tokens.surfaceSubtle,
        headerForegroundColor: tokens.textPrimary,
        todayForegroundColor: WidgetStatePropertyAll(tokens.brand),
        todayBorder: BorderSide(color: tokens.brand),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.onBrand
              : tokens.textPrimary,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.brand
              : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: tokens.surface,
        hourMinuteColor: tokens.surfaceSubtle,
        hourMinuteTextColor: tokens.textPrimary,
        dayPeriodColor: tokens.surfaceSubtle,
        dayPeriodTextColor: tokens.textPrimary,
        dialBackgroundColor: tokens.surfaceSubtle,
        dialHandColor: tokens.brand,
        dialTextColor: tokens.textPrimary,
        entryModeIconColor: tokens.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(AppRadii.pill),
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 8 : 5,
        ),
        thumbColor: WidgetStatePropertyAll(
          tokens.textSecondary.withValues(alpha: 0.55),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? tokens.surfaceInteractive : const Color(0xFF26312D),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: const Color(0xFFF2F6F3),
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  static TextTheme _textTheme(AppVisualTokens tokens) {
    TextStyle style({
      required double size,
      required double height,
      required FontWeight weight,
      Color? color,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontFamily: 'InstrumentSans',
        color: color ?? tokens.textPrimary,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      displaySmall: style(
        size: 40,
        height: 46 / 40,
        weight: FontWeight.w700,
        letterSpacing: -1.1,
      ),
      headlineLarge: style(
        size: 36,
        height: 42 / 36,
        weight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: style(
        size: 32,
        height: 36 / 32,
        weight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineSmall: style(
        size: 24,
        height: 29 / 24,
        weight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: style(
        size: 18,
        height: 23 / 18,
        weight: FontWeight.w600,
        letterSpacing: -0.15,
      ),
      titleMedium: style(
        size: 16,
        height: 22 / 16,
        weight: FontWeight.w600,
      ),
      titleSmall: style(
        size: 14,
        height: 20 / 14,
        weight: FontWeight.w600,
      ),
      bodyLarge: style(
        size: 16,
        height: 24 / 16,
        weight: FontWeight.w400,
      ),
      bodyMedium: style(
        size: 14,
        height: 21 / 14,
        weight: FontWeight.w400,
        color: tokens.textSecondary,
      ),
      bodySmall: style(
        size: 13,
        height: 18 / 13,
        weight: FontWeight.w400,
        color: tokens.textSecondary,
      ),
      labelLarge: style(
        size: 14,
        height: 18 / 14,
        weight: FontWeight.w600,
      ),
      labelMedium: style(
        size: 13,
        height: 16 / 13,
        weight: FontWeight.w600,
        color: tokens.textSecondary,
      ),
      labelSmall: style(
        size: 12,
        height: 15 / 12,
        weight: FontWeight.w600,
        color: tokens.textSecondary,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static WidgetStateProperty<Color?> _interactionOverlay(Color color) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.20);
      }
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: 0.08);
      }
      return null;
    });
  }
}
