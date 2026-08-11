import '../../core/models/user_profile.dart';
import '../../data/repository_mixin.dart';
import '../auth/auth_repository.dart';

/// Contributor profile + mapping stats for the Profile tab.
abstract class ProfileRepository {
  Future<UserProfile> currentProfile();

  /// Stores the user's calibrated step length in metres.
  ///
  /// Guidance converts every stored leg through this number, so it is the one
  /// per-user value that changes what the app says out loud. Callers must
  /// check `StrideProfile.isPlausible` first — this does not re-validate.
  Future<void> saveStride(double metresPerStep);
}

/// Derives the profile from the signed-in [AuthRepository] user and attaches
/// mock contributor stats (real stats come from Supabase in Phase 2).
class MockProfileRepository with RepositoryMixin implements ProfileRepository {
  MockProfileRepository(this._auth);

  final AuthRepository _auth;

  /// Survives for the session only — the mock has no backing store, which is
  /// enough for the calibration screen to read back what it just wrote.
  double? _strideLengthM;

  @override
  Future<void> saveStride(double metresPerStep) async {
    _strideLengthM = metresPerStep;
  }

  @override
  Future<UserProfile> currentProfile() {
    return runEphemeralQuery('profile:current', () async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final user = _auth.currentUser;
      if (user == null) {
        throw const OperationFailure('Not signed in');
      }
      return UserProfile(
        id: user.id,
        fullName: user.fullName,
        email: user.email,
        buildingsMapped: 3,
        floorsMapped: 7,
        roomsMapped: 24,
        rankLabel: 'Mapper · Level 2',
        strideLengthM: _strideLengthM,
      );
    });
  }
}
