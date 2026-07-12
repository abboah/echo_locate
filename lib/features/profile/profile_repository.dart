import '../../core/models/user_profile.dart';
import '../../data/repository_mixin.dart';
import '../auth/auth_repository.dart';

/// Contributor profile + mapping stats for the Profile tab.
abstract class ProfileRepository {
  Future<UserProfile> currentProfile();
}

/// Derives the profile from the signed-in [AuthRepository] user and attaches
/// mock contributor stats (real stats come from Supabase in Phase 2).
class MockProfileRepository with RepositoryMixin implements ProfileRepository {
  MockProfileRepository(this._auth);

  final AuthRepository _auth;

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
      );
    });
  }
}
