part of 'payment_bloc.dart';

sealed class PaymentEvent extends Equatable {
  const PaymentEvent();
}

final class PayLoanScheduleEvent extends PaymentEvent {
  const PayLoanScheduleEvent({
    required this.loan,
    required this.schedule,
    required this.payment,
    this.fileName,
    this.fileBytes,
    this.signatureBytes,
    this.interestPayment = 0,
    this.force = false,
  });

  final Loan loan;
  final LoanSchedule schedule;
  final double payment;
  final double interestPayment;
  final String? fileName;
  final Uint8List? fileBytes;
  final Uint8List? signatureBytes;
  final bool force;

  @override
  List<Object?> get props => [
        loan,
        schedule,
        payment,
        interestPayment,
        fileName,
        fileBytes,
        signatureBytes,
        force,
      ];
}
