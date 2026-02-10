import 'package:loan_repository/loan_repository.dart';

final class LoanSimple {

  const LoanSimple({
    required this.loanId,
    required this.productId,
    required this.loanType,
    required this.status,
  });
  final String loanId;
  final String productId;
  final String loanType;
  final LoanStatus status;
}
