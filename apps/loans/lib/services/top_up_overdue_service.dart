import 'package:flutter/material.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/services/charge_calculator.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:product_repository/product_repository.dart';

/// The owner's soft block for a top-up on an open-term loan with overdue
/// bills (2026-11-19). Adding the top-up warns the lender with the overdue
/// amount and records their choice on it; nothing else is written then.
/// Approval applies a "deduct" choice once: the overdue bills on the
/// approval day are recorded paid from the top-up's proceeds and the rest
/// of the proceeds is released.
///
/// No cash-pool entry is written: the cash pool is the borrower's prepaid
/// balance, a top-up's proceeds never enter it, and the released cash is
/// handed over outside the app, as with every top-up.
class TopUpOverdueService {
  TopUpOverdueService({
    required this.loanScheduleRepository,
    required this.paymentRepository,
  });

  final LoanScheduleRepository loanScheduleRepository;
  final PaymentRepository paymentRepository;

  /// The cash [topUp] hands over: its amount less its deductions and
  /// advance charges. (The balance still adds amount + charges, #127.)
  static double proceeds(AdditionalLoanAmount topUp) =>
      _centavos(topUp.amount - topUp.deductions - topUp.advanceCharges);

  /// [proceeds] of a top-up of [amount] not stored yet, with the product's
  /// [charges] and [deductions] applied as the top-up will store them.
  static double proceedsOf({
    required double amount,
    required List<Charge> charges,
    required List<Charge> deductions,
  }) {
    final result = ChargeCalculator.applyChargesAndDeductionsDetailed(
      baseAmount: amount,
      charges: charges,
      deductions: deductions,
    );

    return _centavos(
      amount - result.totalDeductions - result.totalUpfrontCollection,
    );
  }

  /// When a bill of open-term [loan] is past due on [asOf]'s day (default
  /// now): the bills and the amount the borrower's "Pay now" shows (every
  /// bill due by that day plus the overdue stretch's penalty once; bills
  /// already submitted are not in it). Null when no bill is past due, and
  /// for a fixed-term loan. [schedules] are the loan's rows and bills as
  /// client detail lists them.
  static ({List<LoanSchedule> bills, double amount})? overdue({
    required Loan loan,
    required List<LoanSchedule> schedules,
    DateTime? asOf,
  }) {
    if (loan.period != 0) {
      return null;
    }
    final due = borrowerAmountsDue(
      schedules: schedules,
      loan: loan,
      asOf: asOf,
    );
    final today = DateUtils.dateOnly(asOf ?? DateTime.now());
    // payNow is the next bill when nothing is due yet: only a bill whose
    // due day has passed makes the loan overdue.
    final anyLate = due.payNow.any(
      (s) => DateUtils.dateOnly(s.lateFrom.toLocal()).isBefore(today),
    );
    if (!anyLate) {
      return null;
    }

    return (bills: due.payNow, amount: _centavos(due.nextDueAmount));
  }

  /// [loan]'s stored rows and open-term bills on [now], as client detail
  /// lists them (LoansBloc.selectLoan): a submitted bill settled at its
  /// transfer, the balance with [product]'s charges (none without it), the
  /// engine given the loan with its top-ups.
  Future<List<LoanSchedule>> schedulesOf(
    Loan loan, {
    Product? product,
    DateTime? now,
  }) async {
    final stored = await loanScheduleRepository.allByLoanId(
      loanId: loan.id,
      onlyPaid: false,
    );
    await PaymentConfirmationService.settleSubmittedAtTheirTransfer(
      stored,
      paymentRepository,
    );
    final (:totalAmount, totalUpfrontCollection: _) =
        ChargeCalculator.applyChargesAndDeductions(
      baseAmount: loan.amount,
      charges: product?.additionalCharges ?? const [],
      deductions: product?.deductions ?? const [],
    );

    return LoanCalculationService.calculateOpenTerm(
      amount: totalAmount,
      date: loan.createdAt,
      interestRate: loan.interestRate,
      term: loan.term,
      companyId: loan.companyId,
      paidSchedules: stored,
      loan: loan,
      now: now,
    ).schedules;
  }

  /// Marks [bills] (oldest first) paid in memory, collected at
  /// [collectedAt], the way the Payment Center pays overdue bills together:
  /// each pays its amount due as interest, no principal, and the overdue
  /// stretch's penalty is charged once, on the first late bill (R3).
  /// [schedules] are the rows [bills] came from. Returns the bills plus
  /// their penalties, to the centavo; nothing is written.
  static double settle({
    required Loan loan,
    required List<LoanSchedule> bills,
    required List<LoanSchedule> schedules,
    required DateTime collectedAt,
    required String actorId,
  }) {
    var total = 0.0;
    for (final bill in bills) {
      bill
        ..paidAt = DateTime.timestamp()
        ..loanId = loan.id;
      final status = PaymentConfirmationService.applyLateness(
        schedule: bill,
        loan: loan,
        collectedAt: collectedAt,
        actorId: actorId,
        loanRows: schedules,
      );
      bill
        ..interestPayment = bill.amortization
        ..principalPayment = 0
        ..status = status;
      total += bill.interestPayment + bill.penalty;
    }

    return _centavos(total);
  }

  /// Writes [bills] settled by [settle], each with its own confirmed
  /// payment carrying [comment] (one payment per bill, as the Payment
  /// Center's overdue payment writes them). Returns the payment ids.
  Future<List<String>> persist({
    required Loan loan,
    required List<LoanSchedule> bills,
    required String actorId,
    required String comment,
  }) async {
    final paymentIds = <String>[];
    for (final bill in bills) {
      final saved = await PaymentConfirmationService.persistPaidSchedule(
        bill,
        Payment.create(
          userId: loan.userId,
          loanScheduleId: bill.id,
          loanId: loan.id,
          // Paid from the top-up's proceeds: the top-up's selfie and
          // signature are the record, no transfer to prove.
          bypassPaymentProof: true,
          comment: comment,
          confirmedBy: actorId,
          confirmedAt: DateTime.timestamp(),
        ),
        loanScheduleRepository: loanScheduleRepository,
        paymentRepository: paymentRepository,
      );
      paymentIds.add(saved.id);
    }

    return paymentIds;
  }

  static double _centavos(double value) => (value * 100).round() / 100;
}

/// A top-up action refused before anything was written; [message] is for
/// the lender.
class TopUpRefused implements Exception {
  const TopUpRefused(this.message);

  final String message;

  @override
  String toString() => message;
}
