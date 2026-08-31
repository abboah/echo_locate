import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/user_profile.dart';
import '../../../data/repository_mixin.dart';
import '../profile_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc(this._profiles) : super(const ProfileState()) {
    on<ProfileStarted>(_onStarted);
    on<ProfileNameChanged>(_onNameChanged);
  }

  final ProfileRepository _profiles;

  Future<void> _onStarted(
    ProfileStarted event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(status: ProfileStatus.loading));
    try {
      final profile = await _profiles.currentProfile();
      emit(state.copyWith(status: ProfileStatus.success, profile: profile));
    } catch (error) {
      // Broad on purpose: a narrow catch let Supabase, socket and
      // Hive errors escape, and a Bloc that never emits leaves the
      // screen spinning forever.
      emit(
        state.copyWith(
          status: ProfileStatus.failure,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  /// Renaming the contributor.
  ///
  /// Emits [ProfileStatus.saving] first so the screen can wait for the write
  /// rather than assuming it: telling somebody their name is saved when the
  /// request failed is the failure this screen can least afford.
  Future<void> _onNameChanged(
    ProfileNameChanged event,
    Emitter<ProfileState> emit,
  ) async {
    emit(state.copyWith(status: ProfileStatus.saving));
    try {
      final profile = await _profiles.updateName(event.fullName);
      emit(state.copyWith(status: ProfileStatus.success, profile: profile));
    } catch (error) {
      emit(
        // Still `success`: the profile on screen is the old one and is
        // perfectly valid. A failed rename is not a broken screen, and
        // dropping it to `failure` would replace the whole tab with an error.
        state.copyWith(
          status: ProfileStatus.success,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }
}
