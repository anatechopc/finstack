import 'package:equatable/equatable.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';

class BorrowerLoanGroup extends Equatable {
  const BorrowerLoanGroup({
    required this.loan,
    required this.productName,
    required this.loanType,
    this.actionableSchedules = const [],
    this.storedSchedules = const [],
    this.childLoans = const [],
  });

  final Loan loan;
  final String productName;
  final String loanType;
  final List<LoanSchedule> actionableSchedules;

  /// Every stored row of the loan. An open-term penalty is one per overdue
  /// stretch (owner rule R3); the payment dialog reads what earlier
  /// payments in the stretch already charged from these.
  final List<LoanSchedule> storedSchedules;
  final List<BorrowerLoanGroup> childLoans;

  @override
  List<Object?> get props => [
        loan,
        productName,
        loanType,
        actionableSchedules,
        storedSchedules,
        childLoans,
      ];
}
