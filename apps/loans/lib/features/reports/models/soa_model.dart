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

  // NOTE: less interests and deductions are separated
  // for clarity.
  final List<ChargeSimple> deductions;

  // NOTE: these are unpaid loan balance.
  // Used for Open Term loans
  final double outstandingPrincipalBalance;

  // NOTE: in calculating totalAmount, deductions are
  // calculated first, the total deductions will be then
  // deducted from the outstandingPrincipalBalance.
  final double totalAmount;

  // NOTE: Additional charges are anything that's charged, added
  // on top of the loan.
  // But in this model, additionalCharges are remaining loan
  // outstanding principal balances.
  final List<ChargeSimple> additionalCharges;

  // totalAmountDue is the sum of the totalAmount + the additional charges.
  final double totalAmountDue;

  // the total size of the data, including the fields that are not
  // in the entries list.
  final int size;
}
