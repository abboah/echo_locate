import 'dart:async';

import 'package:echo_locate/services/motion/step_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<int> hardware;

  setUp(() => hardware = StreamController<int>.broadcast());
  tearDown(() => hardware.close());

  StepService service({Future<bool> Function()? permission}) => StepService(
        cumulativeSteps: hardware.stream,
        requestPermission: permission ?? () async => true,
      );

  group('counting from where the user is now', () {
    test('the first hardware reading is the zero point', () async {
      // TYPE_STEP_COUNTER reports steps since boot, which could be 40,000.
      // What guidance needs is steps since this leg began.
      final s = service();
      await s.start();
      final seen = <int>[];
      s.steps.listen(seen.add);

      hardware.add(40000);
      hardware.add(40003);
      await pumpEventQueue();

      expect(seen, [0, 3]);
      expect(s.stepsSinceReset, 3);
    });

    test('reset re-zeros at the latest reading', () async {
      // Called every time an OCR match confirms a landmark, which is what
      // stops step error accumulating across a route.
      final s = service();
      await s.start();
      hardware.add(100);
      hardware.add(112);
      await pumpEventQueue();

      s.reset();
      final seen = <int>[];
      s.steps.listen(seen.add);
      hardware.add(115);
      await pumpEventQueue();

      expect(seen, [3]);
      expect(s.stepsSinceReset, 3);
    });
  });

  group('the counter going backwards', () {
    test('a reboot re-baselines instead of counting down', () async {
      // TYPE_STEP_COUNTER restarts at 0 when the phone reboots. Subtracting a
      // pre-reboot baseline would report a large negative count and, through
      // expectedSteps, tell the user they had walked backwards.
      final s = service();
      await s.start();
      hardware.add(40000);
      hardware.add(40005);
      await pumpEventQueue();

      final seen = <int>[];
      s.steps.listen(seen.add);
      hardware.add(2); // rebooted
      hardware.add(4);
      await pumpEventQueue();

      expect(seen.every((v) => v >= 0), isTrue,
          reason: 'never reports a negative walk');
      expect(s.stepsSinceReset, 2);
    });
  });

  group('devices without a step counter', () {
    test('a refused permission reports unavailable', () async {
      final s = service(permission: () async => false);

      expect(await s.start(), isFalse);
      expect(s.status, StepCounterStatus.unavailable);
    });

    test('a sensor error reports unavailable rather than hanging', () async {
      // Some Samsung devices expose no counter; the plugin surfaces that as a
      // stream error. Guidance must fall back to OCR-only (spec B5 rung 2)
      // rather than waiting forever for a tick.
      final s = service();
      await s.start();

      hardware.addError(StateError('no step sensor'));
      await pumpEventQueue();

      expect(s.status, StepCounterStatus.unavailable);
    });

    test('a working sensor reports available on the first tick', () async {
      final s = service();
      await s.start();
      expect(s.status, StepCounterStatus.unknown);

      hardware.add(7);
      await pumpEventQueue();

      expect(s.status, StepCounterStatus.available);
    });
  });
}
