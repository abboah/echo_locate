import 'dart:async';

import 'package:echo_locate/features/profile/bloc/stride_calibration_cubit.dart';
import 'package:echo_locate/features/profile/profile_repository.dart';
import 'package:echo_locate/services/motion/step_service.dart';
import 'package:echo_locate/services/motion/stride_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSteps extends Mock implements StepService {}

class _MockProfile extends Mock implements ProfileRepository {}

void main() {
  late _MockSteps steps;
  late _MockProfile profile;
  late StreamController<int> stepStream;

  setUp(() {
    steps = _MockSteps();
    profile = _MockProfile();
    stepStream = StreamController<int>.broadcast();

    when(() => steps.start()).thenAnswer((_) async => true);
    when(() => steps.stop()).thenAnswer((_) async {});
    when(() => steps.reset()).thenAnswer((_) {});
    when(() => steps.steps).thenAnswer((_) => stepStream.stream);
    when(() => profile.saveStride(any())).thenAnswer((_) async {});
  });

  Future<void> pump() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a phone with no step counter says so instead of measuring', () async {
    when(() => steps.start()).thenAnswer((_) async => false);
    final cubit = StrideCalibrationCubit(steps, profile);

    await cubit.begin();

    expect(cubit.state.status, CalibrationStatus.unavailable);
    await cubit.close();
  });

  test('steps are counted while the user walks the measured distance',
      () async {
    final cubit = StrideCalibrationCubit(steps, profile);
    await cubit.begin();

    stepStream.add(13);
    await pump();

    expect(cubit.state.status, CalibrationStatus.walking);
    expect(cubit.state.steps, 13);
    await cubit.close();
  });

  test('finishing the walk stores metres per step', () async {
    final cubit = StrideCalibrationCubit(steps, profile);
    await cubit.begin();
    stepStream.add(20);
    await pump();

    await cubit.finish();

    // 10 m in 20 steps.
    expect(cubit.state.profile?.metres, closeTo(0.5, 0.001));
    expect(cubit.state.status, CalibrationStatus.done);
    verify(() => profile.saveStride(any(that: closeTo(0.5, 0.001)))).called(1);
    await cubit.close();
  });

  test('an impossible measurement is refused rather than stored', () async {
    final cubit = StrideCalibrationCubit(steps, profile);
    await cubit.begin();
    // Three steps for ten metres: the counter missed most of them. Storing
    // this would silently mis-scale every leg of every route.
    stepStream.add(3);
    await pump();

    await cubit.finish();

    expect(cubit.state.status, CalibrationStatus.implausible);
    verifyNever(() => profile.saveStride(any()));
    await cubit.close();
  });

  test('a counter that never ticked is reported as a sensor fault, not a bad '
      'walk', () async {
    final cubit = StrideCalibrationCubit(steps, profile);
    await cubit.begin();
    // No stepStream event at all: start() succeeded because it subscribed, and
    // the hardware then reported nothing. Telling the user their *distance*
    // was unbelievable would send them to re-measure a corridor that was never
    // the problem.
    await pump();

    await cubit.finish();

    expect(cubit.state.status, CalibrationStatus.unavailable);
    expect(cubit.state.error, contains('No steps were counted'));
    verifyNever(() => profile.saveStride(any()));
    await cubit.close();
  });

  test('the walked distance is the one the user picked', () async {
    final cubit = StrideCalibrationCubit(steps, profile);
    cubit.setDistance(20);
    await cubit.begin();
    stepStream.add(25);
    await pump();

    await cubit.finish();

    // 20 m in 25 steps, not the 10 m default.
    expect(cubit.state.profile?.metres, closeTo(0.8, 0.001));
    await cubit.close();
  });

  test('a user who skips the walk can give their height instead', () async {
    final cubit = StrideCalibrationCubit(steps, profile);

    await cubit.saveFromHeight(1.7);

    expect(cubit.state.profile?.source, StrideSource.height);
    verify(() => profile.saveStride(any(that: closeTo(0.7055, 0.001))))
        .called(1);
    await cubit.close();
  });

  test('an implausible height is refused', () async {
    final cubit = StrideCalibrationCubit(steps, profile);

    await cubit.saveFromHeight(0.4);

    expect(cubit.state.status, CalibrationStatus.implausible);
    verifyNever(() => profile.saveStride(any()));
    await cubit.close();
  });
}
