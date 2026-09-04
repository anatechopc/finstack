part of 'company_bloc.dart';

@immutable
sealed class CompanyEvent {}

class UpdateCompanyEvent extends CompanyEvent {
  UpdateCompanyEvent({
    required this.company,
    required this.fields,
  });

  final Map<String, dynamic> fields;
  final Company company;
}

class UpdateDefaultPenaltiesEvent extends CompanyEvent {
  UpdateDefaultPenaltiesEvent({required this.penalties});

  final List<Penalty> penalties;
}
