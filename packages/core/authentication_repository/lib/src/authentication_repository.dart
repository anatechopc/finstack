import 'package:authentication_repository/src/authentication_exception.dart';
import 'package:authentication_repository/src/authentication_result.dart';
import 'package:authentication_repository/src/authentication_status.dart';
import 'package:authentication_repository/src/data/authentication_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:loooans_helpers/logging_helpers.dart';

/// Handles all authentication repository functions
class AuthenticationRepository {
  ///
  /// [auth] FirebaseAuth instance from the main app.
  AuthenticationRepository();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthenticationDatabase _authenticationDatabase =
      AuthenticationDatabase();
  final log = Logger('authentication_repository');

  /// authenticate user based on email and password
  Future<AuthenticationResult> authenticate({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user == null) {
        return Future.error(
          AuthenticationException(
            message: 'Cannot read user from authentication',
          ),
        );
      }

      final idToken = await result.user!.getIdToken();

      return Future.value(
        AuthenticationResult(
          status: AuthenticationStatus.success,
          data: idToken,
        ),
      );
    } catch (error) {
      if (error is FirebaseAuthException) {
        return Future.error(
          AuthenticationException(
            message: 'Cannot login user: ${error.message}',
          ),
        );
      }

      return Future.error(
        AuthenticationException(
          message: 'Something went wrong while logging in user $error',
        ),
      );
    }
  }

  /// authenticate user based on user's idToken from firebase auth
  Future<AuthenticationResult> authenticateWithIdToken({
    required AuthCredential credential,
  }) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      if (result.user == null) {
        return Future.error(
          AuthenticationException(
            message: 'Cannot read user from authentication',
          ),
        );
      }

      final idToken = await result.user!.getIdToken();

      return Future.value(
        AuthenticationResult(
          status: AuthenticationStatus.success,
          data: idToken,
        ),
      );
    } catch (error) {
      if (error is FirebaseAuthException) {
        throw AuthenticationException(
          message: 'Cannot login user: ${error.message}',
        );
      }

      throw AuthenticationException(
        message: 'Something went wrong while logging in user: $error',
      );
    }
  }

  Future<void> updateUserPassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    log.info('user update password start');
    final user = this.user;

    if (user == null) {
      throw AuthenticationException(message: 'No user to update password');
    }

    if (user.email == null) {
      throw AuthenticationException(
        message: 'Cannot update password of user. No email',
      );
    }

    if (newPassword != confirmPassword) {
      throw AuthenticationException(
        message: 'Confirm password does not match with password',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    final reauthenticated =
        await _auth.currentUser!.reauthenticateWithCredential(credential);

    log.fine('re-authentication success');

    final currentUser = reauthenticated.user!;
    await currentUser.updatePassword(newPassword);

    log.info('Successfully updated user password');
  }

  /// stream idToken changes to the caller.
  ///
  /// NOTE:
  ///   * The caller should be responsible of closing the stream
  Stream<Future<String>> onIdTokenChanges() async* {
    if (_auth.currentUser == null) {
      throw AuthenticationException(message: 'Please sign in');
    }
    yield* _auth
        .idTokenChanges()
        .where((user) => user != null)
        .map((user) async => (await user!.getIdToken())!);
  }

  /// logs out the  user.
  Future<void> signOut({
    bool includeSession = true,
  }) async {
    // if (includeSession) {
    //   final uid = user?.uid;
    //
    //   if (uid != null) {
    //     await removeSession(uid);
    //   }
    // }

    return _auth.signOut();
  }

  /// gets the current logged in firebase user
  User? get user => _auth.currentUser;

  Stream<bool> listenForceLogout({required String companyId}) {
    return _authenticationDatabase.listenForceLogout(companyId: companyId);
  }

  Future<void> setSesion({
    required String uid,
    required String deviceName,
  }) async {
    return _authenticationDatabase.setSession(uid: uid, deviceName: deviceName);
  }

  Future<void> removeSession(String uid) async {
    return _authenticationDatabase.removeSession(uid);
  }

  /// creates a user record in firebase auth.
  Future<String> createUserCredential({
    required String email,
    required String password,
  }) async {
    if (_auth.currentUser?.isAnonymous ?? false) {
      await _auth.signOut();
    }

    await _auth.signInAnonymously();
    // _auth.currentUser now is set to anonymous
    final emailCredential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final userCredential = await _auth.currentUser?.linkWithCredential(emailCredential);
    final uid = userCredential?.user?.uid;

    if (uid == null) {
      throw AuthenticationException(message: 'cannot create user credential');
    }

    return uid;
  }

  /// [createAnonymousUser]
  ///
  /// Creates an anonymous firebase user.
  /// This is usually called when initializing
  /// a user placeholder when searching for loan
  /// offers and providers.
  Future<void> createAnonymousUser() {
    return _auth.signInAnonymously();
  }
}
