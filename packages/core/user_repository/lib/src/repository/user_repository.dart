import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/src/data/database/user_firestore_service.dart';
import 'package:user_repository/src/data/network/user_network_service.dart';
import 'package:user_repository/src/model/device.dart';
import 'package:user_repository/src/model/request_otp_response.dart';
import 'package:user_repository/src/model/user.dart';

/// User repository class
class UserRepository implements BaseRepository<User> {
  /// constructor
  UserRepository()
      : _firestoreService = UserFirestoreService(),
        _networkService = UserNetworkService();

  late final UserFirestoreService _firestoreService;
  late final UserNetworkService _networkService;

  @override
  Future<User> add({required User data}) async {
    if (data.isPlaceholder) {
      throw Exception('User is a placeholder. Please recreate user again');
    }

    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toUser());
  }

  @override
  Future<User> delete({required User data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toUser());
  }

  @override
  Future<User> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toUser());
  }

  @override
  Future<List<User>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    return _firestoreService
        .load(
          statements: statements,
          limit: limit,
          page: page,
          reset: reset,
        )
        .then((value) => value.map((result) => result.toUser()).toList());
  }

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    _firestoreService.loadNext(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    );
  }

  @override
  Future<User> update({required User data, bool nameUpdated = false}) async {
    if (nameUpdated) {
      UserLoanViewRepository().updateUserData(user: data);
    }

    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toUser());
  }

  /// Provisions a user server-side. Returns the server-minted uid and whether
  /// the invite email was sent. See [UserNetworkService.createUser].
  Future<({String uid, bool inviteSent})> createUser({
    required String role,
    required Map<String, dynamic> user,
    required String idToken,
    Map<String, dynamic>? address,
  }) {
    return _networkService.createUser(
      role: role,
      user: user,
      idToken: idToken,
      address: address,
    );
  }

  /// Requests a set-password / reset link email for [email].
  Future<void> sendPasswordSetupLink({required String email}) {
    return _networkService.sendPasswordSetupLink(email: email);
  }

  Future<RequestOtpResponse> requestOtp({
    required String idToken,
    String purpose = 'mobile_number',
  }) {
    return _networkService.requestOtp(
      idToken: idToken,
      purpose: purpose,
    );
  }

  Future<RequestOtpResponse> requestOtpForUser({
    required String idToken,
    required String targetUserId,
    String reason = 'payment',
  }) {
    return _networkService.requestOtpForUser(
      idToken: idToken,
      targetUserId: targetUserId,
      reason: reason,
    );
  }

  Future<bool> verifyOtp({
    required String idToken,
    required String token,
    required String otp,
  }) {
    return _networkService.verifyOtp(
      idToken: idToken,
      token: token,
      otp: otp,
    );
  }

  Future<void> addDevice({
    required String userId,
    required Device device,
  }) {
    return _firestoreService.addDevice(
      userId: userId,
      device: device.toEntity(),
    );
  }

  Future<void> updateDeviceToken({
    required String userId,
    required Device device,
  }) {
    return _firestoreService.updateDeviceToken(
      userId: userId,
      deviceInstanceId: device.id,
      token: device.token,
    );
  }

  Future<Device?> getDevice({
    required String userId,
    required String deviceInstanceId,
  }) {
    return _firestoreService.getDevice(
      userId: userId,
      deviceInstanceId: deviceInstanceId,
    ).then((value) => value?.toDevice());
  }

  Future<int> get count => _firestoreService.count;

  @override
  Stream<List<User>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toUser()).toList());
}
