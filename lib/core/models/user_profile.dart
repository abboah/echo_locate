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

    /// Metres per step, from the calibration walk. Null until the user
    /// calibrates — guidance then falls back to a height estimate or
    /// [StrideProfile.fallback] rather than refusing to guide.
    ///
    /// Stored as a bare number because `profiles.stride_length_m` is a single
    /// numeric column; how it was obtained is a runtime concern, not a
    /// persisted one.
    double? strideLengthM,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}
