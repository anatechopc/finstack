part of 'company_bloc.dart';

enum CompanyStateStatus {
  initial,
  loading,
  error,
  success;
}

final class CompanyState {
  const CompanyState() : this._();

  const CompanyState._({
    this.status = CompanyStateStatus.initial,
    this.isLoading = false,
    this.message,
  });

  const CompanyState.loading({ bool isLoading = false}): this._(
    isLoading: isLoading,
    status: CompanyStateStatus.loading,
  );

  const CompanyState.success({ String? message}): this._(
    message: message,
    status: CompanyStateStatus.success,
  );

  const CompanyState.error({ required String errorMessage}): this._(
    message: errorMessage,
    status: CompanyStateStatus.error,
  );

  final CompanyStateStatus status;
  final bool isLoading;
  final String? message;
}
