part of 'reports_bloc.dart';

@immutable
sealed class ReportsEvent {}

final class GetReportSummaryEvent extends ReportsEvent {}

final class GenerateSOAEvent extends ReportsEvent {

  GenerateSOAEvent({ required this.loanId});
  final String loanId;
}
