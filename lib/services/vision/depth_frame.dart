import 'package:equatable/equatable.dart';

/// Whether ARCore can run on this device — the answer that decides if the
/// camera scan flow is offered at all.
///
/// Mirrors `ArCoreApk.Availability` one-for-one rather than collapsing to a
/// bool, because the cases need different UI: [unsupported] is permanent and
/// the scan entry point should be hidden, while [supportedNotInstalled] and
/// [supportedApkTooOld] are fixable by the user and should prompt.
enum ArCoreAvailability {
  /// Ready to use.
  supported,

  /// Device is capable, but the ARCore APK is missing — installable from Play.
  supportedNotInstalled,

  /// Device is capable, but the installed ARCore is too old — updatable.
  supportedApkTooOld,

  /// Google has not certified this device. Permanent; no user action helps.
  unsupported,

  /// Still querying (ARCore answers asynchronously on first call).
  checking,

  /// Query failed or timed out.
  unknown;

  /// True only when scanning can actually start right now.
  bool get isReady => this == ArCoreAvailability.supported;

  /// True when the user could fix this by installing or updating ARCore.
  bool get isUserFixable =>
      this == ArCoreAvailability.supportedNotInstalled ||
      this == ArCoreAvailability.supportedApkTooOld;

  static ArCoreAvailability fromNative(String? value) => switch (value) {
    'supported' => ArCoreAvailability.supported,
    'supportedNotInstalled' => ArCoreAvailability.supportedNotInstalled,
    'supportedApkTooOld' => ArCoreAvailability.supportedApkTooOld,
    'unsupported' => ArCoreAvailability.unsupported,
    'checking' => ArCoreAvailability.checking,
    _ => ArCoreAvailability.unknown,
  };
}

/// How well ARCore currently knows where the phone is.
///
/// Depth is only meaningful while [tracking]; the other states mean the pose
/// is unreliable, so a frame captured then would put its points in the wrong
/// place on the floor plan.
enum DepthTrackingState {
  tracking,
  paused,
  stopped;

  static DepthTrackingState fromNative(String? value) => switch (value) {
    'TRACKING' => DepthTrackingState.tracking,
    'PAUSED' => DepthTrackingState.paused,
    _ => DepthTrackingState.stopped,
  };
}

/// One ARCore depth observation: a coarse depth grid plus the camera pose it
/// was taken from.
///
/// The grid is downsampled natively (see `ArCoreDepthHandler.GRID_COLUMNS`) —
/// enough to prove depth is live and to drive M0's readout, while M3 will read
/// the full-resolution image natively rather than marshalling it per frame.
class DepthFrame extends Equatable {
  const DepthFrame({
    required this.trackingState,
    required this.hasDepth,
    required this.width,
    required this.height,
    required this.gridColumns,
    required this.gridRows,
    required this.grid,
    required this.minMillimeters,
    required this.maxMillimeters,
    required this.meanMillimeters,
    required this.validSamples,
    required this.timestampNs,
    required this.translation,
    required this.rotation,
  });

  /// A frame that arrived while ARCore had no usable pose, so carries no depth.
  const DepthFrame.untracked(this.trackingState)
    : hasDepth = false,
      width = 0,
      height = 0,
      gridColumns = 0,
      gridRows = 0,
      grid = const [],
      minMillimeters = 0,
      maxMillimeters = 0,
      meanMillimeters = 0,
      validSamples = 0,
      timestampNs = 0,
      translation = const [0, 0, 0],
      rotation = const [0, 0, 0, 1];

  final DepthTrackingState trackingState;

  /// False while depth is still converging. ARCore's depth is derived from
  /// motion parallax, so the first frames after start carry a pose but no
  /// depth until the user has moved the phone.
  final bool hasDepth;

  /// Full depth-image dimensions, before downsampling.
  final int width;
  final int height;

  final int gridColumns;
  final int gridRows;

  /// Row-major depths in millimetres, `gridRows * gridColumns` long.
  /// A 0 means "no depth returned for this cell", not "zero distance".
  final List<int> grid;

  final int minMillimeters;
  final int maxMillimeters;
  final int meanMillimeters;

  /// Non-zero cells in [grid] — the honest denominator for [meanMillimeters],
  /// and a coverage signal (a frame pointed at a window returns almost none).
  final int validSamples;

  final int timestampNs;

  /// Camera position in ARCore's world space, metres, `[x, y, z]`.
  final List<double> translation;

  /// Camera orientation as a quaternion, `[x, y, z, w]`.
  final List<double> rotation;

  double get minMeters => minMillimeters / 1000.0;
  double get maxMeters => maxMillimeters / 1000.0;
  double get meanMeters => meanMillimeters / 1000.0;

  /// Depth at the centre of the frame — "what am I pointed at" — or null when
  /// that cell returned no depth.
  double? get centerMeters {
    if (!hasDepth || grid.isEmpty) return null;
    final index = (gridRows ~/ 2) * gridColumns + (gridColumns ~/ 2);
    if (index < 0 || index >= grid.length) return null;
    final millimeters = grid[index];
    return millimeters == 0 ? null : millimeters / 1000.0;
  }

  static DepthFrame fromNative(Map<Object?, Object?> map) {
    final tracking = DepthTrackingState.fromNative(
      map['trackingState'] as String?,
    );
    if (map['hasDepth'] != true) return DepthFrame.untracked(tracking);

    return DepthFrame(
      trackingState: tracking,
      hasDepth: true,
      width: _int(map['width']),
      height: _int(map['height']),
      gridColumns: _int(map['gridColumns']),
      gridRows: _int(map['gridRows']),
      grid: _intList(map['grid']),
      minMillimeters: _int(map['minMillimeters']),
      maxMillimeters: _int(map['maxMillimeters']),
      meanMillimeters: _int(map['meanMillimeters']),
      validSamples: _int(map['validSamples']),
      timestampNs: _int(map['timestampNs']),
      translation: _doubleList(map['translation']),
      rotation: _doubleList(map['rotation']),
    );
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static List<int> _intList(Object? value) => value is List
      ? value.map((v) => v is num ? v.toInt() : 0).toList(growable: false)
      : const [];

  static List<double> _doubleList(Object? value) => value is List
      ? value.map((v) => v is num ? v.toDouble() : 0.0).toList(growable: false)
      : const [];

  @override
  List<Object?> get props => [
    trackingState,
    hasDepth,
    timestampNs,
    minMillimeters,
    maxMillimeters,
    meanMillimeters,
    validSamples,
    grid,
    translation,
    rotation,
  ];
}
