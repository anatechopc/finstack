import 'package:address_repository/address_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:user_repository/user_repository.dart';

class AuthenticationService {
  AuthenticationService._internal();

  static AuthenticationService? _instance;
  User? _user;
  Company? _company;
  Address? _address;
  String? _idToken;
  Device? _device;

  User get user {
    if (_user == null) {
      throw Exception('Please login');
    }

    return _user!;
  }

  set user(User user) {
    _user = user;
  }

  set device(Device device) {
    _device = device;
  }

  Device get device {
    if (_device == null) {
      throw Exception('No device. Please login');
    }

    return _device!;
  }

  bool get hasCompany => _company != null;

  Company get company {
    if (user.userRole.index > UserRole.customer.index) {
      if (_company == null) {
        throw Exception(
            'No company found for user ${user.completeNameEasternOrder}',);
      }

      return _company!;
    }

    throw Exception('Cannot get company for role ${user.userRole.label}');
  }

  set company(Company company) {
    _company = company;
  }

  Address get address {
    if (_address != null) {
      return _address!;
    }

    throw Exception('Address not found.');
  }

  set address(Address address) {
    _address = address;
  }

  bool get isLoggedIn {
    if (_user != null) {
      return !_user!.isPlaceholder;
    }

    return false;
  }

  String get idToken {
    if (_user == null || _idToken == null) {
      throw Exception('Please login');
    }

    return _idToken!;
  }

  set idToken(String token) {
    _idToken = token;
  }

  bool get isAdmin => user.isAdmin();

  bool get allowAddClients =>
      _company?.managementType == CompanyManagementType.selfManaged;

  static AuthenticationService get instance {
    _instance ??= AuthenticationService._internal();

    return _instance!;
  }

  void dispose() {
    _user = null;
    _company = null;
  }
}
