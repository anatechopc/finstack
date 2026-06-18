part of 'bank_details_bloc.dart';

sealed class BankDetailsEvent {}

final class LoadBankDetailsEvent extends BankDetailsEvent {}

final class AddBankDetailsEvent extends BankDetailsEvent {
  AddBankDetailsEvent({
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });
  final String bankName;
  final String accountName;
  final String accountNumber;
}

final class UpdateBankDetailsEvent extends BankDetailsEvent {
  UpdateBankDetailsEvent({required this.bankDetails});
  final BankDetails bankDetails;
}

final class DeleteBankDetailsEvent extends BankDetailsEvent {
  DeleteBankDetailsEvent({required this.bankDetails});
  final BankDetails bankDetails;
}
