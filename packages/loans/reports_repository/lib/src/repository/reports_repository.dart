import 'package:reports_repository/src/data/database/reports_realtime_database_service.dart';
import 'package:reports_repository/src/model/capital_usage.dart';
import 'package:reports_repository/src/model/product_totals.dart';
import 'package:reports_repository/src/model/report_summary.dart';
import 'package:reports_repository/src/model/sales.dart';
import 'package:reports_repository/src/model/total_summary_item.dart';

/// {@template reports_repository}
/// reports repository
/// {@endtemplate}
final class ReportsRepository {
  /// constructor
  ReportsRepository() : _databaseService = ReportsRealtimeDatabaseService();

  late final ReportsRealtimeDatabaseService _databaseService;

  /// this is needed to be called initially
  void init({required String companyId}) {
    _databaseService.basePath = 'companies/$companyId';
  }

  Stream<ReportSummary?> get stream => _databaseService.stream;

  Future<Map<String, ProductTotals>?> getProducts() {
    return _databaseService.getProducts();
  }

  Future<Map<String, TotalSummaryItem?>> getTotalSummary({
    List<String> keys = const [],
    int chunkSize = 10,
  }) {
    return _databaseService.getTotalSummary(
      keys: keys,
      chunkSize: chunkSize,
    );
  }

  Future<CapitalUsage?> getCapitalUsage() {
    return _databaseService.getCapitalUsage();
  }

  Future<Sales?> getSales() {
    return _databaseService.getSales();
  }
}
