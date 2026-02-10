import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:loooans/features/cash_pool/model/cash_pool_display.dart';

Future<CashPoolDisplay> processCashPoolDisplay(List<CashPool> cashPoolList) async {
  return Future.microtask(() {
    final totalAcknowledged = cashPoolList
        .where((cashPool) =>
    cashPool.status == CashPoolStatus.acknowledged_payment,)
        .map((cashPool) => cashPool.amount)
        .fold<double>(0, (previousValue, element) => previousValue + element);
    final totalCashPool = cashPoolList
        .where((cashPool) => cashPool.status == CashPoolStatus.add_to_pool)
        .map((cashPool) => cashPool.amount)
        .fold<double>(0, (previousValue, element) => previousValue + element);
    final totalChange = cashPoolList
        .where((cashPool) => cashPool.status == CashPoolStatus.change)
        .map((cashPool) => cashPool.amount)
        .fold<double>(0, (previousValue, element) => previousValue + element);
    final totalSavings = cashPoolList
        .where((cashPool) => cashPool.status == CashPoolStatus.savings)
        .map((cashPool) => cashPool.amount)
        .fold<double>(0, (previousValue, element) => previousValue + element);
    final balance = totalCashPool - totalAcknowledged - totalChange - totalSavings;
    return CashPoolDisplay(
      totalAcknowledged: totalAcknowledged,
      totalCashPool: totalCashPool,
      balance: balance,
      change: totalChange,
      savings: totalSavings,
    );
  });
}
