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

  /// Changes the name shown on the user's contributions.
  ///
  /// It comes from whatever was typed at sign-up — or from a Google account,
  /// which is often a legal name somebody would rather not have against every
  /// building they map.
  Future<UserProfile> updateName(String fullName);

  /// Deletes the account and signs the user out.
  ///
  /// **The traced plans stay.** They are the crowdsourced map other people
  /// depend on, and leaving is not a reason to unmap a building for everybody
  /// else — attribution is dropped instead. The confirmation dialog says so
  /// before it asks, because a destructive action that hides what it destroys
  /// is not consent.
  Future<void> deleteAccount();
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

  /// Session-scoped, like the stride: enough for the screen to read back what
  /// it just wrote, which is all the offline path promises.
  String? _fullName;

  @override
  Future<UserProfile> updateName(String fullName) async {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) {
      throw const OperationFailure('Your name cannot be empty.');
    }
    _fullName = trimmed;
    RepositoryMixin.clearEphemeralCache();
    return currentProfile();
  }

  @override
  Future<void> deleteAccount() async {
    // Nothing to delete without a backing store; signing out is the whole of
    // what "leaving" can mean offline, and the caller does that either way.
    _fullName = null;
    _strideLengthM = null;
    RepositoryMixin.clearEphemeralCache();
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
        fullName: _fullName ?? user.fullName,
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
