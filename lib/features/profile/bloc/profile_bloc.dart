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
    } on OperationFailure catch (f) {
      emit(state.copyWith(status: ProfileStatus.failure, error: f.message));
    }
  }
}
