import 'package:loan_repository/loan_repository.dart';

final class PrincipalBorrower {

  const PrincipalBorrower({
    required this.date,
    required this.userName,
    required this.loanAmount,
    required this.status,
    required this.loanType,
    required this.userId,
    required this.loanId,
    required this.productId,
  });
  final DateTime date;
  final String userName;
  final double loanAmount;
  final LoanStatus status;
  final String loanType;
  final String userId;
  final String productId;
  final String loanId;
}
