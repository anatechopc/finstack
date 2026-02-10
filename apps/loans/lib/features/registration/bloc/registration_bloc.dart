import 'dart:async';
import 'dart:typed_data';

import 'package:address_repository/address_repository.dart';
import 'package:authentication_repository/authentication_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/address_builder.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:loooans_helpers/loooans_helpers.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'registration_event.dart';
part 'registration_state.dart';

class RegistrationBloc extends Bloc<RegistrationEvent, RegistrationState> {
  RegistrationBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        _authenticationRepository = context.read<AuthenticationRepository>(),
        _userRepository = context.read<UserRepository>(),
        _storageRepository = context.read<StorageRepository>(),
        _companyRepository = context.read<CompanyRepository>(),
        _addressRepository = context.read<AddressRepository>(),
        super(RegisterInitial()) {
    on(_handleSubmitUserRegistrationEvent);
    on(_handleSubmitProviderRegistrationEvent);
    on(_handleSubmitManagedUserRegistrationEvent);
  }

  final AuthenticationService authService;
  final AuthenticationRepository _authenticationRepository;
  final UserRepository _userRepository;
  final StorageRepository _storageRepository;
  final CompanyRepository _companyRepository;
  final AddressRepository _addressRepository;
  final log = Logger('register_bloc');

  void registerUser(Map<String, dynamic> data) {
    add(
      SubmitUserRegistrationEvent(
        fields: data,
      ),
    );
  }

  void registerManagedUser(Map<String, dynamic> data) {
    add(
      SubmitManagedUserRegistrationEvent(
        fields: data,
      ),
    );
  }

  void registerProvider(Map<String, dynamic> data) {
    add(SubmitProviderRegistrationEvent(fields: data));
  }

  Future<void> _handleSubmitUserRegistrationEvent(
    SubmitUserRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      emit(RegistrationLoadingState(isLoading: true));

      final data = event.fields;
      final tempProfilePhotoData =
          data['profile_picture'] as Map<String, dynamic>?;
      final tempSelfieValidIdData =
          data['selfie_valid_id'] as Map<String, dynamic>;

      if (tempProfilePhotoData == null) {
        throw Exception(
            'Please include profile and selfie with valid id photos',);
      }

      final email = data['email_address'] as String;
      final password = data['password'] as String;
      final uid = await _authenticationRepository.createUserCredential(
        email: email,
        password: password,
      );

      final photosFolder = 'users/$uid';

      final imageUrls = await Future.wait([
        _storageRepository.upload(
          data: tempProfilePhotoData['bytes'] as Uint8List,
          folder: photosFolder,
          fileName:
              'profile_pic_${DateTime.timestamp().toIso8601String()}_${tempProfilePhotoData['name'] as String}',
          includeOriginal: true,
        ),
        _storageRepository.upload(
          data: tempSelfieValidIdData['bytes'] as Uint8List,
          folder: photosFolder,
          fileName:
              'selfie_valid_id_${DateTime.timestamp().toIso8601String()}_${tempSelfieValidIdData['name'] as String}',
          includeOriginal: true,
        ),
      ]);

      final profilePhotoUrl = imageUrls[0];

      final photoWithValidIdUrl = imageUrls[1];

      final tempUser = User.create(
        uid: uid,
        firstName: data['first_name'] as String,
        lastName: data['last_name'] as String,
        middleName: data['middle_name'] as String?,
        mobileNumber: data['mobile_number'] as String,
        emailAddress: email,
        profilePhotoUrl: profilePhotoUrl,
        photoWithValidIdUrl: photoWithValidIdUrl,
        userRole: UserRole.customer,
        birthDate: data['birth_date'] as DateTime,
        facebookProfileUrl: data['facebook_profile'] as String?,
        sex: data['sex'] as Sex,
        employmentDetails: EmploymentDetails.createBlank()
          ..id = StringHelper.generateId(length: 12)
          ..userId = uid
          ..employmentStatus = data['employment_status'] as EmploymentStatus
          ..employerName = data['employer_name'] as String?
          ..salaryDays = (data['salary_days'] as String?)?.toIntList() ?? [],
        businessName: data['business_name'] as String?,
      );

      final user = await _userRepository.add(data: tempUser);

      final tempAddress = AddressBuilder.buildFromFields(
        data,
        dataId: user.id,
        dataType: DataType.user,
      );
      final _ = await _addressRepository.add(data: tempAddress);
      emit(RegistrationLoadingState());
      emit(RegistrationSuccessState(message: 'Successfully registered user'));
    } catch (err) {
      log.severe('SubmitUserRegistrationEvent: $err', err);
      emit(RegistrationLoadingState());
      emit(RegistrationErrorState(
          message: 'Cannot proceed to registration: $err',),);
    }
  }

  Future<void> _handleSubmitManagedUserRegistrationEvent(
    SubmitManagedUserRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      emit(RegistrationLoadingState(isLoading: true));
      final data = event.fields;

      final tempUser = User.createManagedCustomer(
        firstName: data['first_name'] as String,
        lastName: data['last_name'] as String,
        middleName: data['middle_name'] as String?,
        mobileNumber: data['mobile_number'] as String,
        emailAddress: data['email_address'] as String?,
        profilePhotoUrl: null,
        photoWithValidIdUrl: null,
        birthDate: data['birth_date'] as DateTime,
        sex: data['sex'] as Sex,
        employmentDetails: EmploymentDetails.createBlank(),
        businessName: data['business_name'] as String?,
        companyId: authService.company.id,
      );

      final user = await _userRepository.add(data: tempUser).then((user) async {
        final tempProfilePhotoData =
            data['profile_picture'] as Map<String, dynamic>?;
        final tempSelfieValidIdData =
            data['selfie_valid_id'] as Map<String, dynamic>?;

        final photosFolder = 'users/${user.id}';

        ImageUrl? profilePhotoUrl;

        if (tempProfilePhotoData != null) {
          profilePhotoUrl = await _storageRepository.upload(
            data: tempProfilePhotoData['bytes'] as Uint8List,
            folder: photosFolder,
            fileName:
                'profile_pic_${DateTime.timestamp().toIso8601String()}_${tempProfilePhotoData['name'] as String}',
            includeOriginal: true,
          );
        }

        ImageUrl? photoWithValidIdUrl;

        if (tempSelfieValidIdData != null) {
          photoWithValidIdUrl = await _storageRepository.upload(
            data: tempSelfieValidIdData['bytes'] as Uint8List,
            folder: photosFolder,
            fileName:
                'selfie_valid_id_${DateTime.timestamp().toIso8601String()}_${tempSelfieValidIdData['name'] as String}',
            includeOriginal: true,
          );
        }

        final salaryDays = (data['salary_days'] as String?)?.toIntList();

        if (salaryDays != null) {
          if (salaryDays.first == salaryDays.last) {
            salaryDays
              ..clear()
              ..add(salaryDays.first);
          } else {
            salaryDays.sort((d1, d2) {
              if (d1 > d2) {
                return d2;
              } else {
                return d1;
              }
            });
          }
        }

        final employmentDetails = user.employmentDetails
          ..id = StringHelper.generateId(length: 12)
          ..userId = user.id
          ..employmentStatus = data['employment_status'] as EmploymentStatus
          ..employerName = data['employer_name'] as String?
          ..salaryDays = salaryDays ?? [];

        return _userRepository.update(
          data: user
            ..profilePhotoUrl = profilePhotoUrl
            ..photoWithValidIdUrl = photoWithValidIdUrl
            ..employmentDetails = employmentDetails,
        );
      });

      final tempAddress = AddressBuilder.buildFromFields(
        data,
        dataId: user.id,
        dataType: DataType.user,
      );
      final _ = await _addressRepository.add(data: tempAddress);
      emit(RegistrationLoadingState());
      emit(RegistrationSuccessState(message: 'Successfully registered user'));
    } catch (err) {
      log.severe('SubmitManagedUserRegistrationEvent: $err', err);
      emit(RegistrationLoadingState());
      emit(RegistrationErrorState(
          message: 'Cannot proceed to registration: $err',),);
    }
  }

  Future<void> _handleSubmitProviderRegistrationEvent(
    SubmitProviderRegistrationEvent event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      Future<List<ImageUrl>> uploadImages(
        Map<String, dynamic> data,
        String photosFolder,
      ) async {
        final tempProfilePhotoData =
            data['profile_picture'] as Map<String, dynamic>?;
        final tempSelfieValidIdData =
            data['selfie_valid_id'] as Map<String, dynamic>?;

        final imageUrls = await Future.wait([
          if (tempProfilePhotoData != null) ...[
            _storageRepository.upload(
              data: tempProfilePhotoData['bytes'] as Uint8List,
              folder: photosFolder,
              fileName:
                  'profile_pic_${DateTime.timestamp().toIso8601String()}_${tempProfilePhotoData['name'] as String}',
              includeOriginal: true,
              forceDecodeToImage: true,
            ),
          ],
          if (tempSelfieValidIdData != null) ...[
            _storageRepository.upload(
              data: tempSelfieValidIdData['bytes'] as Uint8List,
              folder: photosFolder,
              fileName:
                  'selfie_valid_id_${DateTime.timestamp().toIso8601String()}_${tempSelfieValidIdData['name'] as String}',
              includeOriginal: true,
              forceDecodeToImage: true,
            ),
          ],
        ]);

        return imageUrls;
      }

      emit(RegistrationLoadingState(isLoading: true));
      var company = authService.hasCompany
          ? authService.company
          : null;
      final data = event.fields;
      final email = data['email_address'] as String;
      var userRole = data['user_role'] as UserRole?;
      String? userId;
      final tempProfilePhotoData =
          data['profile_picture'] as Map<String, dynamic>?;
      final tempSelfieValidIdData =
          data['selfie_valid_id'] as Map<String, dynamic>?;

      final tempAddress = AddressBuilder.buildFromFields(data);

      if (userRole == null) {
        userRole = UserRole.admin;
        if (tempProfilePhotoData == null || tempSelfieValidIdData == null) {
          throw Exception(
            'Please include profile and selfie with valid id photos',
          );
        }

        final password = data['password'] as String;
        userId = await _authenticationRepository.createUserCredential(
          email: email,
          password: password,
        );

        final tempCompany = Company.create(
          name: data['company_name'] as String,
          tin: data['tin'] as String,
          emailAddress: email,
          type: data['type'] as CompanyType,
          tagLine: data['tag_line'] as String,
          secNumber: data['sec_number'] as String?,
          // TODO: super admin console to update CompanyManagementType of company to selfManaged if they requested.
          managementType: CompanyManagementType.app,
        );

        company = await _companyRepository
            .add(data: tempCompany)
            .then((company) async {
          final tempCompanyLogoData =
              data['company_logo'] as Map<String, dynamic>?;
          ImageUrl? companyLogo;

          if (tempCompanyLogoData != null) {
            companyLogo = await _storageRepository.upload(
              data: tempCompanyLogoData['bytes'] as Uint8List,
              folder: 'companies/${company.id}',
              fileName:
                  'company_logo_${DateTime.timestamp().toIso8601String()}_${tempCompanyLogoData['name'] as String}',
              includeOriginal: true,
            );
          }

          unawaited(
            _addressRepository.add(
              data: tempAddress
                ..dataId = company.id
                ..dataType = DataType.provider,
            ),
          );

          return _companyRepository.update(
            data: company..companyProfilePhotoUrl = companyLogo,
          );
        });
      } else {
        if (userRole == UserRole.customer) {
          throw Exception('Cannot proceed to registration: Customer role not allowed');
        }

        // TODO(deibeeed): This is a temp password. It would be best to have a generated temporary password and
        // send it to the user via email.
        const password = 'Password123!';
        userId = await _authenticationRepository.createUserCredential(
          email: email,
          password: password,
        );
        unawaited(
          _addressRepository.add(
            data: tempAddress
              ..dataId = userId
              ..dataType = DataType.user,
          ),
        );
      }

      if (company == null) {
        throw Exception('Cannot proceed to registration: Company not found');
      }

      final photosFolder = 'users/$userId';
      final imageUrls = await uploadImages(data, photosFolder);

      ImageUrl? profilePhotoUrl;

      if (imageUrls.isNotEmpty) {
        profilePhotoUrl = imageUrls[0];
      }

      if (userRole == UserRole.admin) {
        final photoWithValidIdUrl = imageUrls[1];

        final tempUser = User.create(
          uid: userId,
          firstName: data['first_name'] as String,
          lastName: data['last_name'] as String,
          middleName: data['middle_name'] as String?,
          mobileNumber: data['mobile_number'] as String,
          emailAddress: email,
          profilePhotoUrl: profilePhotoUrl!,
          photoWithValidIdUrl: photoWithValidIdUrl,
          userRole: userRole,
          birthDate: data['birth_date'] as DateTime,
          companyId: company.id,
          sex: data['sex'] as Sex,
          employmentDetails: EmploymentDetails.createBlank()
            ..id = StringHelper.generateId(length: 12)
            ..userId = userId
            ..employmentStatus = data['employment_status'] as EmploymentStatus
            ..employerName = data['employer_name'] as String?
            ..salaryDays = (data['salary_days'] as String?)?.toIntList() ?? [],
          businessName: data['business_name'] as String?,
        );

        final _ = await _userRepository.add(data: tempUser);
      } else {

        final tempUser = User.createManagedUser(
          uid: userId,
          firstName: data['first_name'] as String,
          lastName: data['last_name'] as String,
          middleName: data['middle_name'] as String?,
          mobileNumber: data['mobile_number'] as String,
          emailAddress: email,
          profilePhotoUrl: profilePhotoUrl,
          userRole: userRole,
          birthDate: data['birth_date'] as DateTime,
          companyId: company.id,
          sex: data['sex'] as Sex,
          employmentDetails: EmploymentDetails.createBlank()
            ..id = StringHelper.generateId(length: 12)
            ..userId = userId
            ..employmentStatus = data['employment_status'] as EmploymentStatus
            ..employerName = data['employer_name'] as String?
            ..salaryDays = (data['salary_days'] as String?)?.toIntList() ?? [],
          businessName: data['business_name'] as String?,
        );

        final _ = await _userRepository.add(data: tempUser);
      }
      emit(RegistrationLoadingState());

      emit(
        RegistrationSuccessState(
          message: 'Successfully registered',
        ),
      );
    } catch (err) {
      log.severe('SubmitProviderRegistrationEvent: $err', err);
      emit(RegistrationLoadingState());
      emit(
        RegistrationErrorState(
          message: 'Cannot proceed to registration: $err',
        ),
      );
    }
  }
}
