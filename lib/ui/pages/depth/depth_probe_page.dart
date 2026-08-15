import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_dimens.dart';
import '../../../services/injection_container.dart';
import '../../../services/vision/arcore_depth_service.dart';
import '../../../services/vision/depth_frame.dart';

/// M0 spike readout — the acceptance check ("live depth numbers print on a
/// real Android device") made observable instead of log-only.
///
/// Deliberately a plain StatefulWidget, not a Bloc: this is throwaway
/// diagnostic surface for the spike, and M3 builds the real `ScanBloc` against
/// the same [ArCoreDepthService]. Adding a Bloc here would mean writing one to
/// delete.
class DepthProbePage extends StatefulWidget {
  const DepthProbePage({super.key});

  @override
  State<DepthProbePage> createState() => _DepthProbePageState();
}

class _DepthProbePageState extends State<DepthProbePage> {
  final ArCoreDepthService _service = getIt<ArCoreDepthService>();

  ArCoreAvailability? _availability;
  bool? _depthSupported;
  String? _error;
  DepthFrame? _frame;
  int _frameCount = 0;
  StreamSubscription<DepthFrame>? _subscription;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final availability = await _service.checkAvailability();
    final depth = availability.isReady
        ? await _service.isDepthSupported()
        : false;
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _depthSupported = depth;
    });
  }

  Future<void> _start() async {
    if (!await Permission.camera.request().isGranted) {
      if (!mounted) return;
      setState(() => _error = 'Camera permission is needed to scan');
      return;
    }

    final failure = await _service.start();
    if (!mounted) return;
    setState(() => _error = failure);
    if (failure != null) return;

    _subscription = _service.frames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _frame = frame;
        _frameCount++;
      });
    });
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _service.stop();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // Fire-and-forget: dispose cannot await, but the native session must not
    // outlive the page or it keeps the camera locked.
    unawaited(_service.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = _availability;
    final running = _service.isRunning;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => context.pop(),
        ),
        title: const Text('Depth probe (M0)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.space16),
        children: [
          _Row(label: 'ARCore', value: _availabilityLabel(availability)),
          _Row(
            label: 'Depth API',
            value: switch (_depthSupported) {
              null => 'Checking…',
              true => 'Supported',
              false => 'Not supported',
            },
          ),
          const Divider(height: AppDimens.space32),
          if (availability != null && !availability.isReady)
            Text(switch (availability) {
              ArCoreAvailability.supportedNotInstalled ||
              ArCoreAvailability.supportedApkTooOld =>
                'This device can run ARCore, but the ARCore app is missing '
                    'or out of date. Install or update "Google Play Services '
                    'for AR" from the Play Store, then reopen this screen.',
              ArCoreAvailability.unsupported =>
                'Google has not certified this device for ARCore, so '
                    'camera scanning cannot run on it. Everything else in '
                    'the app — sonar, browsing and navigation — works '
                    'normally. Scanning needs a certified device.',
              // Distinct from `unsupported`: ARCore did not rule the device
              // out, it failed to answer. Saying "not certified" here would
              // assert more than was measured — and this is the state an
              // uncertified device actually lands in, because ARCore's
              // install service cannot resolve it at all.
              _ =>
                'ARCore could not determine whether this device supports '
                    'scanning — it is either uncertified or unable to reach '
                    'Google Play Services for AR. Scanning stays unavailable '
                    'until it answers. Sonar, browsing and navigation are '
                    'unaffected.',
            }, style: theme.textTheme.bodyMedium),
          if (availability != null && availability.isReady) ...[
            _Row(label: 'Frames', value: '$_frameCount'),
            _Row(label: 'Tracking', value: _frame?.trackingState.name ?? '—'),
            _Row(
              label: 'Centre',
              value: _frame?.centerMeters == null
                  ? '—'
                  : '${_frame!.centerMeters!.toStringAsFixed(2)} m',
            ),
            _Row(
              label: 'Range',
              value: _frame == null || !_frame!.hasDepth
                  ? '—'
                  : '${_frame!.minMeters.toStringAsFixed(2)} – '
                        '${_frame!.maxMeters.toStringAsFixed(2)} m',
            ),
            _Row(
              label: 'Valid cells',
              value: _frame == null ? '—' : '${_frame!.validSamples}',
            ),
            _Row(
              label: 'Pose',
              value: _frame == null || _frame!.translation.length < 3
                  ? '—'
                  : _frame!.translation
                        .map((v) => v.toStringAsFixed(2))
                        .join(', '),
            ),
            const SizedBox(height: AppDimens.space24),
            if (running && _frame != null && !_frame!.hasDepth)
              Text(
                'Move the phone slowly side to side — ARCore derives depth '
                'from motion, so there is none until it has parallax.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: AppDimens.space16),
            ElevatedButton.icon(
              onPressed: running ? _stop : _start,
              icon: Icon(
                running ? PhosphorIconsRegular.stop : PhosphorIconsRegular.play,
                size: 20,
              ),
              label: Text(running ? 'Stop' : 'Start depth session'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppDimens.space16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _availabilityLabel(ArCoreAvailability? availability) =>
      switch (availability) {
        null => 'Checking…',
        ArCoreAvailability.supported => 'Supported',
        ArCoreAvailability.supportedNotInstalled => 'Needs install',
        ArCoreAvailability.supportedApkTooOld => 'Needs update',
        ArCoreAvailability.unsupported => 'Not supported on this device',
        ArCoreAvailability.checking => 'Checking…',
        ArCoreAvailability.unknown => 'Unknown',
      };
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
