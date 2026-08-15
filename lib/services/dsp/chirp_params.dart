import 'package:equatable/equatable.dart';

/// Shape of one FMCW sonar sweep.
///
/// Defaults follow the project's locked acoustic parameters: a 2–8 kHz
/// linear up-sweep, 40 ms long, at the standard mobile sample rate. Keep
/// this in sync if the parameters are ever retuned — [ChirpGenerator],
/// [CrossCorrelationService], and [ToFCalculator] all key off it.
class ChirpParams extends Equatable {
  const ChirpParams({
    // Near-ultrasonic band. Two reasons, both about working in a real room
    // rather than a quiet one:
    //
    // Noise immunity — speech, footsteps, HVAC and general room noise put
    // almost all their energy below ~8kHz, which is exactly where the
    // original 2-8kHz sweep lived. Moving the sweep above that band means
    // ambient noise contributes almost nothing to the correlation, so the
    // noise floor the gate measures against drops in a crowded room instead
    // of rising.
    //
    // Audibility — a 2-8kHz chirp is a loud, unpleasant sound to emit
    // repeatedly during a live demo. Up here it is faint to most listeners
    // and inaudible to many.
    //
    // Kept below Nyquist (22.05kHz at 44.1kHz sampling) with margin, since
    // mic anti-aliasing filters roll off as they approach it. Bandwidth is
    // still 6kHz, so range resolution is unchanged.
    this.startFrequencyHz = 13000,
    this.endFrequencyHz = 19000,
    // Matched-filter processing gain goes as the time-bandwidth product, so
    // a longer sweep buys SNR without needing more transmit power: at 6kHz
    // of bandwidth, 40ms gives TB=240 (~24dB) and 120ms gives TB=720
    // (~28.6dB). The compressed pulse stays just as sharp — its width is set
    // by bandwidth, not duration — so range resolution is unchanged.
    this.duration = const Duration(milliseconds: 120),
    this.sampleRate = 44100,
  });

  final double startFrequencyHz;
  final double endFrequencyHz;
  final Duration duration;
  final int sampleRate;

  int get sampleCount =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  double get durationSeconds =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  List<Object?> get props => [
    startFrequencyHz,
    endFrequencyHz,
    duration,
    sampleRate,
  ];
}
