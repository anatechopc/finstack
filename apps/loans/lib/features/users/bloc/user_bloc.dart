import 'dart:typed_data';

import 'package:address_repository/address_repository.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/users/model/user_address.dart';
import 'package:loooans/services/address_builder.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'user_event.dart';
part 'user_state.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  UserBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        userRepository = context.read<UserRepository>(),
        userLoanViewRepository = context.read<UserLoanViewRepository>(),
        addressRepository = context.read<AddressRepository>(),
        storageRepository = context.read<StorageRepository>(),
        super(const UserState()) {
    on(_handleSelectUserEvent);
    on(_handleUpdateUserEvent);
    on(_handleResendInviteEvent);
  }

  /// Test seam mirroring RegistrationBloc.withDependencies: lets unit tests
  /// inject mocked repositories. [addressRepository] is optional because the
  /// real [AddressRepository] is a `final` class (so it can't be mocked) and
  /// the resend-invite path never touches it — only the select/update handlers
  /// do, and those aren't exercised in the resend-invite tests.
  /// [userLoanViewRepository] is typed as the base interface so it can be
  /// mocked; the bloc never calls a non-base method on it.
  UserBloc.withDependencies({
    required this.userRepository,
    required this.userLoanViewRepository,
    required this.storageRepository,
    this.addressRepository,
    AuthenticationService? authService,
  })  : authService = authService ?? AuthenticationService.instance,
        super(const UserState()) {
    on(_handleSelectUserEvent);
    on(_handleUpdateUserEvent);
    on(_handleResendInviteEvent);
  }

  /// SnackBar message emitted when a resend-invite succeeds. The UsersScreen
  /// listener filters on this so it only reacts to resend outcomes (UserBloc is
  /// app-scoped and emits success/error for unrelated flows too).
  static const resendInviteSuccessMessage = 'Invite re-sent.';

  /// SnackBar message emitted when a resend-invite fails.
  static const resendInviteErrorMessage = 'Could not resend the invite.';

  final log = Logger('user_bloc');

  final AuthenticationService authService;
  final UserRepository userRepository;
  final AddressRepository? addressRepository;
  final BaseRepository<UserLoanView> userLoanViewRepository;
  final StorageRepository storageRepository;

  User? _selectedUser;

  User? get selectedUser => _selectedUser;

  User? _selectedCoMaker;

  User? get selectedCoMaker => _selectedCoMaker;

  // List<User> _users = [];
  //
  // List<User> get users => _users;

  Stream<List<UserAddress>> get userAddresses =>
      userRepository.dataStream.asyncMap((users) async {
        return Future.wait(
          users.map((user) async {
            final address = await addressRepository!
                .getByDataType(
              id: user.id,
              type: DataType.user,
            )
                .onError((err, stacktrace) {
              log.severe('Error getting address: $err');
              return null;
            });

            return UserAddress(
                user: user,
                address: address ?? Address.noAddress(dataType: DataType.user),);
          }),
        );
      }).handleError((dynamic error) {
        log.severe('User error: $error');
      });

  Stream<List<User>> get users =>
      userRepository.dataStream.handleError((dynamic error) {
        log.severe('User error: $error');
      });

  final List<User> _coMakers = [];

  List<User> get coMakers => _coMakers;

  User get user {
    if (_selectedUser == null) {
      throw Exception('Select user first');
    }

    return _selectedUser!;
  }

  Address? _selectedUserAddress;

  Address? get address => _selectedUserAddress;

  void loadNext({
    required String companyId,
    bool customerOnly = false,
  }) {
    debugPrint('loadNext: $customerOnly');
    userRepository.loadNext(
      limit: null,
      reset: true,
      statements: [
        QueryStatement(
          field: 'company_id',
          isEqualTo: companyId,
        ),
        if (customerOnly)
          QueryStatement(
            field: 'user_role',
            isEqualTo: UserRole.customer.name,
          )
        else
          QueryStatement(
            field: 'user_role',
            whereIn: UserRole.values
                .whereNot((role) => [
                      UserRole.appAdmin,
                      UserRole.customer,
                    ].contains(role),)
                .map((role) => role.name),
          ),
      ],
    );
  }

  void selectUser(String userId) {
    add(SelectUserEvent(userId: userId));
  }

  void setUser(User user) {
    _selectedUser = user;
    emit(UserState.selected(user: user));
  }

  void setCoMaker(User user) {
    _selectedCoMaker = user;
    emit(UserState.selectedCoMaker(user: user));
  }

  void setCoMakers(List<User> users) {
    _coMakers
      ..clear()
      ..addAll(users);
    emit(UserState.selectedCoMakers(users: users));
  }

  void addCoMaker(User user) {
    _coMakers.add(user);
    log.finest('I am called');
    emit(UserState.selectedCoMaker(user: user));
    emit(const UserState.refresh());
  }

  void removeCoMaker(User user) {
    _coMakers.remove(user);
    emit(const UserState.unselectedCoMaker());
  }

  void refresh() {
    emit(const UserState.refresh());
  }

  void unselectUser() {
    _selectedUser = null;
    _selectedUserAddress = null;
    _coMakers.clear();
    emit(const UserState.unselected());
  }

  void updateUser(
    Map<String, dynamic> fields, {
    required User user,
  }) {
    add(UpdateUserEvent(fields: fields, user: user));
  }

  void resendInvite(String email) => add(ResendInviteEvent(email: email));

  Future<void> _handleResendInviteEvent(
    ResendInviteEvent event,
    Emitter<UserState> emit,
  ) async {
    try {
      emit(const UserState.loading(isLoading: true));
      await userRepository.sendPasswordSetupLink(email: event.email);
      emit(const UserState.loading());
      emit(const UserState.success(UserBloc.resendInviteSuccessMessage));
    } catch (err) {
      log.severe('ResendInvite error: $err', err);
      emit(const UserState.loading());
      emit(const UserState.error(UserBloc.resendInviteErrorMessage));
    }
  }

  Future<void> _handleSelectUserEvent(
    SelectUserEvent event,
    Emitter<UserState> emit,
  ) async {
    try {
      emit(const UserState.loading(isLoading: true));
      final userId = event.userId;
      final results = await Future.wait([
        userRepository.get(id: userId),
        addressRepository!
            .getByDataType(
          id: userId,
          type: DataType.user,
        )
            .onError((err, stacktrace) {
          return null;
        }),
      ]);
      _selectedUser = results[0]! as User;
      _selectedUserAddress = results[1] as Address?;
      emit(const UserState.loading());
      emit(UserState.selected(user: _selectedUser!));
    } on Exception catch (err) {
      log.severe('Cannot select user: $err');
      emit(const UserState.loading());
      emit(UserState.error('Cannot select user: $err'));
    } catch (err) {
      log.severe('Select user error', err);
    }
  }

  Future<void> _handleUpdateUserEvent(
    UpdateUserEvent event,
    Emitter<UserState> emit,
  ) async {
    try {
      emit(const UserState.loading(isLoading: true));
      final fields = event.fields;
      final user = event.user;
      final originalMobile = user.mobileNumber;
      final newMobile = fields['mobile_number'] as String;
      final mobileChanged =
          originalMobile != newMobile && user.id == authService.user.id;

      final tempUser = user
        ..firstName = fields['first_name'] as String
        ..lastName = fields['last_name'] as String
        ..middleName = fields['middle_name'] as String?
        ..mobileNumber = newMobile
        // ..emailAddress = fields['email_address'] as String
        ..birthDate = fields['birth_date'] as DateTime;

      final results = await Future.wait([
        userRepository.update(data: tempUser).then((user) async {
          final tempProfilePhotoData =
              fields['profile_picture'] as Map<String, dynamic>?;

          if (tempProfilePhotoData != null) {
            final photosFolder = 'users/${user.id}';
            final profilePhotoUrl = await storageRepository.upload(
              data: tempProfilePhotoData['bytes'] as Uint8List,
              folder: photosFolder,
              fileName:
                  'profile_pic_${DateTime.timestamp().toIso8601String()}_${tempProfilePhotoData['name'] as String}',
              includeOriginal: true,
            );

            return userRepository
                .update(
              data: user..profilePhotoUrl = profilePhotoUrl,
            )
                .then((user) {
              if (user.id == authService.user.id) {
                authService.user = user;
              }
              return user;
            });
          }

          return user;
        }),
        if (!authService.hasCompany)
          Future.microtask(() {
            final addr = authService.address;
            AddressBuilder.updateFromFields(addr, fields);
            return addressRepository!.update(data: addr);
          }),
      ]);

      emit(const UserState.loading());
      final updatedUser = results[0] as User?;
      if (mobileChanged && updatedUser != null) {
        emit(UserState.requireMobileVerify(user: updatedUser));
        return;
      }
      emit(UserState.success(
        'Successfully updated user',
        user: updatedUser,
      ),);
    } catch (err) {
      log.severe('Update error: $err', err);
      emit(const UserState.loading());
      emit(const UserState.error('Something went wrong while adding user.'));
    }
  }

  Future<List<User>> getCustomersByCompany(String companyId,
      {String query = '',}) {
    return userRepository.load(
      limit: null,
      reset: true,
      statements: [
        QueryStatement(
          field: 'company_id',
          isEqualTo: companyId,
        ),
        QueryStatement(
          field: 'user_role',
          isEqualTo: UserRole.customer.name,
        ),
      ],
    ).then((users) {
      if (query.isEmpty) {
        return users;
      }

      return users
          .where(
            (user) => user.completeNameWesternOrder
                .toLowerCase()
                .contains(query.toLowerCase()),
          )
          .toList();
    }).then((users) {
      if (users.isNotEmpty) {
        return users;
      }

      return [
        // User.createPlaceholder(lastName: query),
      ];
    });
  }
}
