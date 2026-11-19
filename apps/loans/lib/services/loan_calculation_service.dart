import 'dart:math';

import 'package:collection/collection.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/logging_helpers.dart';

class LoanCalculationResult {
  LoanCalculationResult({
    required this.schedules,
    required this.monthlyAmortization,
    required this.totalLoanPayment,
    this.totalLoanAmountReceivable = 0,
  });

  final List<LoanSchedule> schedules;
  final double monthlyAmortization;
  final double totalLoanPayment;
  double totalLoanAmountReceivable;
}

class LoanCalculationService {
  LoanCalculationService._();

  static final _log = Logger('loan_calculation_service');

  static double calculateLoanAmount(Loan loan) {
    return loan.amount + loan.additionalCharges - loan.deductions;
  }

  static double calculateMonthlyPaymentSimple({
    required double outstandingBalance,
    required double monthlyInterestRate,
  }) {
    return outstandingBalance * monthlyInterestRate;
  }

  /// Early-settlement balance for a loan family (parent + special loans) as
  /// the settlement dialog computes it today: the net amount released per
  /// loan minus what [schedules] (every row with a payment id) collected.
  ///
  /// BUG(finstack#116): extracted verbatim from `LoanSettlementBloc` and
  /// pinned as-is by golden test G7. The formula needs a design decision,
  /// not a patch: the loop ASSIGNS instead of accumulating (only the last
  /// element counts, and the bloc's list is newest-first by updated_at, so
  /// production credits the least recently updated row); [schedules] includes
  /// borrower submissions not yet confirmed; open-term rows credit the
  /// computed interestCharge rather than the recorded interestPayment; and
  /// approved top-ups (loan.additionalLoanAmounts) are not part of the
  /// released amount. Flip G7 in the change that fixes this, never silently.
  static double calculateSettlementBalance({
    required List<Loan> loans,
    required List<LoanSchedule> schedules,
  }) {
    var totalLoanAmount = 0.0;
    var totalLoanPayment = 0.0;

    for (final loan in loans) {
      totalLoanAmount += (loan.amount + loan.additionalCharges) -
          (loan.deductions + loan.additionalChargeUpfrontCollection);
    }

    for (final schedule in schedules) {
      totalLoanPayment = (schedule.isOpenTerm
              ? schedule.interestCharge
              : schedule.interestPayment) +
          schedule.principalPayment +
          schedule.extraPayment;
    }

    return totalLoanAmount - totalLoanPayment;
  }

  /// Calculates loan schedules for fixed-term loans.
  ///
  /// P = (Pv*R) / [1 - (1 + R)^(-n)]
  static LoanCalculationResult calculateFixedTerm({
    required double amount,
    required int monthsToPay,
    required DateTime date,
    required double interestRate,
    required String term,
    required String companyId,
    List<LoanSchedule> paidSchedules = const [],
  }) {
    final schedules = <LoanSchedule>[];
    var totalLoanPayment = 0.0;
    paidSchedules.sortBy((sched) => sched.dueAt);
    var monthlyInterestRate = interestRate / 100;
    var outstandingBalance = amount;
    var numOfPayments = monthsToPay;
    var nextMonthDate = Jiffy.parseFromDateTime(date).startOf(Unit.day);

    var loanMonthlyAmortization = 0.0;

    if (paidSchedules.isEmpty) {
      loanMonthlyAmortization = amount.calculateMonthlyPayment(
        monthlyInterestRate: monthlyInterestRate,
        monthsToPay: monthsToPay,
        term: term,
      );
    } else {
      loanMonthlyAmortization = paidSchedules.first.amortization;
      outstandingBalance = paidSchedules.last.outstandingBalance;
      nextMonthDate = Jiffy.parseFromMillisecondsSinceEpoch(
        paidSchedules.last.dueAt.millisecondsSinceEpoch,
      ).startOf(Unit.day);
    }

    if (term == '15d') {
      numOfPayments *= 2;
      monthlyInterestRate /= 2;
    }

    if (paidSchedules.isNotEmpty) {
      numOfPayments -= paidSchedules.length;
    }

    _log.finest('loan amortization: $loanMonthlyAmortization');

    if (term == '1m') {
      nextMonthDate = nextMonthDate.add(months: 1);
    } else {
      nextMonthDate = nextMonthDate.add(days: 15);
    }

    final monthlyAmortization = loanMonthlyAmortization;

    _log.finest('---------------------------------------------------');
    for (var i = 1; i <= numOfPayments; i++) {
      final beginningBalance = outstandingBalance;
      final interestPayment = outstandingBalance * monthlyInterestRate;
      final monthlyAmort =
          min(loanMonthlyAmortization, beginningBalance + interestPayment);
      final principalPayment = monthlyAmort - interestPayment;
      outstandingBalance -= principalPayment;
      _log
        ..finest('month: $i')
        ..finest('date: ${nextMonthDate.format()}')
        ..finest('monthly: $monthlyAmort')
        ..finest('interestPayment: $interestPayment')
        ..finest('principalPayment: $principalPayment')
        ..finest('outstandingBalance: $outstandingBalance')
        ..finest('beginningBalance: $beginningBalance')
        ..finest('---------------------------------------------------');
      final schedule = LoanSchedule.create(
        dueAt: nextMonthDate.dateTime,
        outstandingBalance: outstandingBalance,
        amortization:
            min(loanMonthlyAmortization, beginningBalance + interestPayment),
        principalPayment: principalPayment,
        interestCharge: interestPayment,
        loanId: 'loanId:$i',
        interestDayMultiplier: 1,
        companyId: companyId,
      );

      totalLoanPayment += schedule.amortization;
      _log.finest('totalLoanPayment: $totalLoanPayment');

      schedules.add(schedule);

      if (term == '1m') {
        nextMonthDate = nextMonthDate.add(months: 1);
      } else {
        nextMonthDate = nextMonthDate.add(days: 15);
      }
    }

    return LoanCalculationResult(
      schedules: schedules,
      monthlyAmortization: monthlyAmortization,
      totalLoanPayment: totalLoanPayment,
    );
  }

  /// Upper bound on the bills listed in one run, so a malformed term can
  /// never loop forever (about 40 years of salary-day bills).
  static const _maxOpenTermBills = 1000;

  /// Calculates the open-term bills owed after the loan's last stored row.
  ///
  /// Owner rules R1-R5 (2026-11-14 to 2026-11-19; golden set G14):
  /// - R1: a bill keeps its scheduled date. `'1m'` and `'15d'` bills fall
  ///   every 30 or 15 days from [date] (the loan's creation day), the way
  ///   the first bill always did; salary-day terms (`'D1,D2'`) fall on the
  ///   next salary day after the previous bill. Never from today or from a
  ///   payment date (finstack#144).
  /// - R2: every bill due before today is its own row, followed by the first
  ///   bill due today or later. Each row bills its own cycle: no interest
  ///   accrued to today, no one-month cap (finstack#120).
  /// - R4: what the last stored row left unpaid of its amount due (an
  ///   interest shortfall) is added to the first new bill's amount due
  ///   (`amortization`); its `interestCharge` stays the cycle's interest.
  /// - R5: a top-up not yet in the stored balance splits its cycle: the old
  ///   balance up to the top-up day, the new balance from that day on
  ///   (finstack#117).
  ///
  /// Note: 1 month = 30 days (even if in a month there are 31 or 28 days).
  /// Interest runs from the last stored row's `dueAt`, where its interest
  /// ended. A row stored by the old clamp is dated the day it was computed
  /// (its cycle date is in `originalDueAt`), so the first new bill counts
  /// its days from that date to the next scheduled date after it.
  ///
  /// [paidSchedules] are the loan's stored rows, of any status; neither the
  /// list nor its rows are changed (finstack#145). [now] decides which bills
  /// are already due; it defaults to the wall clock, tests pass a fixed date.
  static ({
    List<LoanSchedule> schedules,
    double totalLoanPayment,
    double monthlyAmortization,
  }) calculateOpenTermSchedules({
    required double amount,
    required DateTime date,
    required double interestRate,
    required String term,
    required String companyId,
    List<LoanSchedule> paidSchedules = const [],
    bool forSoa = false,
    DateTime? now,
    List<AdditionalLoanAmount> additionalLoans = const [],
  }) {
    final monthlyInterestRate = interestRate / 100;
    // The creation day as the old engine read it (a stored date is UTC), so
    // the first bill keeps the date it always had.
    final created = Jiffy.parseFromDateTime(date);
    final start = Jiffy.parseFromDateTime(
      DateTime(created.year, created.month, created.date),
    );
    final today = _localDay(now ?? DateTime.now());
    final last = paidSchedules.sortedBy((sched) => sched.dueAt).lastOrNull;

    var balance = last?.outstandingBalance ?? amount;
    var cycleStart = last == null ? start : _localDay(last.dueAt);
    var carry = last == null ? 0.0 : _interestShortfall(last);
    final topUps = additionalLoans
        .where((topUp) => last == null || !_includesTopUp(last, topUp))
        .sortedBy((topUp) => topUp.createdAt);
    var nextTopUp = 0;

    final monthlyAmortization = calculateMonthlyPaymentSimple(
      outstandingBalance: balance,
      monthlyInterestRate: monthlyInterestRate,
    );
    _log.finest('loan amortization: $monthlyAmortization');

    final schedules = <LoanSchedule>[];
    Jiffy dueAt;
    do {
      dueAt = _nextOpenTermDueDate(term: term, start: start, after: cycleStart);

      var interestCharge = 0.0;
      var from = cycleStart;
      while (nextTopUp < topUps.length) {
        final topUp = topUps[nextTopUp];
        final topUpDay = _localDay(topUp.createdAt);
        if (topUpDay.isAfter(dueAt)) {
          break;
        }
        // A top-up before this cycle started (the previous one was paid
        // early) puts the whole cycle on the new balance.
        final splitAt = topUpDay.isBefore(cycleStart) ? cycleStart : topUpDay;
        interestCharge +=
            balance * monthlyInterestRate * _days(from, splitAt) / 30;
        from = splitAt;
        balance += topUp.amount + topUp.additionalCharges;
        nextTopUp++;
      }
      interestCharge += balance * monthlyInterestRate * _days(from, dueAt) / 30;
      final interestDayMultiplier = _days(cycleStart, dueAt) / 30;

      _log
        ..finest('date: ${dueAt.format()}')
        ..finest('interestCharge: $interestCharge')
        ..finest('interestDayMultiplier: $interestDayMultiplier')
        ..finest('carried shortfall: $carry')
        ..finest('outstandingBalance: $balance')
        ..finest('---------------------------------------------------');
      schedules.add(
        LoanSchedule.create(
          dueAt: dueAt.dateTime,
          outstandingBalance: balance,
          amortization: interestCharge + carry,
          principalPayment: 0,
          interestCharge: interestCharge,
          loanId: 'loanId:${schedules.length + 1}',
          isOpenTerm: true,
          interestDayMultiplier: interestDayMultiplier,
          companyId: companyId,
        ),
      );
      carry = 0;
      cycleStart = dueAt;
    } while (dueAt.isBefore(today) && schedules.length < _maxOpenTermBills);

    return (
      schedules: schedules,
      // Sentinel: an open-term loan has no fixed total.
      totalLoanPayment: double.infinity,
      monthlyAmortization: monthlyAmortization,
    );
  }

  /// R1: the first scheduled bill date after [after]. `'D1,D2'` is the next
  /// salary day; `'15d'` steps 15 days from [start], anything else 30.
  static Jiffy _nextOpenTermDueDate({
    required String term,
    required Jiffy start,
    required Jiffy after,
  }) {
    if (term.contains(',')) {
      final splitTerm = term.split(',');
      final tempFirstSalaryDay = int.parse(splitTerm[0]);
      final tempSecondSalaryDay = int.parse(splitTerm[1]);
      final firstSalaryDay = min(tempFirstSalaryDay, tempSecondSalaryDay);
      final secondSalaryDay = max(tempFirstSalaryDay, tempSecondSalaryDay);
      final day = after.date;

      return Jiffy.parseFromDateTime(
        day < firstSalaryDay
            ? DateTime(after.year, after.month, firstSalaryDay)
            : day < secondSalaryDay
                ? DateTime(after.year, after.month, secondSalaryDay)
                : DateTime(after.year, after.month + 1, firstSalaryDay),
      );
    }

    // Calendar days from [start], so a daylight-saving change on the way
    // cannot move the date (adding 30 x 24 hours would, campaign D11).
    final step = term == '15d' ? 15 : 30;
    Jiffy billOn(int cycle) => Jiffy.parseFromDateTime(
          DateTime(start.year, start.month, start.date + step * cycle),
        );
    var cycle = 1;
    while (!billOn(cycle).isAfter(after)) {
      cycle++;
    }

    return billOn(cycle);
  }

  /// Start of [dateTime]'s calendar day on this device. Stored dates come
  /// back in UTC.
  static Jiffy _localDay(DateTime dateTime) =>
      Jiffy.parseFromDateTime(dateTime.toLocal()).startOf(Unit.day);

  static int _days(Jiffy from, Jiffy to) =>
      to.diff(from, unit: Unit.day).toInt();

  /// Whether stored [row]'s balance already holds [topUp]: the row was
  /// computed after the top-up, and the top-up is not after the row's due
  /// day. (Rows from before R1 were never dated before the day they were
  /// computed, so for them only the first condition decides.)
  static bool _includesTopUp(LoanSchedule row, AdditionalLoanAmount topUp) =>
      topUp.createdAt.isBefore(row.createdAt) &&
      !_localDay(topUp.createdAt).isAfter(_localDay(row.dueAt));

  /// R4: what paid [row] left unpaid of its amount due, to the centavo.
  /// Only a recorded interest payment counts: a borrower submission records
  /// none (0) and is paid in full, and so are rows paid before R4 whose
  /// payment matched the amount shown.
  static double _interestShortfall(LoanSchedule row) {
    final isPaid = row.status == LoanStatus.paid_on_time ||
        row.status == LoanStatus.paid_late;
    if (!isPaid || !row.isOpenTerm || row.interestPayment <= 0) {
      return 0;
    }

    return max(0, ((row.amortization - row.interestPayment) * 100).round()) /
        100;
  }

  /// Calculates open-term loan with additional loan amounts and creates
  /// the full schedule list including paid schedules and placeholders.
  ///
  /// Returns new rows only for the bills and placeholders; the stored rows
  /// in [paidSchedules] are listed as they are, never changed (#145).
  static LoanCalculationResult calculateOpenTerm({
    required double amount,
    required DateTime date,
    required double interestRate,
    required String term,
    required String companyId,
    List<LoanSchedule> paidSchedules = const [],
    bool forSoa = false,
    Loan? loan,
    DateTime? now,
  }) {
    final (:schedules, :totalLoanPayment, :monthlyAmortization) =
        calculateOpenTermSchedules(
      amount: amount,
      date: date,
      interestRate: interestRate,
      term: term,
      forSoa: forSoa,
      companyId: companyId,
      paidSchedules: paidSchedules,
      now: now,
      additionalLoans: loan?.additionalLoanAmounts ?? const [],
    );

    final allSchedules = [
      ...paidSchedules.sortedBy((sched) => sched.dueAt),
      ...schedules,
    ];

    if (loan != null) {
      final principalRelease = LoanSchedule.create(
        dueAt: loan.createdAt,
        loanId: loan.id,
        outstandingBalance: 0,
        principalPayment: amount,
        interestCharge: 0,
        amortization: 0,
        advanceInterestPayments: loan.additionalChargeUpfrontCollection,
        interestDayMultiplier: 1,
        companyId: companyId,
        isOpenTerm: true,
        isPlaceholder: true,
        principalLoan: amount,
      );

      allSchedules.insert(0, principalRelease);

      // Sort by createdAt ascending so older additional loans are processed
      // first. Processing out of order causes incorrect outstanding balances
      // because later iterations overwrite earlier schedules' OB values.
      final sortedAdditionalLoans =
          loan.additionalLoanAmounts.sortedBy((a) => a.createdAt);

      for (final additionalLoanAmount in sortedAdditionalLoans) {
        // The top-up row is shown, not billed (R5 bills the cycle on its due
        // row). It sits before the first bill due on or after its day and
        // shows what the old balance accrued since the row before it.
        final topUpDay = _localDay(additionalLoanAmount.createdAt);
        var index = allSchedules.indexWhere(
          (schedule) =>
              !schedule.isAdditionalLoanAmount &&
              !_localDay(schedule.dueAt).isBefore(topUpDay),
          1,
        );
        if (index == -1) {
          index = allSchedules.length;
        }

        final previous = allSchedules[index - 1];
        final balanceBefore = identical(previous, principalRelease)
            ? amount
            : previous.outstandingBalance;
        final interestDayMultiplier =
            max(0, _days(_localDay(previous.dueAt), topUpDay)) / 30;

        allSchedules.insert(
          index,
          LoanSchedule.createAdditionalLoan(
            additionalLoanId: additionalLoanAmount.id,
            createdAt: additionalLoanAmount.createdAt,
            loanId: loan.id,
            outstandingBalance: balanceBefore +
                additionalLoanAmount.amount +
                additionalLoanAmount.additionalCharges,
            principalPayment: 0,
            interestCharge:
                balanceBefore * (interestRate / 100) * interestDayMultiplier,
            amortization: 0,
            interestDayMultiplier: interestDayMultiplier,
            companyId: companyId,
            isOpenTerm: true,
            isPlaceholder: true,
            advanceInterestPayments: additionalLoanAmount.advanceCharges,
            principalLoan: additionalLoanAmount.amount,
            status: additionalLoanAmount.status,
          ),
        );
      }
    }

    return LoanCalculationResult(
      schedules: allSchedules,
      monthlyAmortization: monthlyAmortization,
      totalLoanPayment: totalLoanPayment,
    );
  }
}
