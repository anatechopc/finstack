import 'package:equatable/equatable.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';

class BorrowerLoanGroup extends Equatable {
  const BorrowerLoanGroup({
    required this.loan,
    required this.productName,
    required this.loanType,
    this.actionableSchedules = const [],
    this.childLoans = const [],
  });

  final Loan loan;
  final String productName;
  final String loanType;
  final List<LoanSchedule> actionableSchedules;
  final List<BorrowerLoanGroup> childLoans;

  @override
  List<Object?> get props => [
        loan,
        productName,
        loanType,
        actionableSchedules,
        childLoans,
      ];
}
