import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'bank_details_event.dart';
part 'bank_details_state.dart';

class BankDetailsBloc extends Bloc<BankDetailsEvent, BankDetailsState> {
  BankDetailsBloc(BuildContext context)
      : this.withDependencies(
          bankDetailsRepository: context.read<BaseRepository<BankDetails>>(),
          authService: AuthenticationService.instance,
        );

  BankDetailsBloc.withDependencies({
    required this.bankDetailsRepository,
    required this.authService,
  }) : super(const BankDetailsState()) {
    on<LoadBankDetailsEvent>(_onLoad);
    on<AddBankDetailsEvent>(_onAdd);
    on<UpdateBankDetailsEvent>(_onUpdate);
    on<DeleteBankDetailsEvent>(_onDelete);
  }

  final BaseRepository<BankDetails> bankDetailsRepository;
  final AuthenticationService authService;

  Future<List<BankDetails>> _load() async {
    final all = await bankDetailsRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'dataId', isEqualTo: authService.company.id),
      ],
    );
    return all.where((b) => b.dataType == DataType.provider).toList();
  }

  Future<void> _onLoad(
    LoadBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.loading));
    try {
      emit(
        state.copyWith(
          status: BankDetailsStatus.loaded,
          accounts: await _load(),
        ),
      );
    } catch (err) {
      debugPrint('Failed to load payout accounts: $err');
      emit(
        state.copyWith(
          status: BankDetailsStatus.error,
          message: 'Failed to load payout accounts',
        ),
      );
    }
  }

  Future<void> _onAdd(
    AddBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.add(
        data: BankDetails.create(
          dataId: authService.company.id,
          dataType: DataType.provider,
          bankName: event.bankName,
          accountName: event.accountName,
          accountNumber: event.accountNumber,
        ),
      );
      emit(
        state.copyWith(
          status: BankDetailsStatus.loaded,
          accounts: await _load(),
        ),
      );
    } catch (err) {
      debugPrint('Failed to add account: $err');
      emit(
        state.copyWith(
          status: BankDetailsStatus.error,
          message: 'Failed to add account',
        ),
      );
    }
  }

  Future<void> _onUpdate(
    UpdateBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.update(data: event.bankDetails);
      emit(
        state.copyWith(
          status: BankDetailsStatus.loaded,
          accounts: await _load(),
        ),
      );
    } catch (err) {
      debugPrint('Failed to update account: $err');
      emit(
        state.copyWith(
          status: BankDetailsStatus.error,
          message: 'Failed to update account',
        ),
      );
    }
  }

  Future<void> _onDelete(
    DeleteBankDetailsEvent event,
    Emitter<BankDetailsState> emit,
  ) async {
    emit(state.copyWith(status: BankDetailsStatus.saving));
    try {
      await bankDetailsRepository.delete(data: event.bankDetails);
      emit(
        state.copyWith(
          status: BankDetailsStatus.loaded,
          accounts: await _load(),
        ),
      );
    } catch (err) {
      debugPrint('Failed to delete account: $err');
      emit(
        state.copyWith(
          status: BankDetailsStatus.error,
          message: 'Failed to delete account',
        ),
      );
    }
  }
}
