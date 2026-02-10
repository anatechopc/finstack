import 'package:address_repository/address_repository.dart';
import 'package:user_repository/user_repository.dart';

final class UserAddress {

  const UserAddress({
    required this.user,
    required this.address,
  });
  final User user;
  final Address address;
}