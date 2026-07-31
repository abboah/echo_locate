import 'package:echo_locate/features/sonar/bloc/sonar_bloc.dart';
import 'package:echo_locate/services/audio/sonar_audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSonarAudioService extends Mock implements SonarAudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bloc subscribes to the magnetometer on start, for the radar heading.
  // Left unmocked, sensors_plus reaches for a platform channel that does not
  // exist here and leaves async work pending past the end of the test. These
  // tests are about calibration state, so the compass is stubbed to a stream
  // that simply never emits.
  const sensorsMethod = MethodChannel('dev.fluttercommunity.plus/sensors/method');
  const magnetometer =
      EventChannel('dev.fluttercommunity.plus/sensors/magnetometer');

  late _MockSonarAudioService audio;

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorsMethod, (_) async => null);
    messenger.setMockStreamHandler(
      magnetometer,
      MockStreamHandler.inline(onListen: (_, __) {}),
    );

    audio = _MockSonarAudioService();
    when(() => audio.stop()).thenAnswer((_) async {});
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(sensorsMethod, null);
    messenger.setMockStreamHandler(magnetometer, null);
  });

  Future<SonarBloc> started() async {
    final bloc = SonarBloc(audio)..add(const SonarStarted());
    await bloc.stream.firstWhere((s) => s.status != SonarStatus.starting);
    return bloc;
  }

  group('calibration state on start', () {
    test('a clutter profile restored from storage reports as calibrated', () {
      // Regression: the profile is restored by SonarAudioService.start() and
      // applied to every ping, but the bloc never asked, so a fresh launch
      // told the user to calibrate work that was already done.
      when(() => audio.start()).thenAnswer((_) async => true);
      when(() => audio.hasClutterProfile).thenReturn(true);

      return started().then((bloc) async {
        expect(bloc.state.status, SonarStatus.idle);
        expect(bloc.state.isCalibrated, isTrue);
        await bloc.close();
      });
    });

    test('no stored profile still asks for calibration', () async {
      when(() => audio.start()).thenAnswer((_) async => true);
      when(() => audio.hasClutterProfile).thenReturn(false);

      final bloc = await started();
      expect(bloc.state.status, SonarStatus.idle);
      expect(bloc.state.isCalibrated, isFalse);
      await bloc.close();
    });

    test('unavailable audio never claims to be calibrated', () async {
      when(() => audio.start()).thenAnswer((_) async => false);

      final bloc = await started();
      expect(bloc.state.status, SonarStatus.unavailable);
      expect(bloc.state.isCalibrated, isFalse);
      // The profile is not even consulted when there is no audio path.
      verifyNever(() => audio.hasClutterProfile);
      await bloc.close();
    });
  });

  group('calibration state after calibrating', () {
    test('a successful calibration marks the session calibrated', () async {
      when(() => audio.start()).thenAnswer((_) async => true);
      when(() => audio.hasClutterProfile).thenReturn(false);
      when(() => audio.calibrateClutter()).thenAnswer((_) async => true);

      final bloc = await started();
      bloc.add(const SonarCalibrateRequested());
      await bloc.stream.firstWhere((s) => s.status == SonarStatus.idle);

      expect(bloc.state.isCalibrated, isTrue);
      expect(bloc.state.error, isNull);
      await bloc.close();
    });

    test('a failed calibration keeps an already-restored profile', () async {
      // Failure leaves the previous profile untouched in the service, so the
      // UI must not downgrade to "calibration needed" and imply otherwise.
      when(() => audio.start()).thenAnswer((_) async => true);
      when(() => audio.hasClutterProfile).thenReturn(true);
      when(() => audio.calibrateClutter()).thenAnswer((_) async => false);

      final bloc = await started();
      expect(bloc.state.isCalibrated, isTrue);

      bloc.add(const SonarCalibrateRequested());
      await bloc.stream.firstWhere((s) => s.status == SonarStatus.idle);

      expect(bloc.state.isCalibrated, isTrue);
      expect(bloc.state.error, isNotNull);
      await bloc.close();
    });
  });
}
