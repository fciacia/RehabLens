// audio_bot.dart
// Manages the spatial TTS feedback loop.
// Queues spoken cues from the on-device coach and speaks via flutter_tts
// (on-device platform TTS — no API key required, works offline).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:logger/logger.dart';
import 'package:ryo/domain/services/settings_service.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final audioBotProvider = Provider<AudioBot>((ref) {
  final bot = AudioBot();
  bot.setLanguage(ref.read(settingsProvider).ttsLanguage);
  ref.listen<SettingsState>(settingsProvider, (_, next) {
    bot.setLanguage(next.ttsLanguage);
  });
  // Autonomous voice coach is triggered from Mirror when bad form is detected
  // (see mirror_screen.dart). No global speak on every analysis here.
  ref.onDispose(bot.dispose);
  return bot;
});

// ---------------------------------------------------------------------------
// AudioBot
// ---------------------------------------------------------------------------

/// Queues and speaks TTS cues using the platform on-device TTS engine
/// via [FlutterTts].  No API key or network required.
///
/// To upgrade to Google Cloud TTS or ElevenLabs, replace the [_tts.speak()]
/// call with an HTTP request that returns audio bytes, then pipe those bytes
/// to [AudioPlayer] using [BytesSource].
class AudioBot {
  AudioBot() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  final _log = Logger();

  final _queue = <String>[];
  bool _speaking = false;
  bool _initDone = false;

  // ---------------------------------------------------------------------------
  // Initialise
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    if (_initDone) return;
    await _tts.setSpeechRate(0.45);   // slightly slower for elderly/physio clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);         // neutral, clear for instructions

    // When a cue finishes, play the next one in the queue.
    _tts.setCompletionHandler(() {
      _speaking = false;
      _playNext();
    });

    _tts.setErrorHandler((msg) {
      _log.e('[AudioBot] TTS error: $msg');
      _speaking = false;
      _playNext();
    });
    _initDone = true;
  }

  /// Set TTS language (e.g. ms-MY, en-US). Called from settings.
  Future<void> setLanguage(String locale) async {
    final result = await _tts.setLanguage(locale);
    if (result != true) await _tts.setLanguage('en-US');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Speak the newest cue only. Clears any pending queue and interrupts current
  /// speech so only the latest, most relevant advice is heard (no backlog).
  void speak(String cue) {
    if (cue.isEmpty) return;
    _queue.clear();
    _queue.add(cue);
    _log.d('[AudioBot] Speak (queue cleared): "$cue"');
    _speakLatest();
  }

  /// Stop playback immediately and flush the queue.
  Future<void> stopAll() async {
    _queue.clear();
    await _tts.stop();
    _speaking = false;
  }

  Future<void> dispose() async {
    await stopAll();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Interrupt current speech if any, then play the single queued cue. Fire-and-forget.
  void _speakLatest() {
    if (_queue.isEmpty) return;
    if (_speaking) {
      _tts.stop().then((_) {
        // Completion handler may also run; only advance queue (don't force _speaking = false).
        _playNext();
      }).catchError((Object e) {
        _log.w('[AudioBot] Stop error (continuing): $e');
        _speaking = false;
        _playNext();
      });
      return;
    }
    _playNext();
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _speaking = false;
      return;
    }
    if (!_initDone) await _init();

    _speaking = true;
    final cue = _queue.removeAt(0);
    _log.d('[AudioBot] Speaking: "$cue"');

    try {
      await _tts.speak(cue);
    } catch (e) {
      _log.w('[AudioBot] speak error: $e');
      _speaking = false;
      _playNext();
    }
  }
}
