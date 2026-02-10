part of 'reports_bloc.dart';

enum ReportStateStatus {
  initial,
  loading,
  success,
  error,
  capitalUsageRefresh,
  momSalesRefresh,
  salesByProductRefresh,
  reportCardsRefresh,
  soaGeneratedRefresh,
  loanStatusCountRefresh,
  allSalesRefresh,
}

final class ReportsState extends Equatable {
  const ReportsState() : this._();

  const ReportsState._({
    this.status = ReportStateStatus.initial,
    this.isLoading = false,
    this.message,
  });

  const ReportsState.loading({bool isLoading = false}): this._(
    isLoading: isLoading,
    status: ReportStateStatus.loading,
  );

  const ReportsState.success(String? message): this._(
    message: message,
    status: ReportStateStatus.success,
  );

  const ReportsState.error(String message): this._(
    message: message,
    status: ReportStateStatus.error,
  );

  const ReportsState.capitalUsageRefresh(): this._(
    status: ReportStateStatus.capitalUsageRefresh,
  );

  const ReportsState.momSalesRefresh(): this._(
    status: ReportStateStatus.momSalesRefresh,
  );

  const ReportsState.salesByProductRefresh(): this._(
    status: ReportStateStatus.salesByProductRefresh,
  );

  const ReportsState.soaGeneratedRefresh(): this._(
    status: ReportStateStatus.soaGeneratedRefresh,
  );

  const ReportsState.loanStatusCountRefresh(): this._(
    status: ReportStateStatus.loanStatusCountRefresh,
  );

  const ReportsState.allSalesRefresh(): this._(
    status: ReportStateStatus.allSalesRefresh,
  );

  final ReportStateStatus status;
  final String? message;
  final bool isLoading;

  @override
  List<Object?> get props => [
        status,
        message,
        isLoading,
      ];
}
