import 'package:equatable/equatable.dart';

/// Measured audio-path latencies for this device, and the capture schedule
/// derived from them.
///
/// The sonar's timing was originally two hand-tuned constants sized for the
/// worst case seen on an Infinix X657C: a 600ms recorder warmup and a 1000ms
/// capture window, together with the pulse train making a single sweep take
/// ~2.5s (and a 3-sweep measurement ~7.6s). That is far too slow to run
/// alongside a live camera.
///
/// Only the *capture window* is derived here. The recorder warmup is no
/// longer estimated at all: [SonarAudioService] waits for the recorder's
/// first chunk to actually arrive instead, which is exact where any estimate
/// was not. On-device, `firstByteAt` swung between 358ms and 652ms across
/// otherwise identical sweeps, so no single number could be both safe and
/// tight — and a schedule derived from the most recent sample chased that
/// noise upward (816ms to 1111ms) rather than converging.
///
/// [playbackLatency] cannot be waited on the same way, because nothing
/// signals when a sound actually leaves the speaker. It is instead read off
/// the recording — the direct speaker-to-mic breakthrough is the chirp
/// arriving over ~0m, so where it lands IS the emission moment — and
/// accumulated as a running maximum by the service, since a window sized
/// from an optimistic sample truncates the next slow sweep.
class SonarLatencyProfile extends Equatable {
  const SonarLatencyProfile({
    required this.recorderStartup,
    required this.playbackLatency,
  });

  /// From `startStream()` resolving to the first captured bytes arriving.
  final Duration recorderStartup;

  /// From `play()` being called to the sound actually leaving the speaker.
  final Duration playbackLatency;

  /// Slack added to both derived durations.
  ///
  /// Deliberately generous relative to the milliseconds being saved: the
  /// failure mode of too little is that the chirp falls outside the capture
  /// window and the sweep returns nothing at all, while the cost of too much
  /// is a fraction of a second. Both measurements are also approximations —
  /// the recorder's first *chunk* arrives some time after the audio in it was
  /// captured, so neither latency is known to better than a chunk.
  static const Duration safetyMargin = Duration(milliseconds: 200);

  /// A profile is only believed if both measurements are physically sensible.
  /// A failed correlation or a dropped recording can produce a negative or
  /// absurd figure, and adopting one would break every later sweep.
  bool get isPlausible =>
      !recorderStartup.isNegative &&
      !playbackLatency.isNegative &&
      recorderStartup < const Duration(seconds: 3) &&
      playbackLatency < const Duration(seconds: 3);

  /// How long to keep recording after the pulse train was scheduled to end.
  ///
  /// The train starts sounding [playbackLatency] late, so the window must
  /// cover that lag plus the flight time of the furthest echo still worth
  /// hearing.
  Duration captureWindow({required Duration maxEchoDelay}) =>
      playbackLatency + maxEchoDelay + safetyMargin;

  Map<String, int> toJson() => {
    'recorderStartupUs': recorderStartup.inMicroseconds,
    'playbackLatencyUs': playbackLatency.inMicroseconds,
  };

  static SonarLatencyProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final recorder = value['recorderStartupUs'];
    final playback = value['playbackLatencyUs'];
    if (recorder is! num || playback is! num) return null;
    final profile = SonarLatencyProfile(
      recorderStartup: Duration(microseconds: recorder.toInt()),
      playbackLatency: Duration(microseconds: playback.toInt()),
    );
    return profile.isPlausible ? profile : null;
  }

  @override
  String toString() =>
      'recorderStartup=${recorderStartup.inMilliseconds}ms '
      'playbackLatency=${playbackLatency.inMilliseconds}ms';

  @override
  List<Object?> get props => [recorderStartup, playbackLatency];
}
