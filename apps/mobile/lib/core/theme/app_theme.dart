import 'package:flutter/material.dart';

import '../constants/app_radii.dart';

class AppTheme {
  const AppTheme._();

  static const _darkBackground = Color(0xFF091014);
  static const _darkSurface = Color(0xFF10181E);
  static const _darkSurfaceLow = Color(0xFF131D24);
  static const _darkSurfaceContainer = Color(0xFF17222B);
  static const _darkSurfaceHigh = Color(0xFF1C2933);
  static const _darkSurfaceHighest = Color(0xFF22313C);
  static const _darkPrimary = Color(0xFF6EE7C8);
  static const _darkOnPrimary = Color(0xFF00382E);
  static const _darkPrimaryContainer = Color(0xFF123E35);
  static const _darkOnPrimaryContainer = Color(0xFFB4F6E5);
  static const _darkSecondary = Color(0xFFAFC6FF);
  static const _darkOnSecondary = Color(0xFF17305E);
  static const _darkSecondaryContainer = Color(0xFF243B68);
  static const _darkOnSecondaryContainer = Color(0xFFDAE4FF);
  static const _darkTertiary = Color(0xFFFFCA7A);
  static const _darkOnTertiary = Color(0xFF432B00);
  static const _darkText = Color(0xFFE6EDF1);
  static const _darkMuted = Color(0xFFAEBAC1);
  static const _darkOutline = Color(0xFF748187);
  static const _darkOutlineVariant = Color(0xFF2C3B44);

  static const _lightBackground = Color(0xFFF6F8F7);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceLow = Color(0xFFF0F4F2);
  static const _lightSurfaceContainer = Color(0xFFEAEFED);
  static const _lightSurfaceHigh = Color(0xFFE3EAE7);
  static const _lightSurfaceHighest = Color(0xFFDCE4E1);
  static const _lightPrimary = Color(0xFF006B5E);
  static const _lightOnPrimary = Color(0xFFFFFFFF);
  static const _lightPrimaryContainer = Color(0xFFC1F1E4);
  static const _lightOnPrimaryContainer = Color(0xFF00382F);
  static const _lightSecondary = Color(0xFF425F91);
  static const _lightOnSecondary = Color(0xFFFFFFFF);
  static const _lightSecondaryContainer = Color(0xFFD9E2FF);
  static const _lightOnSecondaryContainer = Color(0xFF0C2B5C);
  static const _lightTertiary = Color(0xFF795900);
  static const _lightOnTertiary = Color(0xFFFFFFFF);
  static const _lightText = Color(0xFF17211F);
  static const _lightMuted = Color(0xFF4B5C57);
  static const _lightOutline = Color(0xFF6D7C77);
  static const _lightOutlineVariant = Color(0xFFCAD5D1);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? _darkBackground : _lightBackground;
    final surface = dark ? _darkSurface : _lightSurface;
    final surfaceLow = dark ? _darkSurfaceLow : _lightSurfaceLow;
    final surfaceContainer =
        dark ? _darkSurfaceContainer : _lightSurfaceContainer;
    final surfaceHigh = dark ? _darkSurfaceHigh : _lightSurfaceHigh;
    final surfaceHighest = dark ? _darkSurfaceHighest : _lightSurfaceHighest;
    final primary = dark ? _darkPrimary : _lightPrimary;
    final onPrimary = dark ? _darkOnPrimary : _lightOnPrimary;
    final primaryContainer =
        dark ? _darkPrimaryContainer : _lightPrimaryContainer;
    final onPrimaryContainer =
        dark ? _darkOnPrimaryContainer : _lightOnPrimaryContainer;
    final secondary = dark ? _darkSecondary : _lightSecondary;
    final onSecondary = dark ? _darkOnSecondary : _lightOnSecondary;
    final secondaryContainer =
        dark ? _darkSecondaryContainer : _lightSecondaryContainer;
    final onSecondaryContainer =
        dark ? _darkOnSecondaryContainer : _lightOnSecondaryContainer;
    final tertiary = dark ? _darkTertiary : _lightTertiary;
    final onTertiary = dark ? _darkOnTertiary : _lightOnTertiary;
    final onSurface = dark ? _darkText : _lightText;
    final onSurfaceVariant = dark ? _darkMuted : _lightMuted;
    final outline = dark ? _darkOutline : _lightOutline;
    final outlineVariant = dark ? _darkOutlineVariant : _lightOutlineVariant;

    final seeded = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final colorScheme = seeded.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      surfaceContainerLowest: background,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    final textTheme = _textTheme(
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'Roboto',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: primary.withValues(alpha: dark ? 0.30 : 0.22),
      hoverColor: primary.withValues(alpha: 0.08),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surfaceLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium,
        helperStyle: textTheme.bodySmall,
        errorMaxLines: 3,
        border: _inputBorder(outline),
        enabledBorder: _inputBorder(outline),
        focusedBorder: _inputBorder(primary, width: 2),
        errorBorder: _inputBorder(colorScheme.error),
        focusedErrorBorder: _inputBorder(colorScheme.error, width: 2),
        disabledBorder: _inputBorder(outlineVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: _interactionOverlay(onPrimary),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: _interactionOverlay(primary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: _interactionOverlay(primary),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurfaceVariant,
          minimumSize: const Size.square(44),
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: _interactionOverlay(primary),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? onSurface
                : onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelLarge,
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: onSurfaceVariant,
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
                ? onPrimaryContainer
                : onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? primaryContainer
                : Colors.transparent,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          overlayColor: _interactionOverlay(primary),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceContainer,
        selectedColor: primaryContainer,
        disabledColor: surfaceLow,
        side: BorderSide(color: outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: onPrimaryContainer,
        ),
        checkmarkColor: onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceVariant,
        textColor: onSurface,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          side: BorderSide(color: outlineVariant),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? _darkSurfaceHighest : _lightText,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: dark ? _darkText : _lightSurface,
        ),
        actionTextColor: _darkPrimary,
        elevation: 8,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceHighest,
        circularTrackColor: surfaceHighest,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(AppRadii.pill),
        thickness: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? 8 : 5,
        ),
        thumbColor: WidgetStatePropertyAll(
          onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? _darkSurfaceHighest : _lightText,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: dark ? _darkText : _lightSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  static TextTheme _textTheme({
    required Color onSurface,
    required Color onSurfaceVariant,
  }) {
    return TextTheme(
      displaySmall: TextStyle(
        color: onSurface,
        fontSize: 42,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
      ),
      headlineLarge: TextStyle(
        color: onSurface,
        fontSize: 34,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: onSurface,
        fontSize: 27,
        height: 1.16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
      ),
      headlineSmall: TextStyle(
        color: onSurface,
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleLarge: TextStyle(
        color: onSurface,
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      titleMedium: TextStyle(
        color: onSurface,
        fontSize: 16,
        height: 1.32,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: TextStyle(
        color: onSurface,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: onSurface,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: onSurfaceVariant,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: onSurfaceVariant,
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: onSurface,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: onSurfaceVariant,
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: onSurfaceVariant,
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
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
        return color.withValues(alpha: 0.24);
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
