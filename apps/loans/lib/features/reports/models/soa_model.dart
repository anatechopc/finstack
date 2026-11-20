import 'package:loooans/features/reports/models/charge_simple.dart';
import 'package:loooans/features/reports/models/soa_entry.dart';

/// [SOAModel] is the summary of the account of the borrower.
/// this model is generated when the borrower asks for their
/// statement of account.
final class SOAModel {

  const SOAModel({
    required this.userId,
    required this.date,
    required this.fullName,
    required this.interest,
    required this.term,
    required this.entries,
    required this.totalInterestCharge,
    required this.lessAdvanceInterest,
    required this.lessTotalInterestCollected,
    required this.rebates,
    required this.deductions,
    required this.outstandingPrincipalBalance,
    required this.totalAmount,
    required this.additionalCharges,
    required this.totalAmountDue,
    required this.size,
  });
  final String userId;
  final DateTime date;
  final String fullName;
  final double interest;
  final String term;
  final List<SOAEntry> entries;
  final double totalInterestCharge;
  final double lessAdvanceInterest;
  final double lessTotalInterestCollected;

  /// Interest charged less advance interest less interest collected, over
  /// the rows above: history only, not part of the amount due.
  final double rebates;

  // NOTE: less interests and deductions are separated
  // for clarity.
  final List<ChargeSimple> deductions;

  /// The early-settlement principal: the balance after the last confirmed
  /// payment, top-ups included (#116).
  final double outstandingPrincipalBalance;

  // NOTE: in calculating totalAmount, deductions are
  // calculated first, the total deductions will be then
  // deducted from the outstandingPrincipalBalance.
  final double totalAmount;

  /// Added to [totalAmount]: interest to date, unpaid penalties and each
  /// special loan's own settlement amount.
  final List<ChargeSimple> additionalCharges;

  /// What settling the loan and its special loans costs today, the figure
  /// the settlement records (`LoanCalculationService.settlementOf`).
  final double totalAmountDue;

  // the total size of the data, including the fields that are not
  // in the entries list.
  final int size;
}
