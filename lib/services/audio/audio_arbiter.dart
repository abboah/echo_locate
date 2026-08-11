import 'dart:async';

import '../../core/utils/logger.dart';

/// What a holder wants the audio hardware for. Ordered by urgency — see
/// [AudioUse.rank].
enum AudioUse {
  /// Sonar: emits a chirp train and records the echo. Long (~5.4s for a
  /// three-sweep measurement) and entirely interruptible — a lost measurement
  /// costs a retry, nothing more.
  ranging,

  /// Routine callouts and navigation directions. Short, and the reason a
  /// visually impaired user is holding the phone at all.
  speech,

  /// "About halfway", "you're close — sweep your phone to find the sign".
  /// Outranks a routine obstacle callout because it is time-sensitive: said
  /// late it describes somewhere the user has already walked past.
  guidanceProgress,

  /// "Reading Hall door." The confirmation that the user is where the route
  /// says they are — the single most useful sentence guidance ever speaks, and
  /// the one that resets the step count.
  landmarkReached,

  /// A callout about something the user is about to walk into. Same hardware
  /// as [speech], separated only so it can cut one off — see [rank].
  urgentSpeech;

  /// Higher wins. Speech outranks ranging because the alternative is a user
  /// walking toward an obstacle while the phone finishes measuring a wall:
  /// making an urgent callout queue behind a five-second sweep would make the
  /// warning useless by the time it arrived.
  ///
  /// Urgent speech outranks routine speech for the same reason one step down.
  /// Callouts arrive from a live camera at a few per second while an utterance
  /// takes seconds to say, so "very close, ahead" would otherwise be refused
  /// for being late to a queue behind "sign on your right" — silently, and
  /// exactly when it mattered most.
  ///
  /// The two guidance ranks sit between them, giving the order spec §7 B4
  /// requires: urgent obstacle > landmark confirmed > progress update >
  /// routine obstacle. Being where you think you are matters more than being
  /// told about a chair you are not about to hit; not walking into the chair
  /// matters more than either.
  int get rank => switch (this) {
        AudioUse.ranging => 0,
        AudioUse.speech => 10,
        AudioUse.guidanceProgress => 12,
        AudioUse.landmarkReached => 15,
        AudioUse.urgentSpeech => 20,
      };
}

/// Serialises access to the microphone and speaker.
///
/// Sonar drives both at once (chirp out, echo in), TTS drives the speaker, and
/// speech-to-text will drive the microphone. Nothing previously mediated
/// between them, so an obstacle callout during a measurement meant two
/// components talking to the same hardware — on Android that surfaces as
/// mangled audio, a failed recorder start, or a sweep that silently returns
/// nothing.
///
/// Deliberately not a lock or a queue. A caller either gets the hardware now
/// or is told no: queuing a sonar sweep behind speech would fire a chirp at
/// some unpredictable later moment, which is worse than not firing it.
class AudioArbiter {
  AudioArbiter({this.preemptionTimeout = const Duration(seconds: 2)});

  /// How long a pre-empting caller waits for the current holder to let go
  /// before taking the hardware anyway. Bounded so a wedged holder cannot
  /// block an urgent callout indefinitely — sonar's cancellation checks run
  /// every ~100ms, so this only expires if something is genuinely stuck.
  final Duration preemptionTimeout;

  AudioLease? _current;

  /// The active holder, or null when the hardware is free.
  AudioLease? get current => _current;

  bool get isBusy => _current != null;

  /// Takes the microphone and speaker for [use], pre-empting a lower-priority
  /// holder. Returns null when refused — the caller must not touch audio.
  ///
  /// Equal priority is refused rather than queued: two sweeps or two
  /// utterances racing means the caller has a bug, and serialising them
  /// silently would hide it.
  Future<AudioLease?> acquire(AudioUse use) async {
    final held = _current;
    if (held != null) {
      if (use.rank <= held.use.rank) {
        AppLogger.debug(
          'AUDIO refused :: ${use.name} cannot pre-empt ${held.use.name}',
        );
        return null;
      }
      AppLogger.info('AUDIO pre-empting ${held.use.name} for ${use.name}');
      held._cancel();
      await held.done.timeout(preemptionTimeout, onTimeout: () {});
    }

    // Dart is single-threaded, but the await above yields, so another caller
    // could have taken the hardware meanwhile. Losing that race is refused
    // rather than retried — whoever holds it now is at least as urgent.
    if (_current != null && _current != held) {
      AppLogger.debug('AUDIO refused :: lost the race for ${use.name}');
      return null;
    }

    final lease = AudioLease._(use, this);
    _current = lease;
    return lease;
  }

  void _release(AudioLease lease) {
    if (identical(_current, lease)) _current = null;
  }
}

/// A held claim on the audio hardware. Release it in a `finally`, and check
/// [isCancelled] at every point where work can be abandoned.
class AudioLease {
  AudioLease._(this.use, this._arbiter);

  final AudioUse use;
  final AudioArbiter _arbiter;
  final Completer<void> _done = Completer<void>();

  bool _cancelled = false;
  void Function()? _onCancelled;

  /// True once something more urgent has asked for the hardware. Holders are
  /// expected to stop promptly and [release]; nothing forces them to.
  bool get isCancelled => _cancelled;

  /// Completes when the holder releases. A pre-empting caller waits on this
  /// so it does not start playing over audio that is still being torn down.
  Future<void> get done => _done.future;

  /// Registers a hook fired the moment this lease is pre-empted, for holders
  /// that cannot poll [isCancelled].
  ///
  /// Sonar sits in its own loop and can check between pulses; a holder blocked
  /// inside a plugin call — TTS awaiting the end of an utterance — cannot, and
  /// without this would hold the speaker until the pre-emption timeout expired
  /// and the urgent callout talked over it. [callback] must not throw and
  /// should only start the teardown; [release] still ends the lease.
  ///
  /// Fires immediately if the lease was already pre-empted, so a holder that
  /// registers late cannot miss it.
  void onCancelled(void Function() callback) {
    _onCancelled = callback;
    if (_cancelled) callback();
  }

  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancelled?.call();
  }

  void release() {
    _arbiter._release(this);
    if (!_done.isCompleted) _done.complete();
  }
}
