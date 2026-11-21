// adaptive_scaffold.dart
// Platform-aware scaffold:
//   macOS  → permanent left NavigationRail (thin icons, no labels)
//   Mobile → adaptive bottom nav bar — dark glass when dark, white pill when elderly

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ryo/core/theme/ryo_theme.dart';

// ---------------------------------------------------------------------------
// Nav destinations config
// ---------------------------------------------------------------------------

class _NavDest {
  const _NavDest({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _NavDest(
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
    label: 'Home',
  ),
  _NavDest(
    icon: Icons.view_in_ar_outlined,
    selectedIcon: Icons.view_in_ar_rounded,
    label: 'Mirror',
  ),
  _NavDest(
    icon: Icons.graphic_eq_outlined,
    selectedIcon: Icons.graphic_eq_rounded,
    label: 'Coach',
  ),
  _NavDest(
    icon: Icons.show_chart_outlined,
    selectedIcon: Icons.show_chart_rounded,
    label: 'Stats',
  ),
];

// ---------------------------------------------------------------------------
// AdaptiveScaffold
// ---------------------------------------------------------------------------

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    return _isDesktop
        ? _DesktopLayout(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            body: body,
          )
        : _MobileLayout(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            body: body,
          );
  }
}

// ---------------------------------------------------------------------------
// Desktop — persistent left rail
// ---------------------------------------------------------------------------

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ryoBg,
      body: Row(
        children: [
          Container(
            width: 64,
            decoration: BoxDecoration(
              color: context.ryoSurface,
              border: Border(
                right: BorderSide(color: context.ryoDivider, width: 0.5),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'RYO',
                      style: TextStyle(
                        color: context.ryoTextMuted,
                        fontSize: 9,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Divider(indent: 16, endIndent: 16, color: context.ryoDivider),
                  const SizedBox(height: 16),
                  ..._destinations.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final dest = entry.value;
                    final isSelected = selectedIndex == idx;
                    return _RailItem(
                      icon: isSelected ? dest.selectedIcon : dest.icon,
                      label: dest.label,
                      isSelected: isSelected,
                      onTap: () => onDestinationSelected(idx),
                    );
                  }),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.ryoAccent;
    final muted = context.ryoTextMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? accent.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: isSelected ? accent : muted),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? accent : muted,
                fontSize: 7,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile — adaptive bottom nav bar
// ---------------------------------------------------------------------------

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isElderly = context.isElderlyMode;
    final accent = context.ryoAccent;

    return Scaffold(
      backgroundColor: context.ryoBg,
      extendBody: true,
      body: body,
      bottomNavigationBar: isElderly
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(
                    color: accent.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
              ),
              padding: EdgeInsets.only(
                top: 10,
                bottom: bottomPadding > 0 ? bottomPadding : 14,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _destinations.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final dest = entry.value;
                  final isSelected = selectedIndex == idx;
                  return _BottomNavItem(
                    icon: isSelected ? dest.selectedIcon : dest.icon,
                    label: dest.label,
                    isSelected: isSelected,
                    isElderly: true,
                    onTap: () => onDestinationSelected(idx),
                  );
                }).toList(),
              ),
            )
          : ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              top: 10,
              bottom: bottomPadding > 0 ? bottomPadding : 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _destinations.asMap().entries.map((entry) {
                final idx = entry.key;
                final dest = entry.value;
                final isSelected = selectedIndex == idx;
                return _BottomNavItem(
                  icon: isSelected ? dest.selectedIcon : dest.icon,
                  label: dest.label,
                  isSelected: isSelected,
                  isElderly: false,
                  onTap: () => onDestinationSelected(idx),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isElderly,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isElderly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.ryoAccent;
    final Color iconColor = isSelected ? accent : context.ryoTextMuted;

    return Semantics(
      label: label,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 18 : 12,
            vertical: 6,
          ),
          decoration: isSelected
              ? BoxDecoration(
                  color: accent.withValues(alpha: isElderly ? 0.10 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accent.withValues(alpha: isElderly ? 0.25 : 0.20),
                    width: 0.5,
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: isElderly ? 24 : 22, color: iconColor),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: isSelected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: accent,
                            fontSize: isElderly ? 14 : 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable Glassmorphism container widget
// ---------------------------------------------------------------------------

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.sigma = 20,
    this.padding,
    this.border,
    this.width,
    this.height,
  });

  final Widget child;
  final double borderRadius;
  final double sigma;
  final EdgeInsetsGeometry? padding;
  final Color? border;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: RyoDecorations.glass(
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global RYO brandmark header widget
// ---------------------------------------------------------------------------

class RyoBrandmark extends StatelessWidget {
  const RyoBrandmark({super.key, this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Text(
      subtitle != null ? 'RYO · $subtitle' : 'RYO · BIOMECHANICS',
      style: RyoTypography.brandmark.copyWith(
        color: context.ryoTextPrimary,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
