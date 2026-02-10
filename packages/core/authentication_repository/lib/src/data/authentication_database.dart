import 'package:authentication_repository/authentication_repository.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthenticationDatabase {
  Stream<bool> listenForceLogout({required String companyId}) {
    final forceLogoutRef = FirebaseDatabase.instance.ref('companies/$companyId/authentication/force_logout');
    return forceLogoutRef.onValue.map((event) {
      return event.snapshot.value as bool? ?? false;
    });
  }

  Future<void> setSession({
    required String uid,
    required String deviceName,
  }) async {
    final sessionRef = FirebaseDatabase.instance.ref('app/sessions/$uid');
    final snapshot = await sessionRef.get();
    final session = snapshot.value;

    if (session != null) {
      if (session is Map) {
        // throw error here
        final lastLogin = DateTime.fromMillisecondsSinceEpoch(
          session['last_login'] as int,
          isUtc: true,
        );
        final deviceName = session['device_name'] as String;

        throw SessionException(
          deviceName: deviceName,
          lastLogin: lastLogin,
          message: 'Already logged in',
        );
      }
    } else {
      await sessionRef.set({
        'device_name': deviceName,
        'last_login': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> removeSession(String uid) async {
    final sessionRef = FirebaseDatabase.instance.ref('app/sessions/$uid');
    await sessionRef.remove();
  }
}
