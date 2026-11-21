// protocol_card.dart
// Full-bleed workout card with dark gradient overlay and bold text.
// Nike Training Club–inspired: image/pattern behind, text locked to bottom.

import 'package:flutter/material.dart';
import 'package:ryo/core/theme/ryo_theme.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class Protocol {
  const Protocol({
    required this.id,
    required this.name,
    required this.category,
    required this.targetMuscles,
    required this.difficulty,
    required this.icon,
    this.accentColor = RyoColors.cyan,
    this.imageAsset,
  });

  final String id;
  final String name;
  final String category;
  final List<String> targetMuscles;
  final ProtocolDifficulty difficulty;
  final IconData icon;
  final Color accentColor;
  final String? imageAsset;
}

enum ProtocolDifficulty { beginner, intermediate, elite }

extension ProtocolDifficultyExt on ProtocolDifficulty {
  String get label => switch (this) {
        ProtocolDifficulty.beginner => 'BEGINNER',
        ProtocolDifficulty.intermediate => 'INTERMEDIATE',
        ProtocolDifficulty.elite => 'ELITE',
      };

  Color get color => switch (this) {
        ProtocolDifficulty.beginner => RyoColors.cyan,
        ProtocolDifficulty.intermediate => RyoColors.warning,
        ProtocolDifficulty.elite => RyoColors.critical,
      };
}

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

const protocols = [
  Protocol(
    id: 'squat',
    name: 'SQUAT',
    category: 'LOWER BODY',
    targetMuscles: ['Quads', 'Glutes', 'Hamstrings'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.airline_seat_legroom_normal_outlined,
  ),
  Protocol(
    id: 'deadlift',
    name: 'DEADLIFT',
    category: 'POSTERIOR CHAIN',
    targetMuscles: ['Hamstrings', 'Lower Back', 'Traps'],
    difficulty: ProtocolDifficulty.intermediate,
    icon: Icons.fitness_center_outlined,
  ),
  Protocol(
    id: 'press',
    name: 'OVERHEAD PRESS',
    category: 'UPPER BODY',
    targetMuscles: ['Deltoids', 'Triceps', 'Traps'],
    difficulty: ProtocolDifficulty.intermediate,
    icon: Icons.sports_gymnastics,
  ),
  Protocol(
    id: 'lunge',
    name: 'LUNGE',
    category: 'UNILATERAL',
    targetMuscles: ['Quads', 'Glutes', 'Hip Flexors'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.directions_walk_outlined,
  ),
  Protocol(
    id: 'plank',
    name: 'PLANK',
    category: 'CORE STABILITY',
    targetMuscles: ['Core', 'Shoulders', 'Glutes'],
    difficulty: ProtocolDifficulty.elite,
    icon: Icons.horizontal_rule_outlined,
    accentColor: RyoColors.critical,
  ),
  Protocol(
    id: 'row',
    name: 'BENT-OVER ROW',
    category: 'BACK',
    targetMuscles: ['Lats', 'Rhomboids', 'Biceps'],
    difficulty: ProtocolDifficulty.elite,
    icon: Icons.compare_arrows_outlined,
    accentColor: RyoColors.warning,
  ),
  // Physio protocol–driven
  Protocol(
    id: 'post_stroke_shoulder_week1',
    name: 'SHOULDER W1',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Shoulder', 'ROM', 'Week 1'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.health_and_safety_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'knee_rehab_week1',
    name: 'KNEE REHAB W1',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Knee', 'ROM', 'Brigham'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.accessibility_new_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'knee_rehab_week2',
    name: 'KNEE REHAB W2',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Knee', 'ROM', 'Phase II–III'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.accessibility_new_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'knee_rehab_precautions',
    name: 'KNEE PRECAUTIONS',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Mass General', 'Precautions'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.warning_amber_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'post_stroke_general',
    name: 'STROKE GENERAL',
    category: 'PHYSIO · MOH',
    targetMuscles: ['MOH CPG', 'Mobilisation'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.health_and_safety_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'physio_general',
    name: 'PHYSIO GENERAL',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Safety limits', 'MOH guideline'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.medical_services_outlined,
    accentColor: RyoColors.cyan,
  ),
  Protocol(
    id: 'oa_exercises',
    name: 'OA EXERCISES',
    category: 'PHYSIO · MOH',
    targetMuscles: ['Quad/Hip', 'MOH OA CPG'],
    difficulty: ProtocolDifficulty.beginner,
    icon: Icons.fitness_center_outlined,
    accentColor: RyoColors.cyan,
  ),
];

// ---------------------------------------------------------------------------
// ProtocolCard widget
// ---------------------------------------------------------------------------

class ProtocolCard extends StatelessWidget {
  const ProtocolCard({
    super.key,
    required this.protocol,
    this.onTap,
    this.height = 220,
  });

  final Protocol protocol;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveHeight = constraints.hasBoundedHeight && constraints.maxHeight.isFinite
              ? height.clamp(0.0, constraints.maxHeight)
              : height;
          return Container(
            height: effectiveHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: context.ryoCard,
              border: Border.all(color: context.ryoDivider, width: 0.5),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background — anatomical grid pattern
                _AnatomicalBackground(protocol: protocol),

                // Gradient overlay — dark mode only (elderly uses plain white card, text is dark)
                if (!context.isElderlyMode)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),

                // Content pinned to bottom (constrained to avoid overflow on short cards)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (constraints.maxHeight - 40).clamp(60.0, double.infinity),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Category label
                        Text(
                          protocol.category,
                          style: RyoTypography.dataLabel.copyWith(
                            color: context.isElderlyMode
                                ? context.ryoAccent
                                : protocol.accentColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Movement name — 2 lines max
                        Text(
                          protocol.name,
                          style: RyoTypography.display.copyWith(
                            fontSize: 18,
                            height: 1.15,
                            color: context.isElderlyMode
                                ? context.ryoTextPrimary
                                : Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        // Muscle tags + difficulty pill
                        Row(
                          children: [
                            _DifficultyPill(
                              difficulty: protocol.difficulty,
                              accentColor: protocol.accentColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                protocol.targetMuscles.take(2).join(' · ').toUpperCase(),
                                style: RyoTypography.micro.copyWith(
                                  color: context.isElderlyMode
                                      ? context.ryoTextMuted
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                                maxLines: 2,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anatomical background — desaturated X-ray style grid
// ---------------------------------------------------------------------------

class _AnatomicalBackground extends StatelessWidget {
  const _AnatomicalBackground({required this.protocol});

  final Protocol protocol;

  @override
  Widget build(BuildContext context) {
    // If a real image asset is provided, use it.
    if (protocol.imageAsset != null) {
      return Image.asset(
        protocol.imageAsset!,
        fit: BoxFit.cover,
        colorBlendMode: BlendMode.luminosity,
        color: Colors.grey.shade800,
      );
    }

    // Fallback: ghost icon centred in upper half of the card.
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: Icon(
          protocol.icon,
          size: 72,
          color: protocol.accentColor.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty pill badge
// ---------------------------------------------------------------------------

class _DifficultyPill extends StatelessWidget {
  const _DifficultyPill({
    required this.difficulty,
    required this.accentColor,
  });

  final ProtocolDifficulty difficulty;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        difficulty.label,
        style: RyoTypography.micro.copyWith(
          color: accentColor,
          fontSize: 8,
          letterSpacing: 1.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
