import 'dart:async';

import 'package:echo_locate/services/audio/audio_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('priority', () {
    test('speech outranks ranging', () {
      // The ordering the whole arbiter exists to enforce: a spoken obstacle
      // warning must not queue behind a ~5.4s sonar measurement.
      expect(AudioUse.speech.rank, greaterThan(AudioUse.ranging.rank));
    });

    test('urgent speech outranks routine speech', () {
      expect(
        AudioUse.urgentSpeech.rank,
        greaterThan(AudioUse.speech.rank),
      );
    });

    test('guidance is ordered urgent > landmark > progress > routine', () {
      // Spec §7 B4. Without this a user hears "in ten steps, turn—" layered
      // over "CHAIR AHEAD", which is worse than useless to someone who cannot
      // see the chair.
      expect(
        AudioUse.urgentSpeech.rank,
        greaterThan(AudioUse.landmarkReached.rank),
      );
      expect(
        AudioUse.landmarkReached.rank,
        greaterThan(AudioUse.guidanceProgress.rank),
      );
      expect(
        AudioUse.guidanceProgress.rank,
        greaterThan(AudioUse.speech.rank),
      );
    });

    test('a landmark confirmation cuts off a progress update', () async {
      final arbiter = AudioArbiter();
      final progress = await arbiter.acquire(AudioUse.guidanceProgress);

      final landmark = await arbiter.acquire(AudioUse.landmarkReached);

      expect(landmark, isNotNull);
      expect(progress!.isCancelled, isTrue);
    });

    test('a progress update never talks over a landmark confirmation',
        () async {
      final arbiter = AudioArbiter();
      await arbiter.acquire(AudioUse.landmarkReached);

      expect(await arbiter.acquire(AudioUse.guidanceProgress), isNull);
    });
  });

  group('acquire', () {
    test('an idle arbiter hands over the hardware', () async {
      final arbiter = AudioArbiter();
      final lease = await arbiter.acquire(AudioUse.ranging);

      expect(lease, isNotNull);
      expect(arbiter.isBusy, isTrue);
      expect(lease!.isCancelled, isFalse);
    });

    test('releasing frees the hardware for the next caller', () async {
      final arbiter = AudioArbiter();
      final first = await arbiter.acquire(AudioUse.ranging);
      first!.release();

      expect(arbiter.isBusy, isFalse);
      expect(await arbiter.acquire(AudioUse.ranging), isNotNull);
    });

    test('speech pre-empts an in-flight measurement', () async {
      final arbiter = AudioArbiter();
      final ranging = await arbiter.acquire(AudioUse.ranging);

      // Sonar's loop polls isCancelled and releases; stand in for that.
      final speech = arbiter.acquire(AudioUse.speech);
      await Future<void>.delayed(Duration.zero);
      expect(ranging!.isCancelled, isTrue,
          reason: 'the holder must be told to stop');
      ranging.release();

      expect(await speech, isNotNull);
    });

    test('ranging is refused while speech holds the speaker', () async {
      final arbiter = AudioArbiter();
      await arbiter.acquire(AudioUse.speech);

      expect(await arbiter.acquire(AudioUse.ranging), isNull);
    });

    test('an urgent callout cuts off one already being spoken', () async {
      // "Very close, ahead" must not be dropped because "sign on your right"
      // is mid-sentence. Callouts arrive faster than they can be said, so
      // without this the warnings that matter are the ones refused.
      final arbiter = AudioArbiter();
      final routine = await arbiter.acquire(AudioUse.speech);

      final urgent = arbiter.acquire(AudioUse.urgentSpeech);
      await Future<void>.delayed(Duration.zero);
      expect(routine!.isCancelled, isTrue);
      routine.release();

      expect(await urgent, isNotNull);
    });

    test('equal priority is refused rather than queued', () async {
      // Two sweeps racing is a caller bug; serialising it silently would hide
      // one chirp firing at an unpredictable moment.
      final arbiter = AudioArbiter();
      await arbiter.acquire(AudioUse.ranging);

      expect(await arbiter.acquire(AudioUse.ranging), isNull);
    });
  });

  group('pre-emption timeout', () {
    test('a wedged holder cannot block an urgent callout forever', () async {
      final arbiter = AudioArbiter(
        preemptionTimeout: const Duration(milliseconds: 50),
      );
      // Acquired and never released — the failure mode the timeout exists for.
      final stuck = await arbiter.acquire(AudioUse.ranging);

      final speech = await arbiter.acquire(AudioUse.speech);

      expect(stuck!.isCancelled, isTrue);
      expect(speech, isNotNull,
          reason: 'speech must proceed even if ranging never lets go');
    });

    test('a holder that releases promptly is waited for, not timed out',
        () async {
      final arbiter = AudioArbiter(
        preemptionTimeout: const Duration(seconds: 5),
      );
      final ranging = await arbiter.acquire(AudioUse.ranging);

      var releasedBeforeSpeechStarted = false;
      final speech = arbiter.acquire(AudioUse.speech).then((lease) {
        expect(releasedBeforeSpeechStarted, isTrue);
        return lease;
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      releasedBeforeSpeechStarted = true;
      ranging!.release();

      expect(await speech, isNotNull);
    });
  });

  group('onCancelled', () {
    test('tells a holder that cannot poll to tear down at once', () async {
      // TTS is blocked inside the plugin for the length of an utterance and
      // never reaches a polling point. Without the hook it would hold the
      // speaker until the pre-emption timeout expired and the urgent callout
      // played over the top of it.
      final arbiter = AudioArbiter();
      final speech = await arbiter.acquire(AudioUse.speech);

      var toreDown = false;
      speech!.onCancelled(() => toreDown = true);

      unawaited(arbiter.acquire(AudioUse.urgentSpeech));
      await Future<void>.delayed(Duration.zero);

      expect(toreDown, isTrue);
    });

    test('fires immediately when the lease was already pre-empted', () async {
      // A holder that registers after cancellation must not miss it and sit
      // there synthesising into a microphone someone else now owns.
      final arbiter = AudioArbiter(
        preemptionTimeout: const Duration(milliseconds: 10),
      );
      final ranging = await arbiter.acquire(AudioUse.ranging);
      await arbiter.acquire(AudioUse.speech);

      var toreDown = false;
      ranging!.onCancelled(() => toreDown = true);

      expect(toreDown, isTrue);
    });

    test('is not fired by an ordinary release', () async {
      // Releasing is the holder finishing normally; a teardown hook that ran
      // then would stop the NEXT utterance, since `stop` is engine-wide.
      final arbiter = AudioArbiter();
      final speech = await arbiter.acquire(AudioUse.speech);

      var toreDown = false;
      speech!.onCancelled(() => toreDown = true);
      speech.release();

      expect(toreDown, isFalse);
    });
  });

  group('lease.done', () {
    test('completes on release so a pre-empter knows the hardware is idle',
        () async {
      final arbiter = AudioArbiter();
      final lease = await arbiter.acquire(AudioUse.ranging);

      var done = false;
      unawaited(lease!.done.then((_) => done = true));
      expect(done, isFalse);

      lease.release();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    test('a double release is harmless', () async {
      final arbiter = AudioArbiter();
      final lease = await arbiter.acquire(AudioUse.ranging);

      lease!.release();
      expect(lease.release, returnsNormally);
      expect(arbiter.isBusy, isFalse);
    });

    test('a stale lease releasing does not free a newer holder', () async {
      // The pre-emption timeout can leave an old holder still running. When it
      // finally releases, it must not evict whoever took over.
      final arbiter = AudioArbiter(
        preemptionTimeout: const Duration(milliseconds: 20),
      );
      final stale = await arbiter.acquire(AudioUse.ranging);
      final speech = await arbiter.acquire(AudioUse.speech);

      stale!.release();

      expect(arbiter.current, same(speech));
      expect(arbiter.isBusy, isTrue);
    });
  });
}
