import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/logger.dart';
import '../../../services/motion/step_service.dart';
import '../../../services/motion/stride_profile.dart';
import '../profile_repository.dart';

/// idle → walking → done | implausible, or unavailable on a phone with no
/// step counter.
enum CalibrationStatus { idle, unavailable, walking, done, implausible, failed }

class StrideCalibrationState extends Equatable {
  const StrideCalibrationState({
    this.status = CalibrationStatus.idle,
    this.distanceM = StrideCalibrationCubit.defaultDistanceM,
    this.steps = 0,
    this.profile,
    this.error,
  });

  final CalibrationStatus status;

  /// The measured distance the user walks. Ten metres is long enough that a
  /// step or two of error is a few percent, short enough to pace out in a
  /// corridor with a tape.
  final double distanceM;

  final int steps;
  final StrideProfile? profile;
  final String? error;

  StrideCalibrationState copyWith({
    CalibrationStatus? status,
    double? distanceM,
    int? steps,
    StrideProfile? profile,
    String? error,
  }) => StrideCalibrationState(
    status: status ?? this.status,
    distanceM: distanceM ?? this.distanceM,
    steps: steps ?? this.steps,
    profile: profile ?? this.profile,
    error: error,
  );

  @override
  List<Object?> get props => [status, distanceM, steps, profile, error];
}

/// Measures how far this user travels per step.
///
/// The one per-user number in the whole system. Routes are stored in metres
/// precisely so that a contributor's stride never leaks into anybody else's
/// directions; this is where a user's own stride enters, and everything spoken
/// about distance is scaled by it.
class StrideCalibrationCubit extends Cubit<StrideCalibrationState> {
  StrideCalibrationCubit(this._steps, this._profile)
    : super(const StrideCalibrationState());

  final StepService _steps;
  final ProfileRepository _profile;

  StreamSubscription<int>? _subscription;

  static const double defaultDistanceM = 10;

  void setDistance(double metres) => emit(state.copyWith(distanceM: metres));

  /// Starts counting. The user walks the measured distance and taps [finish].
  Future<void> begin() async {
    final available = await _steps.start();
    if (isClosed) return;
    if (!available) {
      emit(state.copyWith(status: CalibrationStatus.unavailable));
      return;
    }

    _steps.reset();
    await _subscription?.cancel();
    _subscription = _steps.steps.listen((count) {
      if (!isClosed) emit(state.copyWith(steps: count));
    });
    emit(state.copyWith(status: CalibrationStatus.walking, steps: 0));
  }

  /// Ends the walk and stores the result, unless it is not believable.
  Future<void> finish() async {
    await _subscription?.cancel();
    _subscription = null;

    // Counting nothing is a sensor fault, not a bad walk, and the two need
    // opposite things from the user. Reporting it as an implausible distance
    // sends someone off to re-measure a corridor that was never the problem:
    // TYPE_STEP_COUNTER simply never ticked. [StepService.start] cannot catch
    // this on its own — it reports success the moment it subscribes, and the
    // "no such sensor" error arrives asynchronously afterwards, by which time
    // the screen already says "walking".
    if (state.steps <= 0) {
      emit(
        state.copyWith(
          status: CalibrationStatus.unavailable,
          error:
              'No steps were counted, so this walk cannot be measured. '
              'Give your height instead — guidance will lean on landmarks '
              'rather than step counts.',
        ),
      );
      return;
    }

    final measured = StrideProfile.fromWalk(
      distanceM: state.distanceM,
      steps: state.steps,
    );
    await _store(
      measured,
      'That walk does not give a believable step length. Check the distance '
      'you marked out and try again.',
    );
  }

  /// The fallback for a user who will not pace out a corridor: step length is
  /// about 0.415 of height. Less accurate than walking it, and better than the
  /// generic default it replaces.
  Future<void> saveFromHeight(double heightM) => _store(
    StrideProfile.fromHeight(heightM),
    'That height does not give a believable step length.',
  );

  Future<void> _store(StrideProfile profile, String rejection) async {
    if (!profile.isPlausible) {
      emit(
        state.copyWith(status: CalibrationStatus.implausible, error: rejection),
      );
      return;
    }

    try {
      await _profile.saveStride(profile.metres);
      if (isClosed) return;
      emit(state.copyWith(status: CalibrationStatus.done, profile: profile));
    } catch (e, stack) {
      AppLogger.error('Saving stride failed: $e', e, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: CalibrationStatus.failed,
          profile: profile,
          error:
              'Measured $profile, but it could not be saved. '
              'Try again with a connection.',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _steps.stop();
    return super.close();
  }
}
