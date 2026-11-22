// settings_screen.dart
// Profile & preferences: senior mode toggle, doctor email, TTS language,
// default activity, skeleton sensitivity, voice coach, accessibility options.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/layout/adaptive_scaffold.dart';
import 'package:ryo/core/theme/ryo_theme.dart';
import 'package:ryo/domain/services/local_coach.dart';
import 'package:ryo/domain/services/settings_service.dart';
import 'package:ryo/features/home/home_screen.dart';
import 'package:ryo/features/home/widgets/protocol_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _doctorEmailController;

  @override
  void initState() {
    super.initState();
    _doctorEmailController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final email = ref.read(settingsProvider).doctorEmail;
    if (_doctorEmailController.text != email) {
      _doctorEmailController.text = email;
    }
  }

  @override
  void dispose() {
    _doctorEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    final bg = context.ryoBg;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        titleSpacing: 24,
        title: const RyoBrandmark(subtitle: 'SETTINGS'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: context.ryoTextMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
        children: [
          // ── Senior Friendly Mode — prominent toggle at top ──
          _ElderlyModeCard(
            enabled: settings.elderlyMode,
            onToggle: (v) =>
                ref.read(settingsProvider.notifier).setElderlyMode(v),
          ),

          const SizedBox(height: 24),
          const _SectionTitle(title: 'VOICE & ACTIVITY'),
          _AdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Voice coach language', style: context.ryoLabelStyle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ChoiceChip(
                      label: 'Malay (ms-MY)',
                      selected: settings.ttsLanguage == 'ms-MY',
                      onTap: () => ref.read(settingsProvider.notifier).setTtsLanguage('ms-MY'),
                    ),
                    const SizedBox(width: 8),
                    _ChoiceChip(
                      label: 'English',
                      selected: settings.ttsLanguage == 'en-US',
                      onTap: () => ref.read(settingsProvider.notifier).setTtsLanguage('en-US'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Default activity', style: context.ryoLabelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: protocols.map((p) {
                    final selected = settings.defaultActivity == p.id;
                    return _ChoiceChip(
                      label: p.name,
                      selected: selected,
                      onTap: () {
                        ref.read(settingsProvider.notifier).setDefaultActivity(p.id);
                        ref.read(currentActivityProvider.notifier).state = p.id;
                        ref.read(activeProtocolProvider.notifier).state = p;
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const _SectionTitle(title: 'MIRROR'),
          _AdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Skeleton sensitivity', style: context.ryoLabelStyle),
                const SizedBox(height: 4),
                Text(
                  'Relaxed shows more bones in poor light.',
                  style: context.ryoBodyStyle.copyWith(
                      fontSize: 12, color: context.ryoTextMuted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: LikelihoodMode.values.map((mode) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ChoiceChip(
                        label: mode.label,
                        selected: settings.likelihoodMode == mode,
                        onTap: () => ref.read(settingsProvider.notifier).setLikelihoodMode(mode),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  title: 'Physio / rehabilitation mode',
                  subtitle: 'Gentler thresholds + larger on-screen cues',
                  value: settings.physioMode,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setPhysioMode(v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const _SectionTitle(title: 'VOICE COACH'),
          _AdaptiveCard(
            child: Column(
              children: [
                _SwitchRow(
                  title: 'Speak on bad form',
                  subtitle: 'Coach speaks out loud when posture deviation is detected',
                  value: settings.voiceCoachOnBadForm,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setVoiceCoachOnBadForm(v),
                ),
                _SwitchRow(
                  title: 'Voice summary after set',
                  subtitle: 'Announces rep count when a set completes',
                  value: settings.voiceSummaryAfterSet,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setVoiceSummaryAfterSet(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: 'ACCESSIBILITY'),
          _AdaptiveCard(
            child: Column(
              children: [
                _SwitchRow(
                  title: 'High contrast (dark mode)',
                  subtitle: 'Stronger borders and text contrast',
                  value: settings.highContrast,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setHighContrast(v),
                ),
                _SwitchRow(
                  title: 'Reduce animations',
                  subtitle: 'Minimise motion effects throughout the app',
                  value: settings.reduceMotion,
                  onChanged: (v) => ref.read(settingsProvider.notifier).setReduceMotion(v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Senior / Elderly Mode feature card
// ---------------------------------------------------------------------------

class _ElderlyModeCard extends StatelessWidget {
  const _ElderlyModeCard({
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = context.ryoAccent;
    final isElderly = context.isElderlyMode;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: enabled
            ? accent.withValues(alpha: isElderly ? 0.08 : 0.10)
            : context.ryoCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              enabled ? accent.withValues(alpha: 0.5) : context.ryoDivider,
          width: enabled ? 1.5 : 0.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Icon(Icons.elderly_outlined, color: accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Senior Friendly Mode',
                  style: context.ryoTitleStyle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'White background · Large text · High contrast',
                  style: context.ryoBodyStyle.copyWith(
                    fontSize: 13,
                    color: context.ryoTextMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onToggle,
            thumbColor: WidgetStateProperty.resolveWith(
              (s) =>
                  s.contains(WidgetState.selected) ? Colors.white : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? accent
                  : context.ryoDivider,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI components — adaptive to theme
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: context.ryoLabelStyle.copyWith(
          fontSize: context.isElderlyMode ? 14 : 12,
        ),
      ),
    );
  }
}

class _AdaptiveCard extends StatelessWidget {
  const _AdaptiveCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.isElderlyMode ? 22 : 20),
      decoration: BoxDecoration(
        color: context.ryoCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.ryoDivider,
          width: context.isElderlyMode ? 1.0 : 0.5,
        ),
      ),
      child: child,
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.ryoAccent;
    final isElderly = context.isElderlyMode;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isElderly ? 16 : 14,
          vertical: isElderly ? 10 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : context.ryoSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : context.ryoDivider,
            width: selected ? 1.0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: context.ryoLabelStyle.copyWith(
            color: selected ? accent : context.ryoTextSecondary,
            fontSize: isElderly ? 14 : 12,
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isElderly = context.isElderlyMode;
    final accent = context.ryoAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.ryoTitleStyle.copyWith(
                    fontSize: isElderly ? 16 : 15,
                  ),
                ),
                if (subtitle != null) ...[  
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.ryoBodyStyle.copyWith(
                      fontSize: isElderly ? 13 : 11,
                      color: context.ryoTextMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? Colors.white : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? accent
                  : context.ryoDivider,
            ),
          ),
        ],
      ),
    );
  }
}
