// session_service.dart
// Workout session lifecycle: start -> track reps -> end.
// Held in memory only. Persistent local storage (SQLite) is added later
// as lib/data/local_store.dart. Nothing is sent off the phone.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ryo/core/vision/rep_detector.dart';
import 'package:ryo/domain/services/local_coach.dart';

class SessionState {
  const SessionState({
    this.isActive = false,
    this.sessionId = '',
    this.activity = 'squat',
    this.repCount = 0,
  });

  final bool isActive;
  final String sessionId;
  final String activity;
  final int repCount;

  SessionState copyWith({
    bool? isActive,
    String? sessionId,
    String? activity,
    int? repCount,
  }) =>
      SessionState(
        isActive: isActive ?? this.isActive,
        sessionId: sessionId ?? this.sessionId,
        activity: activity ?? this.activity,
        repCount: repCount ?? this.repCount,
      );
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier() : super(const SessionState());

  Future<void> startSession(String activity) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    state = SessionState(
      isActive: true,
      sessionId: sessionId,
      activity: activity,
      repCount: 0,
    );
    debugPrint('[SessionService] Started session: $sessionId ($activity)');
  }

  Future<void> endSession() async {
    if (!state.isActive) return;
    debugPrint('[SessionService] Ended session: ${state.sessionId} '
        '(${state.repCount} reps)');
    state = const SessionState();
  }

  /// Update the session from every non-none rep trigger.
  Future<void> onSnapshot(RepSnapshot snap, {MovementAnalysis? analysis}) async {
    if (!state.isActive) await startSession(snap.activity);
    switch (snap.trigger) {
      case ApiTrigger.repCompleted:
      case ApiTrigger.shallowRep:
      case ApiTrigger.badTempo:
      case ApiTrigger.asymmetryDetected:
      case ApiTrigger.fatigueDetected:
      case ApiTrigger.grinderRep:
      case ApiTrigger.dangerousBottom:
        state = state.copyWith(repCount: snap.repCount);
      case ApiTrigger.setComplete:
        break;
      case ApiTrigger.sessionComplete:
        state = const SessionState();
      case ApiTrigger.none:
        break;
    }
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier();
});
