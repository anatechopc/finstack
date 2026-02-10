final class SOAEntry {

  SOAEntry({
    required this.date,
    required this.principalLoan,
    required this.interestCharge,
    required this.advanceInterest,
    required this.interestPayment,
    required this.principalPayment,
    required this.principalBalance,
    required this.numberOfDays,
    this.isTotal = false,
    this.toRemove = false,
    this.isAdditionalAmount = false,
  });
  final DateTime date;
  final double principalLoan;
  final double interestCharge;
  final double advanceInterest;
  final double interestPayment;
  final double principalPayment;
  double principalBalance;
  final bool isTotal;
  bool toRemove;
  final bool isAdditionalAmount;
  final String numberOfDays;
}
