// home_screen.dart
// Protocol Vault — RYO's movement library.
// Nike Training Club–inspired layout with bold typography over protocol cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/app.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';
import 'package:ryo/domain/services/local_coach.dart';
import 'package:ryo/features/home/widgets/protocol_card.dart';
import 'package:ryo/features/settings/settings_screen.dart';

// Provider to track the active protocol
final activeProtocolProvider = StateProvider<Protocol>((ref) => protocols.first);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeProtocolProvider);

    return Scaffold(
      backgroundColor: context.ryoBg,
      body: CustomScrollView(
        slivers: [
          // ── Sticky header ─────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: context.ryoBg,
            expandedHeight: 0,
            pinned: true,
            snap: false,
            floating: true,
            titleSpacing: 24,
            title: const RyoBrandmark(subtitle: 'HOME · VAULT'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(Icons.tune_outlined, size: 24, color: context.ryoTextPrimary),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Hero greeting (elderly-friendly: clear, no overflow) ─────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Date line
                  Text(
                    _todayLabel(),
                    style: RyoTypography.micro.copyWith(
                      color: context.ryoTextMuted,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your Vault',
                    style: RyoTypography.display.copyWith(
                      fontSize: 32,
                      height: 1.1,
                      color: context.ryoTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a protocol, then open Mirror to begin.',
                    style: RyoTypography.body.copyWith(
                      fontSize: 14,
                      color: context.ryoTextSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // ── Quick stats strip ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  _QuickStat(
                    icon: Icons.layers_outlined,
                    label: '${protocols.length}',
                    sublabel: 'PROTOCOLS',
                  ),
                  const SizedBox(width: 10),
                  const _QuickStat(
                    icon: Icons.track_changes_outlined,
                    label: 'ROM',
                    sublabel: 'TRACKING',
                  ),
                  const SizedBox(width: 10),
                  const _QuickStat(
                    icon: Icons.health_and_safety_outlined,
                    label: 'MOH',
                    sublabel: 'PHYSIO CPG',
                  ),
                ],
              ),
            ),
          ),

          // ── Active protocol banner (tap to open Mirror) ───────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: _ActiveProtocolBanner(
              protocol: active,
              onTap: () {
                ref.read(requestedNavIndexProvider.notifier).state = 1;
              },
            ),
          ),

          // ── Section title ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Text(
                'ALL PROTOCOLS',
                style: RyoTypography.dataLabel.copyWith(color: context.ryoTextMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // ── Protocol grid ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: protocols.length,
              itemBuilder: (context, i) {
                final p = protocols[i];
                final isActive = active.id == p.id;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isActive
                        ? RyoDecorations.cyanGlow(blurRadius: 16)
                        : null,
                  ),
                  child: _ProtocolCardWithFeedback(
                    protocol: p,
                    isActive: isActive,
                    onTap: () {
                      ref.read(activeProtocolProvider.notifier).state = p;
                      ref.read(currentActivityProvider.notifier).state = p.id;
                      ref.read(requestedNavIndexProvider.notifier).state = 1; // switch to Mirror
                    },
                  ),
                );
              },
            ),
          ),

          // Bottom padding for the glass nav bar
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Protocol card with press scale feedback
// ---------------------------------------------------------------------------

class _ProtocolCardWithFeedback extends StatefulWidget {
  const _ProtocolCardWithFeedback({
    required this.protocol,
    required this.isActive,
    required this.onTap,
  });

  final Protocol protocol;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_ProtocolCardWithFeedback> createState() => _ProtocolCardWithFeedbackState();
}

class _ProtocolCardWithFeedbackState extends State<_ProtocolCardWithFeedback> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressing = true),
      onPointerUp: (_) => setState(() => _pressing = false),
      onPointerCancel: (_) => setState(() => _pressing = false),
      child: AnimatedScale(
        scale: _pressing ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ProtocolCard(
          protocol: widget.protocol,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active protocol banner — full-width highlighted card (tap → Mirror)
// ---------------------------------------------------------------------------

class _ActiveProtocolBanner extends StatelessWidget {
  const _ActiveProtocolBanner({required this.protocol, this.onTap});

  final Protocol protocol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 80,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: context.ryoSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: protocol.accentColor.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Row(
              children: [
                const SizedBox(width: 20),
                Icon(protocol.icon, size: 28, color: protocol.accentColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ACTIVE PROTOCOL',
                        style: RyoTypography.micro.copyWith(color: protocol.accentColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        protocol.name,
                        style: RyoTypography.title.copyWith(
                          color: context.ryoTextPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: context.ryoTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _todayLabel() {
  const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final now = DateTime.now();
  return '${days[now.weekday - 1]}  ·  ${now.day} ${months[now.month - 1]} ${now.year}';
}

// ---------------------------------------------------------------------------
// Quick stat tile — compact metric on the home landing page
// ---------------------------------------------------------------------------

class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.icon,
    required this.label,
    required this.sublabel,
  });

  final IconData icon;
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.isElderlyMode ? Colors.transparent : context.ryoCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: context.isElderlyMode
                ? context.ryoAccent.withValues(alpha: 0.25)
                : context.ryoDivider,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.ryoAccent),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                Text(
                  label,
                  style: RyoTypography.title.copyWith(
                    color: context.ryoTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sublabel,
                  style: RyoTypography.micro.copyWith(
                    color: context.ryoTextMuted,
                    fontSize: 9,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}
