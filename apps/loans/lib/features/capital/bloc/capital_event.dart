part of 'capital_bloc.dart';

@immutable
sealed class CapitalEvent {}

class AddCapitalEvent extends CapitalEvent {

  AddCapitalEvent({required this.amount});
  final double amount;
}
