import 'package:echo_locate/services/audio/sonar_latency_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Round trip to ToFCalculator's 10m ceiling: 2*10/343 ≈ 58ms.
  const maxEchoDelay = Duration(milliseconds: 58);

  /// The measurements the Infinix X657C actually produced, which the old
  /// hand-tuned constants were sized around.
  const infinix = SonarLatencyProfile(
    recorderStartup: Duration(milliseconds: 450),
    playbackLatency: Duration(milliseconds: 560),
  );

  group('captureWindow', () {
    test('covers playback lag plus the furthest echo, with margin', () {
      // 560 playback + 58 echo + 200 margin = 818ms.
      expect(
        infinix.captureWindow(maxEchoDelay: maxEchoDelay),
        const Duration(milliseconds: 818),
      );
    });

    test('a faster playback engine shortens the window', () {
      const fast = SonarLatencyProfile(
        recorderStartup: Duration(milliseconds: 100),
        playbackLatency: Duration(milliseconds: 50),
      );
      expect(
        fast.captureWindow(maxEchoDelay: maxEchoDelay),
        const Duration(milliseconds: 308),
      );
    });
  });

  test('the measured window beats the hand-tuned 1000ms constant', () {
    const handTuned = Duration(milliseconds: 1000);
    expect(
      infinix.captureWindow(maxEchoDelay: maxEchoDelay),
      lessThan(handTuned),
    );
  });

  test('the window always outlasts the chirp it has to capture', () {
    // The invariant that matters: recording must still be running when the
    // furthest echo arrives. The chirp sounds `playbackLatency` after the
    // train was scheduled, so the window has to cover that plus flight time —
    // undershoot here costs the entire reading, not just accuracy.
    for (final playback in const [
      Duration(milliseconds: 50),
      Duration(milliseconds: 400),
      Duration(milliseconds: 569),
      Duration(milliseconds: 1200),
    ]) {
      final profile = SonarLatencyProfile(
        recorderStartup: const Duration(milliseconds: 500),
        playbackLatency: playback,
      );
      expect(
        profile.captureWindow(maxEchoDelay: maxEchoDelay),
        greaterThan(playback + maxEchoDelay),
        reason: 'window must outlast the echo at playback=$playback',
      );
    }
  });

  group('isPlausible', () {
    test('accepts realistic measurements', () {
      expect(infinix.isPlausible, isTrue);
    });

    test('rejects negatives, which mean the correlation misfired', () {
      // A breakthrough found before play() was called is impossible; adopting
      // it would shorten the schedule until every later sweep missed.
      const negative = SonarLatencyProfile(
        recorderStartup: Duration(milliseconds: 450),
        playbackLatency: Duration(milliseconds: -100),
      );
      expect(negative.isPlausible, isFalse);
    });

    test('rejects absurdly long values from a dropped recording', () {
      const absurd = SonarLatencyProfile(
        recorderStartup: Duration(seconds: 5),
        playbackLatency: Duration(milliseconds: 560),
      );
      expect(absurd.isPlausible, isFalse);
    });
  });

  group('persistence', () {
    test('round-trips through json', () {
      expect(SonarLatencyProfile.fromJson(infinix.toJson()), infinix);
    });

    test('a malformed or implausible stored value is discarded', () {
      expect(SonarLatencyProfile.fromJson(null), isNull);
      expect(SonarLatencyProfile.fromJson('nonsense'), isNull);
      expect(SonarLatencyProfile.fromJson({'recorderStartupUs': 1}), isNull);
      expect(
        SonarLatencyProfile.fromJson(
          const {'recorderStartupUs': -1, 'playbackLatencyUs': 100},
        ),
        isNull,
        reason: 'stored garbage must not be trusted on restore',
      );
    });
  });
}
