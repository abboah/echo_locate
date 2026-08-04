import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';
part 'auth_user.g.dart';

/// The signed-in user (auth identity only; contributor stats live in
/// [UserProfile]).
@freezed
abstract class AuthUser with _$AuthUser {
  const AuthUser._();

  const factory AuthUser({
    required String id,
    required String fullName,
    required String email,
  }) = _AuthUser;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      _$AuthUserFromJson(json);

  /// Single letter for the avatar chip (Home header, Profile).
  String get initial => fullName.isEmpty ? '?' : fullName[0].toUpperCase();
}
