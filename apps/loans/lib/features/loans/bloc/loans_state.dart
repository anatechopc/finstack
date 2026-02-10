part of 'loans_bloc.dart';

enum LoansStatus {
  initial,
  loading,
  success,
  error,
  selected,
  unselected,
  refresh,
  allUserLoansRetrieved,
  principalBorrowersRetrieved,
}

final class LoansState extends Equatable {
  const LoansState() : this._();

  const LoansState._({
    this.loan,
    this.schedules = const [],
    this.status = LoansStatus.initial,
    this.isLoading = false,
    this.message,
    this.closeDialog = false,
    this.extraData,
  });

  const LoansState.selected({
    required Loan? loan,
    required List<LoanSchedule> schedules,
  }) : this._(
          loan: loan,
          schedules: schedules,
          status: LoansStatus.selected,
        );

  const LoansState.unselected()
      : this._(
          status: LoansStatus.unselected,
        );

  const LoansState.loading({
    bool isLoading = false,
  }) : this._(
          isLoading: isLoading,
          status: LoansStatus.loading,
        );

  const LoansState.success(String? message, {bool closeDialog = false})
      : this._(
          message: message,
          status: LoansStatus.success,
          closeDialog: closeDialog,
        );

  const LoansState.error(String message)
      : this._(
          message: message,
          status: LoansStatus.error,
        );

  LoansState.refresh()
      : this._(
          extraData: DateTime.now().millisecondsSinceEpoch,
          status: LoansStatus.refresh,
        );

  const LoansState.allUserLoansRetrieved()
      : this._(
          status: LoansStatus.allUserLoansRetrieved,
        );

  const LoansState.principalBorrowersRetrieved()
      : this._(
          status: LoansStatus.principalBorrowersRetrieved,
        );

  final Loan? loan;
  final List<LoanSchedule> schedules;
  final LoansStatus status;
  final bool isLoading;
  final String? message;
  final bool closeDialog;
  final dynamic extraData;

  @override
  List<Object?> get props => [
        loan,
        schedules,
        status,
        isLoading,
        message,
        closeDialog,
        extraData,
      ];
}
