import 'reverb_features.dart';

/// Why a reverberation capture produced nothing.
///
/// Split out because the causes need different responses and, during joint
/// camera+audio testing, are easily confused: a measurement lost to a spoken
/// obstacle callout looks exactly like a room that would not ring, and
/// reporting both as "no usable measurement" sends the tester hunting for an
/// acoustics problem that is really a scheduling one.
enum ReverbFailure {
  /// No microphone, or the engine never came up.
  audioUnavailable,

  /// The speaker and mic were in use — a sonar sweep, another capture, or
  /// speech holding them. Retrying once things fall quiet is reasonable.
  audioBusy,

  /// Started, then pre-empted mid-capture by something more urgent. The
  /// recording contains that sound rather than the room's decay, so it is
  /// discarded: analysing it would produce a confident, wrong RT60.
  interrupted,

  /// The recorder returned nothing, or the capture threw.
  captureFailed,

  /// A genuine capture that held no decay this method can fit — too quiet,
  /// too noisy, or a space too dead to ring. The only failure here that is
  /// about the ROOM rather than the device.
  noMeasurableDecay;

  /// Plain-language cause, for the screen and the logs.
  String get message => switch (this) {
    ReverbFailure.audioUnavailable => 'the microphone is unavailable',
    ReverbFailure.audioBusy => 'the microphone was busy — try again',
    ReverbFailure.interrupted =>
      'the measurement was interrupted by a spoken callout — try again',
    ReverbFailure.captureFailed => 'the recording failed — try again',
    ReverbFailure.noMeasurableDecay =>
      'no measurable reverberation in this space',
  };
}

/// The outcome of one reverberation capture: features, or why not.
///
/// Exactly one of [features] and [failure] is non-null.
class ReverbMeasurement {
  const ReverbMeasurement.measured(ReverbFeatures this.features)
    : failure = null;

  const ReverbMeasurement.failed(ReverbFailure this.failure) : features = null;

  final ReverbFeatures? features;
  final ReverbFailure? failure;

  bool get succeeded => features != null;

  @override
  String toString() => succeeded
      ? 'ReverbMeasurement($features)'
      : 'ReverbMeasurement(${failure!.name})';
}
