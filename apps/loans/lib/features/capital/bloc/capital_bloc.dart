import 'package:capital_repository/capital_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/logging_helpers.dart';

part 'capital_event.dart';

part 'capital_state.dart';

class CapitalBloc extends Bloc<CapitalEvent, CapitalState> {
  CapitalBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        capitalRepository = context.read<CapitalRepository>(),
        super(CapitalState()) {
    on(_handleAddCapitalEvent);
  }

  final AuthenticationService authService;
  final CapitalRepository capitalRepository;

  final log = Logger('capital_bloc.dart');

  void addCapital({required double amount}) {
    add(AddCapitalEvent(amount: amount));
  }

  Future<void> _handleAddCapitalEvent(
    AddCapitalEvent event,
    Emitter<CapitalState> emit,
  ) async {
    try {
      if (!authService.hasCompany) {
        return;
      }

      emit(const CapitalState.loading(isLoading: true));

      await capitalRepository.add(
        data: Capital.create(
          providerId: authService.company.id,
          amount: event.amount,
        ),
      );

      emit(const CapitalState.loading());
      emit(const CapitalState.success());
    } catch (err) {
      log.severe('Cannot add capital: $err', err);
      emit(const CapitalState.loading());
      emit(
          CapitalState.error(message: 'Cannot add capital: $err'),);
    }
  }
}
