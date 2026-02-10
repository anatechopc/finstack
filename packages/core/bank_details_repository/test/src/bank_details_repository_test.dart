// ignore_for_file: prefer_const_constructors

import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankDetailsRepository', () {
    test('can be instantiated', () {
      expect(BankDetailsRepository(), isNotNull);
    });
  });
}
