import 'package:echo_locate/services/vision/arcore_capture_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart'
    show ArCoreAvailability;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the platform side, so everything above the channel can be
/// exercised without a certified phone — which is the whole situation this
/// feature is being built in.
class _FakeChannel {
  _FakeChannel(this.name);

  final String name;
  final List<MethodCall> calls = [];

  Object? Function(MethodCall call)? respond;
  bool throwMissingPlugin = false;
  PlatformException? throwPlatform;

  MethodChannel install() {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (throwMissingPlugin) throw MissingPluginException();
          final failure = throwPlatform;
          if (failure != null) throw failure;
          return respond?.call(call);
        });
    return channel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChannel channel;
  late ArCoreCaptureService service;

  setUp(() {
    channel = _FakeChannel('echo_locate/arcore_capture');
    service = ArCoreCaptureService(
      methodChannel: channel.install(),
      // Tests run on the host, so the Android guard is injected rather than
      // left to short-circuit every method to its degraded answer.
      platformSupported: true,
    );
  });

  group('the coordinate contract', () {
    test('ARCore forward (−z) becomes plan north (+y)', () {
      // The single easiest thing in this feature to get wrong, and the one
      // that cannot be caught by looking at the result: a mirrored floor is
      // still a plausible floor, and every left and right is inverted.
      //
      // ARCore is right-handed with +Y up and −Z away from the camera, so a
      // point two metres in front of where the user started is z = −2, and
      // that is two metres NORTH in the plan frame.
      expect(ArCoreCaptureService.toPlan(0, -2), const Offset(0, 2));
    });

    test('behind the start is south', () {
      expect(ArCoreCaptureService.toPlan(0, 3), const Offset(0, -3));
    });

    test('x passes straight through — only one axis flips', () {
      expect(ArCoreCaptureService.toPlan(1.5, 0), const Offset(1.5, 0));
      expect(ArCoreCaptureService.toPlan(-1.5, 0), const Offset(-1.5, 0));
    });

    test('the conversion preserves distances', () {
      // A mirror is an isometry, so this cannot catch a sign error — it is
      // here to catch a *scale* error, which the sign tests cannot see.
      final a = ArCoreCaptureService.toPlan(3, -4);
      expect(a.distance, closeTo(5, 1e-9));
    });
  });

  group('availability', () {
    test('maps the native string', () async {
      channel.respond = (_) => 'supported';

      expect(await service.checkAvailability(), ArCoreAvailability.supported);
    });

    test('an uncertified device is reported, not thrown', () async {
      channel.respond = (_) => 'unsupported';

      expect(await service.checkAvailability(), ArCoreAvailability.unsupported);
    });

    test('a build with no native side degrades to unsupported', () async {
      channel.throwMissingPlugin = true;

      expect(await service.checkAvailability(), ArCoreAvailability.unsupported);
    });
  });

  group('starting', () {
    test('returns null when the session starts', () async {
      channel.respond = (_) => null;

      expect(await service.start(viewWidth: 1080, viewHeight: 2400), isNull);
      expect(service.isRunning, isTrue);
    });

    test('an uncertified device gets sent to photo tracing', () async {
      channel.throwPlatform = PlatformException(
        code: 'unavailable',
        message: 'raw native detail',
      );

      final reason = await service.start(viewWidth: 1080, viewHeight: 2400);

      expect(reason, contains('not certified'));
      // The native message is diagnostic, not something to put in front of a
      // user — least of all one using a screen reader.
      expect(reason, isNot(contains('raw native detail')));
      expect(service.isRunning, isFalse);
    });

    test('a missing permission says which one', () async {
      channel.throwPlatform = PlatformException(code: 'permission');

      expect(
        await service.start(viewWidth: 1080, viewHeight: 2400),
        contains('Camera permission'),
      );
    });

    test('starting twice does not start twice', () async {
      channel.respond = (_) => null;

      await service.start(viewWidth: 1080, viewHeight: 2400);
      await service.start(viewWidth: 1080, viewHeight: 2400);

      expect(channel.calls.where((c) => c.method == 'start'), hasLength(1));
    });
  });

  group('hit testing', () {
    setUp(() async {
      channel.respond = (_) => null;
      await service.start(viewWidth: 1080, viewHeight: 2400);
    });

    test('converts a hit into a plan-frame corner', () async {
      channel.respond = (call) => call.method == 'hitTest'
          ? {'x': 1.0, 'z': -2.0, 'confidence': 1.0}
          : null;

      final corner = await service.hitTest(0.5, 0.5);

      expect(corner, isNotNull);
      expect(corner!.position, const Offset(1, 2));
      expect(corner.confidence, 1);
    });

    test('passes the tap through normalised', () async {
      channel.respond = (call) =>
          call.method == 'hitTest' ? {'x': 0.0, 'z': 0.0} : null;

      await service.hitTest(0.25, 0.75);

      final call = channel.calls.firstWhere((c) => c.method == 'hitTest');
      expect(call.arguments, {'u': 0.25, 'v': 0.75});
    });

    test('a tap that hit nothing is null, not an error', () async {
      channel.respond = (_) => null;

      // No tracking, no plane, or a point beyond what ARCore has actually
      // seen. All normal, and the screen says "aim at the floor".
      expect(await service.hitTest(0.5, 0.5), isNull);
    });

    test('keeps a low-confidence hit rather than discarding it', () async {
      channel.respond = (call) => call.method == 'hitTest'
          ? {'x': 0.0, 'z': 0.0, 'confidence': 0.5}
          : null;

      final corner = await service.hitTest(0.5, 0.5);

      // Reported, not averaged away: a finished plan should be able to say how
      // much of it was captured while tracking was solid.
      expect(corner!.confidence, 0.5);
    });

    test('a malformed native reply is null rather than a crash', () async {
      channel.respond = (call) =>
          call.method == 'hitTest' ? <String, Object?>{'x': 1.0} : null;

      expect(await service.hitTest(0.5, 0.5), isNull);
    });

    test('does nothing when the session is not running', () async {
      await service.stop();
      channel.calls.clear();

      expect(await service.hitTest(0.5, 0.5), isNull);
      expect(channel.calls, isEmpty);
    });
  });

  group('frames', () {
    test('reads tracking state and the plane lock', () {
      final frame = CaptureFrame.fromNative({
        'trackingState': 'TRACKING',
        'planeLocked': true,
        'width': 640,
        'height': 480,
      });

      expect(frame.tracking, CaptureTracking.tracking);
      expect(frame.canCapture, isTrue);
      expect(frame.planeLocked, isTrue);
      expect(frame.issue, CaptureTrackingIssue.none);
    });

    test('carries a preview when one was sent', () {
      final frame = CaptureFrame.fromNative({
        'trackingState': 'TRACKING',
        'jpeg': Uint8List.fromList([1, 2, 3]),
      });

      expect(frame.preview, hasLength(3));
    });

    test('a frame with no preview is normal, not empty', () {
      // Previews are throttled natively while ARCore updates every frame, so
      // most updates carry state and no image.
      final frame = CaptureFrame.fromNative({'trackingState': 'TRACKING'});

      expect(frame.preview, isNull);
      expect(frame.canCapture, isTrue);
    });

    test('paused tracking blocks capture and names what to do', () {
      final frame = CaptureFrame.fromNative({
        'trackingState': 'PAUSED',
        'failureReason': 'INSUFFICIENT_LIGHT',
      });

      expect(frame.canCapture, isFalse);
      expect(frame.issue, CaptureTrackingIssue.insufficientLight);
      expect(frame.issue.advice, contains('light'));
    });

    test('every issue gives an instruction, not a diagnosis', () {
      for (final issue in CaptureTrackingIssue.values) {
        expect(issue.advice, isNotEmpty);
        // "Insufficient features" is not something a person can act on.
        expect(issue.advice.toLowerCase(), isNot(contains('insufficient')));
        expect(issue.advice.toLowerCase(), isNot(contains('excessive')));
      }
    });

    test('an unrecognised failure reason still says something useful', () {
      final frame = CaptureFrame.fromNative({
        'trackingState': 'PAUSED',
        'failureReason': 'SOMETHING_NEW_IN_A_LATER_ARCORE',
      });

      expect(frame.issue, CaptureTrackingIssue.relocalising);
      expect(frame.issue.advice, isNotEmpty);
    });
  });
}
