import 'package:firebase_database/firebase_database.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:user_repository/src/model/user_otp_entity.dart';

/// IMPORTANT NOTE: vehicle location reference is
/// `vehicles/{vehicleId}/locations`
class UserOtpRealtimeDatabaseService
    implements BaseDatabaseService<UserOtpEntity> {
  final _log = Logger('location_firebase_database_service');

  @override
  Future<UserOtpEntity> add({required UserOtpEntity data}) async {
    final db = FirebaseDatabase.instance;
    final ref = db.ref('users/${data.id}/otp');
    final refData = ref.push();
    final updatedData = data..id = refData.key ?? data.createdAt.toString();

    try {
      await refData.set(updatedData.toJson());
    } catch (err) {
      _log.fine('database err: $err');
    }

    return updatedData;
  }

  @override
  Future<UserOtpEntity> delete({required UserOtpEntity data}) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<UserOtpEntity> get({required String id}) async {
    final db = FirebaseDatabase.instance;
    final ref = db.ref('otp/$id');
    final data = await ref.get();

    if (data.value == null) {
      throw Exception('No otp value found');
    }

    return UserOtpEntity.fromJson(data.value! as Map<String, dynamic>);
  }

  @override
  Future<List<UserOtpEntity>> load(
      {List<QueryStatement>? statements,
        int? limit = defaultDataLimit,
        int? page,
        bool reset = false,}) {
    // TODO: implement load
    throw UnimplementedError();
  }

  @override
  Future<UserOtpEntity> update({required UserOtpEntity data}) {
    // TODO: implement update
    throw UnimplementedError();
  }
}
