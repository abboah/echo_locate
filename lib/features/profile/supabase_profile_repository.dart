import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/user_profile.dart';
import '../../data/repository_mixin.dart';
import 'profile_repository.dart';

/// Supabase-backed contributor profile: identity from `profiles` (created by
/// the `on_auth_user_created` trigger), mapping totals from the
/// `contributor_stats()` RPC.
class SupabaseProfileRepository
    with RepositoryMixin
    implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  /// Mapper levels shown under the name on the Profile tab.
  static String _rankFor(int buildingsMapped) => switch (buildingsMapped) {
    0 => 'New mapper',
    1 || 2 => 'Mapper · Level 1',
    3 || 4 || 5 => 'Mapper · Level 2',
    _ => 'Mapper · Level 3',
  };

  @override
  Future<void> saveStride(double metresPerStep) {
    return runOperation('profile_save_stride', () async {
      final user = _client.auth.currentUser;
      if (user == null) throw const OperationFailure('Not signed in');

      await _client
          .from('profiles')
          .update({'stride_length_m': metresPerStep})
          .eq('id', user.id);
    });
  }

  @override
  Future<UserProfile> currentProfile() {
    return runOperation('profile_current', () async {
      final user = _client.auth.currentUser;
      if (user == null) throw const OperationFailure('Not signed in');

      final row = await _client
          .from('profiles')
          .select('full_name, email, stride_length_m')
          .eq('id', user.id)
          .maybeSingle();

      final stats = await _client.rpc<List<dynamic>>('contributor_stats');
      final s = stats.isEmpty
          ? const <String, dynamic>{}
          : stats.first as Map<String, dynamic>;

      final buildings = (s['buildings_mapped'] as num?)?.toInt() ?? 0;
      // The profile row is created by a trigger, but a user who signed up
      // before the trigger existed won't have one — fall back to auth metadata.
      final fullName = (row?['full_name'] as String?)?.trim();
      final email = (row?['email'] as String?) ?? user.email ?? '';

      return UserProfile(
        id: user.id,
        fullName: fullName != null && fullName.isNotEmpty
            ? fullName
            : user.userMetadata?['full_name'] as String? ??
                  (email.contains('@') ? email.split('@').first : 'Mapper'),
        email: email,
        buildingsMapped: buildings,
        floorsMapped: (s['floors_mapped'] as num?)?.toInt() ?? 0,
        roomsMapped: (s['rooms_mapped'] as num?)?.toInt() ?? 0,
        rankLabel: _rankFor(buildings),
        strideLengthM: (row?['stride_length_m'] as num?)?.toDouble(),
      );
    });
  }
}
