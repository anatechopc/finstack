part of 'bank_details_bloc.dart';

enum BankDetailsStatus { initial, loading, loaded, saving, error }

final class BankDetailsState extends Equatable {
  const BankDetailsState({
    this.status = BankDetailsStatus.initial,
    this.accounts = const [],
    this.message,
  });

  final BankDetailsStatus status;
  final List<BankDetails> accounts;
  final String? message;

  BankDetailsState copyWith({
    BankDetailsStatus? status,
    List<BankDetails>? accounts,
    String? message,
  }) =>
      BankDetailsState(
        status: status ?? this.status,
        accounts: accounts ?? this.accounts,
        message: message,
      );

  @override
  List<Object?> get props => [status, accounts, message];
}
