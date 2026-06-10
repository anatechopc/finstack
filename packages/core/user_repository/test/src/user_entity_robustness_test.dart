// Regression tests: old/incomplete user documents (missing `sex` or
// `employment_details`) must still deserialize so those accounts can log in.
import 'package:flutter_test/flutter_test.dart';
import 'package:user_repository/src/model/employment_status.dart';
import 'package:user_repository/src/model/sex.dart';
import 'package:user_repository/src/model/user_entity.dart';

Map<String, dynamic> baseJson() => <String, dynamic>{
      'updated_at': 1726137187726,
      'created_at': 1726137187726,
      'id': 'XouShJ0y9xeJzp9DXsDT0esI2EI2',
      'last_name': 'Dugd',
      'first_name': 'Asdf',
      'birth_date': 1725120000000,
      'mobile_number': '9420981814',
      'email_address': 'leizelduldulao@gmail.com',
      'user_role': 'customer',
      'verificationStatus': 0,
    };

void main() {
  group('UserEntity.fromJson robustness', () {
    test('defaults a doc missing `sex` to Sex.other (no throw)', () {
      final json = baseJson(); // no 'sex'
      late final UserEntity user;
      expect(() => user = UserEntity.fromJson(json), returnsNormally);
      expect(user.sex, Sex.other);
    });

    test('treats an explicit null `sex` as Sex.other', () {
      final json = baseJson()..['sex'] = null;
      final user = UserEntity.fromJson(json);
      expect(user.sex, Sex.other);
    });

    test('treats an unrecognized `sex` value as Sex.other', () {
      final json = baseJson()..['sex'] = 'nonbinary';
      final user = UserEntity.fromJson(json);
      expect(user.sex, Sex.other);
    });

    test('still decodes a present `sex`', () {
      final json = baseJson()..['sex'] = 'female';
      final user = UserEntity.fromJson(json);
      expect(user.sex, Sex.female);
    });

    test(
        'deserializes a doc missing `employment_details` without throwing '
        '(defaults to a blank)', () {
      final json = baseJson(); // no 'employment_details'
      late final UserEntity user;
      expect(() => user = UserEntity.fromJson(json), returnsNormally);
      expect(
        user.employmentDetails.employmentStatus,
        EmploymentStatus.selfEmployed,
      );
      expect(user.employmentDetails.salaryDays, isEmpty);
    });

    test('round-trips a fully-populated doc', () {
      final json = baseJson()
        ..['sex'] = 'male'
        ..['employment_details'] = <String, dynamic>{
          'updated_at': 1726137187726,
          'created_at': 1726137187726,
          'id': 'emp-1',
          'user_id': 'XouShJ0y9xeJzp9DXsDT0esI2EI2',
          'employment_status': 'employed',
          'salary_days': <int>[15, 30],
        };
      final user = UserEntity.fromJson(json);
      expect(user.sex, Sex.male);
      expect(user.employmentDetails.id, 'emp-1');

      // A doc with no `sex` serializes back as the 'other' fallback.
      final defaulted = UserEntity.fromJson(baseJson());
      expect(defaulted.toJson()['sex'], 'other');
    });
  });
}
