import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import 'app_motion_tokens.dart';
import 'app_theme_effects.dart';
import 'app_visual_tokens.dart';

enum AppThemeId { dark, light, space }

class AppTheme {
  const AppTheme._();

  static final ThemeData dark = _build(_AppThemeDefinition.dark);

  static final ThemeData light = _build(_AppThemeDefinition.light);

  static final ThemeData space = _build(_AppThemeDefinition.space);

  static final ThemeData _spaceHighContrast = _build(
    _AppThemeDefinition.space,
    surfaceMaterialOverride: AppSurfaceMaterial.disabled,
  );

  static ThemeData resolve(AppThemeId id, {bool highContrast = false}) {
    if (highContrast && id == AppThemeId.space) return _spaceHighContrast;
    return switch (id) {
      AppThemeId.dark => dark,
      AppThemeId.light => light,
      AppThemeId.space => space,
    };
  }

  static ThemeData withoutAnimations(ThemeData theme) {
    ButtonStyle? reduced(ButtonStyle? style) => style?.copyWith(
          animationDuration: Duration.zero,
          splashFactory: NoSplash.splashFactory,
        );

    return theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      filledButtonTheme: FilledButtonThemeData(
        style: reduced(theme.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: reduced(theme.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: reduced(theme.textButtonTheme.style),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: reduced(theme.iconButtonTheme.style),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: reduced(theme.segmentedButtonTheme.style),
      ),
    );
  }

  static ThemeData _build(
    _AppThemeDefinition definition, {
    AppSurfaceMaterial? surfaceMaterialOverride,
  }) {
    final brightness = definition.brightness;
    final tokens = definition.tokens;
    final effects = surfaceMaterialOverride == null
        ? definition.effects
        : definition.effects.copyWith(
            surfaceMaterial: surfaceMaterialOverride,
          );
    final surfaceMaterial = effects.surfaceMaterial;
    final plainSurface = surfaceMaterial.plain(tokens.surface);
    final subtleSurface = surfaceMaterial.subtle(tokens.surfaceSubtle);
    final raisedSurface = surfaceMaterial.raised(tokens.surfaceRaised);
    final denseSurface = surfaceMaterial.dense(tokens.surface);
    final navigationSurface = surfaceMaterial.navigation(tokens.surface);
    final overlaySurface = surfaceMaterial.overlay(tokens.surface);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: tokens.brand,
      onPrimary: tokens.onBrand,
      primaryContainer: definition.primaryContainer,
      onPrimaryContainer: definition.onPrimaryContainer,
      secondary: tokens.info,
      onSecondary: definition.onSecondary,
      secondaryContainer: surfaceMaterial.semantic(tokens.infoSurface),
      onSecondaryContainer: tokens.info,
      tertiary: tokens.attention,
      onTertiary: definition.onTertiary,
      tertiaryContainer: surfaceMaterial.semantic(tokens.attentionSurface),
      onTertiaryContainer: tokens.attention,
      error: tokens.danger,
      onError: definition.onError,
      errorContainer: surfaceMaterial.semantic(tokens.dangerSurface),
      onErrorContainer: tokens.danger,
      surface: denseSurface,
      onSurface: tokens.textPrimary,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.focus,
      outlineVariant: tokens.outlineSoft,
      shadow: tokens.shadow,
      scrim: definition.scrim,
      inverseSurface: definition.inverseSurface,
      onInverseSurface: definition.onInverseSurface,
      inversePrimary: definition.inversePrimary,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: tokens.background,
      surfaceContainerLow: plainSurface,
      surfaceContainer: subtleSurface,
      surfaceContainerHigh: raisedSurface,
      surfaceContainerHighest: raisedSurface,
    );
    final textTheme = _textTheme(tokens);
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: tokens.focus, width: 2);
      }
      return null;
    });
    final interactionOverlay = WidgetStateProperty.resolveWith<Color?>(
      effects.controlOverlay,
    );
    final controlForegroundBuilder = _controlForegroundBuilder(effects);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: definition.scaffoldBackground,
      canvasColor: tokens.background,
      fontFamily: 'InstrumentSans',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: effects.splashFactory,
      splashColor: effects.splashColor,
      highlightColor: effects.highlightColor,
      focusColor: effects.focusColor,
      hoverColor: effects.hoverColor,
      disabledColor: tokens.textSecondary.withValues(alpha: 0.42),
      extensions: [
        const AppMotionTokens(),
        tokens,
        effects,
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
        color: subtleSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: _surfaceShape(AppRadii.md, effects),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.outlineSoft,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: denseSurface,
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
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => effects.filledControlOverlay(states, tokens.onBrand),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (!effects.interactionGlowEnabled) {
              return focusSide.resolve(states);
            }
            if (states.contains(WidgetState.disabled)) {
              return BorderSide.none;
            }
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.focus, width: 2);
            }
            if (states.contains(WidgetState.pressed)) {
              return BorderSide(
                color: tokens.focus.withValues(alpha: 0.88),
              );
            }
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(
                color: tokens.brand.withValues(alpha: 0.88),
              );
            }
            return BorderSide(
              color: tokens.textPrimary.withValues(alpha: 0.44),
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (!effects.interactionGlowEnabled ||
                states.contains(WidgetState.disabled)) {
              return 0;
            }
            if (states.contains(WidgetState.pressed)) return 1;
            if (states.contains(WidgetState.hovered)) return 6;
            return 2;
          }),
          shadowColor: effects.interactionGlowEnabled
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.transparent;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return tokens.focus.withValues(alpha: 0.36);
                  }
                  if (states.contains(WidgetState.focused)) {
                    return tokens.focus.withValues(alpha: 0.48);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return tokens.brand.withValues(alpha: 0.55);
                  }
                  return effects.primaryControlIdleGlowColor;
                })
              : null,
          animationDuration: const Duration(milliseconds: 120),
          splashFactory: effects.splashFactory,
          foregroundBuilder: controlForegroundBuilder,
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
            if (effects.interactionGlowEnabled &&
                states.contains(WidgetState.pressed)) {
              return BorderSide(color: tokens.focus);
            }
            if (effects.interactionGlowEnabled &&
                states.contains(WidgetState.hovered)) {
              return BorderSide(color: tokens.brand);
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
          elevation: effects.interactionGlowEnabled
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) return 0;
                  if (states.contains(WidgetState.pressed)) return 1;
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return 3;
                  }
                  return 0;
                })
              : null,
          shadowColor: effects.interactionGlowEnabled
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.transparent;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return tokens.focus.withValues(alpha: 0.38);
                  }
                  if (states.contains(WidgetState.focused)) {
                    return tokens.focus.withValues(alpha: 0.36);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return tokens.brand.withValues(alpha: 0.34);
                  }
                  return Colors.transparent;
                })
              : null,
          animationDuration: const Duration(milliseconds: 120),
          splashFactory: effects.splashFactory,
          foregroundBuilder: controlForegroundBuilder,
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
          splashFactory: effects.splashFactory,
          foregroundBuilder: controlForegroundBuilder,
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
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: tokens.focus, width: 2);
            }
            if (effects.interactionGlowEnabled &&
                states.contains(WidgetState.pressed)) {
              return BorderSide(color: tokens.focus);
            }
            if (effects.interactionGlowEnabled &&
                states.contains(WidgetState.hovered)) {
              return BorderSide(color: tokens.brand);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          overlayColor: interactionOverlay,
          elevation: effects.interactionGlowEnabled
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) return 0;
                  if (states.contains(WidgetState.pressed)) return 1;
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return 2;
                  }
                  return 0;
                })
              : null,
          shadowColor: effects.interactionGlowEnabled
              ? WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.transparent;
                  }
                  if (states.contains(WidgetState.pressed)) {
                    return tokens.focus.withValues(alpha: 0.36);
                  }
                  if (states.contains(WidgetState.focused)) {
                    return tokens.focus.withValues(alpha: 0.32);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return tokens.brand.withValues(alpha: 0.30);
                  }
                  return Colors.transparent;
                })
              : null,
          splashFactory: effects.splashFactory,
          foregroundBuilder: controlForegroundBuilder,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.brand,
        foregroundColor: tokens.onBrand,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        shape: _surfaceShape(AppRadii.lg, effects),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: navigationSurface,
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
        backgroundColor: navigationSurface,
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
                : denseSurface,
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
          splashFactory: effects.splashFactory,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: denseSurface,
        selectedColor: surfaceMaterial.dense(tokens.surfaceInteractive),
        disabledColor: subtleSurface,
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
              : raisedSurface,
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
        backgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: tokens.shadow,
        shape: _surfaceShape(AppRadii.lg, effects),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: overlaySurface,
        modalBackgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: tokens.textSecondary,
        showDragHandle: true,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
          side: _surfaceBorderSide(effects),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceMaterial.overlay(definition.snackBackground),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: definition.snackForeground,
        ),
        actionTextColor: definition.snackAction,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        shape: _surfaceShape(AppRadii.md, effects),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.brand,
        linearTrackColor: raisedSurface,
        circularTrackColor: raisedSurface,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: tokens.brand,
        inactiveTrackColor: raisedSurface,
        thumbColor: tokens.brand,
        overlayColor: tokens.brand.withValues(alpha: 0.12),
        valueIndicatorColor:
            surfaceMaterial.overlay(definition.valueIndicatorBackground),
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: definition.valueIndicatorForeground,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceMaterial.overlay(tokens.surfaceRaised),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyLarge,
        shape: _surfaceShape(AppRadii.md, effects),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            surfaceMaterial.overlay(tokens.surfaceRaised),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(_surfaceShape(AppRadii.md, effects)),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: surfaceMaterial.overlay(tokens.surfaceSubtle),
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
        shape: _surfaceShape(AppRadii.lg, effects),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: overlaySurface,
        hourMinuteColor: surfaceMaterial.overlay(tokens.surfaceSubtle),
        hourMinuteTextColor: tokens.textPrimary,
        dayPeriodColor: surfaceMaterial.overlay(tokens.surfaceSubtle),
        dayPeriodTextColor: tokens.textPrimary,
        dialBackgroundColor: surfaceMaterial.overlay(tokens.surfaceSubtle),
        dialHandColor: tokens.brand,
        dialTextColor: tokens.textPrimary,
        entryModeIconColor: tokens.textSecondary,
        shape: _surfaceShape(AppRadii.lg, effects),
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
          color: surfaceMaterial.overlay(definition.tooltipBackground),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: definition.tooltipForeground,
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

  static RoundedRectangleBorder _surfaceShape(
    double radius,
    AppThemeEffects effects,
  ) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: _surfaceBorderSide(effects),
    );
  }

  static BorderSide _surfaceBorderSide(AppThemeEffects effects) =>
      effects.surfaceOutlineColor.a > 0
          ? BorderSide(color: effects.surfaceOutlineColor)
          : BorderSide.none;

  static ButtonLayerBuilder? _controlForegroundBuilder(
    AppThemeEffects effects,
  ) {
    if (effects.controlPressedScale == 1) return null;
    return (context, states, child) => AnimatedScale(
          key: const ValueKey('space-control-foreground-scale'),
          scale: states.contains(WidgetState.pressed) &&
                  !states.contains(WidgetState.disabled)
              ? effects.controlPressedScale
              : 1,
          duration: context.motionTokens.selectionFor(context),
          curve: context.motionTokens.curve,
          child: child,
        );
  }
}

@immutable
class _AppThemeDefinition {
  const _AppThemeDefinition({
    required this.brightness,
    required this.tokens,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.onSecondary,
    required this.onTertiary,
    required this.onError,
    required this.scrim,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.scaffoldBackground,
    required this.snackBackground,
    required this.snackForeground,
    required this.snackAction,
    required this.valueIndicatorBackground,
    required this.valueIndicatorForeground,
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.effects,
  });

  final Brightness brightness;
  final AppVisualTokens tokens;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color onSecondary;
  final Color onTertiary;
  final Color onError;
  final Color scrim;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
  final Color scaffoldBackground;
  final Color snackBackground;
  final Color snackForeground;
  final Color snackAction;
  final Color valueIndicatorBackground;
  final Color valueIndicatorForeground;
  final Color tooltipBackground;
  final Color tooltipForeground;
  final AppThemeEffects effects;

  static final dark = _AppThemeDefinition(
    brightness: Brightness.dark,
    tokens: AppVisualTokens.dark,
    primaryContainer: const Color(0xFF173B32),
    onPrimaryContainer: const Color(0xFFB9F6E3),
    onSecondary: const Color(0xFF12254C),
    onTertiary: const Color(0xFF3C2B00),
    onError: const Color(0xFF450905),
    scrim: const Color(0xFF000000),
    inverseSurface: AppVisualTokens.dark.textPrimary,
    onInverseSurface: AppVisualTokens.dark.background,
    inversePrimary: const Color(0xFF087A65),
    scaffoldBackground: AppVisualTokens.dark.background,
    snackBackground: AppVisualTokens.dark.surfaceInteractive,
    snackForeground: const Color(0xFFF2F6F3),
    snackAction: const Color(0xFF69E0BD),
    valueIndicatorBackground: AppVisualTokens.dark.surfaceInteractive,
    valueIndicatorForeground: const Color(0xFFF2F6F3),
    tooltipBackground: AppVisualTokens.dark.surfaceInteractive,
    tooltipForeground: const Color(0xFFF2F6F3),
    effects: _standardEffects(
      tokens: AppVisualTokens.dark,
      focusOpacity: 0.34,
      accentSurfaceOpacity: 0.14,
    ),
  );

  static final light = _AppThemeDefinition(
    brightness: Brightness.light,
    tokens: AppVisualTokens.light,
    primaryContainer: const Color(0xFFD9F3EA),
    onPrimaryContainer: const Color(0xFF075F50),
    onSecondary: const Color(0xFFFFFFFF),
    onTertiary: const Color(0xFFFFFFFF),
    onError: const Color(0xFFFFFFFF),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFF26312D),
    onInverseSurface: const Color(0xFFF2F6F3),
    inversePrimary: const Color(0xFF69E0BD),
    scaffoldBackground: AppVisualTokens.light.background,
    snackBackground: const Color(0xFF26312D),
    snackForeground: const Color(0xFFF2F6F3),
    snackAction: const Color(0xFF69E0BD),
    valueIndicatorBackground: const Color(0xFF26312D),
    valueIndicatorForeground: const Color(0xFFF2F6F3),
    tooltipBackground: const Color(0xFF26312D),
    tooltipForeground: const Color(0xFFF2F6F3),
    effects: _standardEffects(
      tokens: AppVisualTokens.light,
      focusOpacity: 0.24,
      accentSurfaceOpacity: 0.09,
    ),
  );

  static final space = _AppThemeDefinition(
    brightness: Brightness.dark,
    tokens: AppVisualTokens.space,
    primaryContainer: const Color(0xFF20224A),
    onPrimaryContainer: const Color(0xFFDCD4FF),
    onSecondary: AppVisualTokens.space.infoSurface,
    onTertiary: AppVisualTokens.space.attentionSurface,
    onError: AppVisualTokens.space.dangerSurface,
    scrim: const Color(0xFF000000),
    inverseSurface: AppVisualTokens.space.textPrimary,
    onInverseSurface: AppVisualTokens.space.background,
    inversePrimary: AppVisualTokens.space.brand,
    scaffoldBackground: Colors.transparent,
    snackBackground: AppVisualTokens.space.surfaceInteractive,
    snackForeground: AppVisualTokens.space.textPrimary,
    snackAction: AppVisualTokens.space.brand,
    valueIndicatorBackground: AppVisualTokens.space.surfaceInteractive,
    valueIndicatorForeground: AppVisualTokens.space.textPrimary,
    tooltipBackground: AppVisualTokens.space.surfaceInteractive,
    tooltipForeground: AppVisualTokens.space.textPrimary,
    effects: AppThemeEffects(
      starfieldEnabled: true,
      interactionGlowEnabled: true,
      backdropPortraitAsset: 'assets/theme/space-deep-field-portrait.webp',
      backdropLandscapeAsset: 'assets/theme/space-deep-field-landscape.webp',
      backdropScrimOpacity: 0.40,
      splashFactory: InkRipple.splashFactory,
      splashColor: AppVisualTokens.space.brand.withValues(alpha: 0.22),
      highlightColor: AppVisualTokens.space.focus.withValues(alpha: 0.16),
      focusColor: AppVisualTokens.space.focus.withValues(alpha: 0.34),
      hoverColor: AppVisualTokens.space.brand.withValues(alpha: 0.10),
      focusOverlay: AppVisualTokens.space.focus.withValues(alpha: 0.22),
      pressedOverlay: AppVisualTokens.space.focus.withValues(alpha: 0.18),
      hoverOverlay: AppVisualTokens.space.brand.withValues(alpha: 0.10),
      surfacePressedOverlay:
          AppVisualTokens.space.focus.withValues(alpha: 0.18),
      quickActionPressedColor: Color.alphaBlend(
        AppVisualTokens.space.focus.withValues(alpha: 0.20),
        AppVisualTokens.space.brand,
      ),
      interactionGlowColor: AppVisualTokens.space.brand,
      primaryControlIdleGlowColor:
          AppVisualTokens.space.brand.withValues(alpha: 0.26),
      controlPressedScale: 0.96,
      interactiveSurfaceHoverLift: 1,
      navigationSignalColor: AppVisualTokens.space.brand,
      surfaceOutlineColor:
          AppVisualTokens.space.outlineSoft.withValues(alpha: 0.82),
      surfaceHoverOutlineColor:
          AppVisualTokens.space.brand.withValues(alpha: 0.58),
      raisedSurfaceGlowColor:
          AppVisualTokens.space.dataViolet.withValues(alpha: 0.22),
      accentSurfaceOpacity: 0.14,
      starCyan: AppVisualTokens.space.brand,
      starViolet: AppVisualTokens.space.dataViolet,
      starNeutral: AppVisualTokens.space.textPrimary,
      surfaceMaterial: const AppSurfaceMaterial(
        enabled: true,
        hudFrameEnabled: true,
        plainOpacity: 0.48,
        subtleOpacity: 0.52,
        raisedOpacity: 0.58,
        interactiveOpacity: 0.52,
        interactiveHoverOpacity: 0.58,
        interactivePressedOpacity: 0.60,
        denseOpacity: 0.60,
        semanticOpacity: 0.70,
        overlayOpacity: 0.82,
        navigationOpacity: 0.52,
        navigationBlurSigma: 8,
      ),
      backdropMotion: const AppBackdropMotion(
        enabled: true,
        cycle: Duration(seconds: 48),
        fixedPhase: 0.37,
        maxHorizontalDrift: 6,
        maxVerticalDrift: 4,
        baseScale: 1.04,
        scaleAmplitude: 0.004,
      ),
    ),
  );

  static AppThemeEffects _standardEffects({
    required AppVisualTokens tokens,
    required double focusOpacity,
    required double accentSurfaceOpacity,
  }) {
    return AppThemeEffects(
      starfieldEnabled: false,
      interactionGlowEnabled: false,
      backdropPortraitAsset: null,
      backdropLandscapeAsset: null,
      backdropScrimOpacity: 0,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: tokens.focus.withValues(alpha: focusOpacity),
      hoverColor: tokens.brand.withValues(alpha: 0.08),
      focusOverlay: tokens.brand.withValues(alpha: 0.20),
      pressedOverlay: tokens.brand.withValues(alpha: 0.14),
      hoverOverlay: tokens.brand.withValues(alpha: 0.08),
      surfacePressedOverlay: tokens.brand.withValues(alpha: 0.12),
      quickActionPressedColor: Color.lerp(tokens.brand, Colors.black, 0.12)!,
      interactionGlowColor: tokens.brand,
      primaryControlIdleGlowColor: Colors.transparent,
      controlPressedScale: 1,
      interactiveSurfaceHoverLift: 0,
      navigationSignalColor: Colors.transparent,
      surfaceOutlineColor: Colors.transparent,
      surfaceHoverOutlineColor: Colors.transparent,
      raisedSurfaceGlowColor: Colors.transparent,
      accentSurfaceOpacity: accentSurfaceOpacity,
      starCyan: tokens.brand,
      starViolet: tokens.dataViolet,
      starNeutral: tokens.textPrimary,
    );
  }
}
