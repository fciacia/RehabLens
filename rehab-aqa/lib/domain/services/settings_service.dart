// settings_service.dart
// Persists user preferences in SharedPreferences (on-device only).
// Drives Mirror (likelihood, physio mode, cue size), AudioBot (TTS language), theme (high contrast).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Keys & defaults
// ---------------------------------------------------------------------------

const _kTtsLanguage = 'ryo_tts_language'; // 'ms-MY' | 'en-US'
const _kDefaultActivity = 'ryo_default_activity';
const _kLikelihoodMode = 'ryo_likelihood_mode'; // strict | normal | relaxed
const _kPhysioMode = 'ryo_physio_mode';
const _kLargerCueText = 'ryo_larger_cue_text';
const _kHighContrast = 'ryo_high_contrast';
const _kReduceMotion = 'ryo_reduce_motion';
const _kFirstTimeMirrorTipsShown = 'ryo_first_time_mirror_tips';
const _kVoiceSummaryAfterSet = 'ryo_voice_summary_after_set';
const _kVoiceCoachOnBadForm = 'ryo_voice_coach_on_bad_form';
const _kSaveFormFeedbackClips = 'ryo_save_form_feedback_clips';
const _kFormFeedbackClipsMaxCount = 'ryo_form_feedback_clips_max_count';
const _kElderlyMode = 'ryo_elderly_mode';

const _defaultTtsLanguage = 'ms-MY';
const _defaultActivity = 'squat';
const _defaultLikelihood = 'normal';
const _defaultPhysioMode = false;
const _defaultLargerCueText = false;
const _defaultHighContrast = false;
const _defaultReduceMotion = false;
const _defaultVoiceSummaryAfterSet = false;
const _defaultVoiceCoachOnBadForm = true;
const _defaultSaveFormFeedbackClips = false;
const _defaultFormFeedbackClipsMaxCount = 20;
const _defaultElderlyMode = false;

/// Likelihood mode for skeleton drawing: stricter = fewer bones in marginal conditions.
enum LikelihoodMode { strict, normal, relaxed }

extension LikelihoodModeExt on LikelihoodMode {
  double get minLandmarkLikelihood => switch (this) {
        LikelihoodMode.strict => 0.5,
        LikelihoodMode.normal => 0.25,
        LikelihoodMode.relaxed => 0.15,
      };

  String get label => switch (this) {
        LikelihoodMode.strict => 'Strict',
        LikelihoodMode.normal => 'Normal',
        LikelihoodMode.relaxed => 'Relaxed',
      };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class SettingsState {
  const SettingsState({
    this.doctorEmail = '',
    this.ttsLanguage = _defaultTtsLanguage,
    this.defaultActivity = _defaultActivity,
    this.likelihoodMode = LikelihoodMode.normal,
    this.physioMode = _defaultPhysioMode,
    this.largerCueText = _defaultLargerCueText,
    this.highContrast = _defaultHighContrast,
    this.reduceMotion = _defaultReduceMotion,
    this.firstTimeMirrorTipsShown = false,
    this.voiceSummaryAfterSet = _defaultVoiceSummaryAfterSet,
    this.voiceCoachOnBadForm = _defaultVoiceCoachOnBadForm,
    this.saveFormFeedbackClips = _defaultSaveFormFeedbackClips,
    this.formFeedbackClipsMaxCount = _defaultFormFeedbackClipsMaxCount,
    this.elderlyMode = _defaultElderlyMode,
  });

  final String doctorEmail;
  final String ttsLanguage;
  final String defaultActivity;
  final LikelihoodMode likelihoodMode;
  final bool physioMode;
  final bool largerCueText;
  final bool highContrast;
  final bool reduceMotion;
  final bool firstTimeMirrorTipsShown;
  final bool voiceSummaryAfterSet;
  final bool voiceCoachOnBadForm;
  final bool saveFormFeedbackClips;
  final int formFeedbackClipsMaxCount;
  /// White background, large text senior-friendly mode.
  final bool elderlyMode;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._prefs)
      : super(const SettingsState()) {
    _load();
  }

  final SharedPreferences _prefs;

  Future<void> _load() async {
    final tts = _prefs.getString(_kTtsLanguage) ?? _defaultTtsLanguage;
    final activity = _prefs.getString(_kDefaultActivity) ?? _defaultActivity;
    final likStr = _prefs.getString(_kLikelihoodMode) ?? _defaultLikelihood;
    final likelihoodMode = switch (likStr) {
      'strict' => LikelihoodMode.strict,
      'relaxed' => LikelihoodMode.relaxed,
      _ => LikelihoodMode.normal,
    };
    final doctorEmail = _prefs.getString('ryo_doctor_email') ?? '';
    state = SettingsState(
      doctorEmail: doctorEmail,
      ttsLanguage: tts,
      defaultActivity: activity,
      likelihoodMode: likelihoodMode,
      physioMode: _prefs.getBool(_kPhysioMode) ?? _defaultPhysioMode,
      largerCueText: _prefs.getBool(_kLargerCueText) ?? _defaultLargerCueText,
      highContrast: _prefs.getBool(_kHighContrast) ?? _defaultHighContrast,
      reduceMotion: _prefs.getBool(_kReduceMotion) ?? _defaultReduceMotion,
      firstTimeMirrorTipsShown:
          _prefs.getBool(_kFirstTimeMirrorTipsShown) ?? false,
      voiceSummaryAfterSet:
          _prefs.getBool(_kVoiceSummaryAfterSet) ?? _defaultVoiceSummaryAfterSet,
      voiceCoachOnBadForm:
          _prefs.getBool(_kVoiceCoachOnBadForm) ?? _defaultVoiceCoachOnBadForm,
      saveFormFeedbackClips:
          _prefs.getBool(_kSaveFormFeedbackClips) ?? _defaultSaveFormFeedbackClips,
      elderlyMode: _prefs.getBool(_kElderlyMode) ?? _defaultElderlyMode,
      formFeedbackClipsMaxCount:
          _prefs.getInt(_kFormFeedbackClipsMaxCount) ?? _defaultFormFeedbackClipsMaxCount,
    );
  }

  Future<void> setDoctorEmail(String email) async {
    await _prefs.setString('ryo_doctor_email', email.trim());
    state = SettingsState(
      doctorEmail: email.trim(),
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setTtsLanguage(String value) async {
    await _prefs.setString(_kTtsLanguage, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: value,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setDefaultActivity(String value) async {
    await _prefs.setString(_kDefaultActivity, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: value,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setLikelihoodMode(LikelihoodMode value) async {
    await _prefs.setString(
        _kLikelihoodMode,
        switch (value) {
          LikelihoodMode.strict => 'strict',
          LikelihoodMode.relaxed => 'relaxed',
          _ => 'normal',
        });
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: value,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setPhysioMode(bool value) async {
    await _prefs.setBool(_kPhysioMode, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: value,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setLargerCueText(bool value) async {
    await _prefs.setBool(_kLargerCueText, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: value,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setHighContrast(bool value) async {
    await _prefs.setBool(_kHighContrast, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: value,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setReduceMotion(bool value) async {
    await _prefs.setBool(_kReduceMotion, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: value,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setFirstTimeMirrorTipsShown(bool value) async {
    await _prefs.setBool(_kFirstTimeMirrorTipsShown, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: value,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setVoiceSummaryAfterSet(bool value) async {
    await _prefs.setBool(_kVoiceSummaryAfterSet, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: value,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setVoiceCoachOnBadForm(bool value) async {
    await _prefs.setBool(_kVoiceCoachOnBadForm, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: value,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setSaveFormFeedbackClips(bool value) async {
    await _prefs.setBool(_kSaveFormFeedbackClips, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: value,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }

  Future<void> setFormFeedbackClipsMaxCount(int value) async {
    await _prefs.setInt(_kFormFeedbackClipsMaxCount, value.clamp(5, 50));
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: state.elderlyMode,
      formFeedbackClipsMaxCount: value.clamp(5, 50),
    );
  }

  Future<void> setElderlyMode(bool value) async {
    await _prefs.setBool(_kElderlyMode, value);
    state = SettingsState(
      doctorEmail: state.doctorEmail,
      ttsLanguage: state.ttsLanguage,
      defaultActivity: state.defaultActivity,
      likelihoodMode: state.likelihoodMode,
      physioMode: state.physioMode,
      largerCueText: state.largerCueText,
      highContrast: state.highContrast,
      reduceMotion: state.reduceMotion,
      firstTimeMirrorTipsShown: state.firstTimeMirrorTipsShown,
      voiceSummaryAfterSet: state.voiceSummaryAfterSet,
      voiceCoachOnBadForm: state.voiceCoachOnBadForm,
      saveFormFeedbackClips: state.saveFormFeedbackClips,
      elderlyMode: value,
      formFeedbackClipsMaxCount: state.formFeedbackClipsMaxCount,
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Override in main with SharedPreferences.getInstance() so settings can load.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'Override sharedPreferencesProvider in main with SharedPreferences.getInstance()');
});

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});
