import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/auth/supabase_auth_repository.dart';

void main() {
  test('network failure surfaces a friendly connection message', () async {
    // Nothing listens on this port — every request fails at the socket
    // level, exactly like a phone with no route to Supabase.
    final client = SupabaseClient('http://127.0.0.1:9', 'test-key');
    final repo = SupabaseAuthRepository(client);

    try {
      await repo.signInWithEmail(email: 'a@b.com', password: 'password123');
      fail('expected OperationFailure');
    } on OperationFailure catch (f) {
      expect(f.message.toLowerCase(), contains('connection'));
      expect(f.message.toLowerCase(), isNot(contains('exception')));
      expect(f.message.toLowerCase(), isNot(contains('socket')));
    } finally {
      await client.dispose();
    }
  });
}
