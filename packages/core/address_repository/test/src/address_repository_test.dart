// ignore_for_file: prefer_const_constructors

import 'package:address_repository/address_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AddressRepository', () {
    test('can be instantiated', () {
      expect(AddressRepository(), isNotNull);
    });
  });
}
