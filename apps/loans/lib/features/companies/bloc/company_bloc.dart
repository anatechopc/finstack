import 'dart:typed_data';

import 'package:address_repository/address_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/address_builder.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:storage_repository/storage_repository.dart';

part 'company_event.dart';

part 'company_state.dart';

class CompanyBloc extends Bloc<CompanyEvent, CompanyState> {
  CompanyBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        companyRepository = context.read<CompanyRepository>(),
        storageRepository = context.read<StorageRepository>(),
        addressRepository = context.read<AddressRepository>(),
        super(const CompanyState()) {
    on(_handleUpdateCompanyEvent);
    on(_handleUpdateDefaultPenaltiesEvent);
  }

  static const defaultPenaltiesSavedMessage = 'Default penalties updated';
  static const defaultPenaltiesFailedMessage =
      'Cannot update default penalties';

  final AuthenticationService authService;
  final CompanyRepository companyRepository;
  final StorageRepository storageRepository;
  final AddressRepository addressRepository;

  final log = Logger('company_bloc');

  void updateCompany(Company company, Map<String, dynamic> fields) {
    add(UpdateCompanyEvent(company: company, fields: fields));
  }

  void updateDefaultPenalties(List<Penalty> penalties) {
    add(UpdateDefaultPenaltiesEvent(penalties: penalties));
  }

  Future<void> _handleUpdateCompanyEvent(
    UpdateCompanyEvent event,
    Emitter<CompanyState> emit,
  ) async {
    try {
      emit(const CompanyState.loading(isLoading: true));
      final data = event.fields;
      final company = event.company;

      final tempCompany = company
        ..name = data['company_name'] as String
        ..tin = data['tin'] as String
        ..type = data['type'] as CompanyType
        ..tagLine = data['tag_line'] as String
        ..secNumber = data['sec_number'] as String?;

      await companyRepository.update(data: tempCompany).then((company) async {
        if (authService.hasCompany &&
            (authService.company.id == company.id)) {
          authService.company = company;
        }
        final tempCompanyLogoData =
            data['company_logo'] as Map<String, dynamic>?;
        ImageUrl? companyLogo;

        if (tempCompanyLogoData != null) {
          companyLogo = await storageRepository.upload(
            data: tempCompanyLogoData['bytes'] as Uint8List,
            folder: 'companies/${company.id}',
            fileName:
                'company_logo_${DateTime.timestamp().toIso8601String()}_${tempCompanyLogoData['name'] as String}',
            includeOriginal: true,
          );
        }

        final tempAddress = authService.address
          ..dataId = company.id
          ..dataType = DataType.provider;
        AddressBuilder.updateFromFields(tempAddress, data);

        return (await Future.wait([
          if (tempCompanyLogoData != null)
            companyRepository
                .update(
              data: company..companyProfilePhotoUrl = companyLogo,
            )
                .then((company) {
              if (authService.hasCompany &&
                  (authService.company.id == company.id)) {
                authService.company = company;
              }
            }),
          addressRepository.update(data: tempAddress),
        ]))[0];
      });

      emit(const CompanyState.loading());
      emit(
        const CompanyState.success(
          message: 'Successfully updated company',
        ),
      );
    } catch (err) {
      log.severe('UpdateCompanyError: $err', err);
      emit(
        CompanyState.error(
          errorMessage: 'Cannot update companyu: $err',
        ),
      );
    }
  }

  Future<void> _handleUpdateDefaultPenaltiesEvent(
    UpdateDefaultPenaltiesEvent event,
    Emitter<CompanyState> emit,
  ) async {
    final company = authService.company;
    final previous = company.defaultPenalties;
    try {
      emit(const CompanyState.loading(isLoading: true));
      company.defaultPenalties = List<Penalty>.of(event.penalties);
      final updated = await companyRepository.update(data: company);
      authService.company = updated;
      emit(const CompanyState.loading());
      emit(
        const CompanyState.success(message: defaultPenaltiesSavedMessage),
      );
    } catch (err) {
      company.defaultPenalties = previous;
      log.severe('UpdateDefaultPenaltiesError: $err', err);
      emit(const CompanyState.loading());
      emit(
        const CompanyState.error(
          errorMessage: defaultPenaltiesFailedMessage,
        ),
      );
    }
  }
}
