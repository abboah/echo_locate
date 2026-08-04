import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

/// Contributor profile shown on the Profile tab: identity + mapping stats.
@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    required String fullName,
    required String email,
    @Default(0) int buildingsMapped,
    @Default(0) int floorsMapped,
    @Default(0) int roomsMapped,
    @Default('New mapper') String rankLabel,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}
