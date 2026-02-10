part of 'additional_loan_bloc.dart';

sealed class AdditionalLoanEvent extends Equatable {
  const AdditionalLoanEvent();
}

final class AddLoanAmountEvent extends AdditionalLoanEvent {
  const AddLoanAmountEvent({
    required this.loanId,
    required this.amount,
    required this.additionalCharges,
    required this.deductions,
    required this.selfiePhoto,
    required this.signatureBytes,
    this.description,
  });

  final String loanId;
  final double amount;
  final String? description;
  final List<Charge> additionalCharges;
  final List<Charge> deductions;
  final SimpleFileData selfiePhoto;
  final Uint8List signatureBytes;

  @override
  List<Object?> get props => [
        loanId,
        amount,
        description,
        additionalCharges,
        deductions,
        selfiePhoto,
        signatureBytes,
      ];
}

final class UpdateAdditionalLoanAmountEvent extends AdditionalLoanEvent {
  const UpdateAdditionalLoanAmountEvent({
    required this.loanId,
    required this.additionalLoanAmountId,
    required this.status,
  });

  final String loanId;
  final String additionalLoanAmountId;
  final LoanStatus status;

  @override
  List<Object?> get props => [
        loanId,
        additionalLoanAmountId,
        status,
      ];
}
