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
  ///
  /// Resuming after the stored [paidSchedules] (owner, 2026-11-19, #152):
  /// the next bill is the amortization plus the principal the last stored
  /// row left unpaid, and the last bill clears the whole balance, rounding
  /// included. When every bill is stored and the last one left principal
  /// owed, one more row bills it: due on the last due date, no interest.
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
    // A remainder row shares the last due date; the balance only falls, so
    // the lower balance is the later row.
    paidSchedules.sortByCompare(
      (sched) => sched,
      (a, b) => a.dueAt != b.dueAt
          ? a.dueAt.compareTo(b.dueAt)
          : b.outstandingBalance.compareTo(a.outstandingBalance),
    );
    var monthlyInterestRate = interestRate / 100;
    var outstandingBalance = amount;
    var numOfPayments = monthsToPay;
    var nextMonthDate = Jiffy.parseFromDateTime(date).startOf(Unit.day);

    var loanMonthlyAmortization = 0.0;
    var carry = 0.0;

    if (paidSchedules.isEmpty) {
      loanMonthlyAmortization = amount.calculateMonthlyPayment(
        monthlyInterestRate: monthlyInterestRate,
        monthsToPay: monthsToPay,
        term: term,
      );
    } else {
      loanMonthlyAmortization = paidSchedules.first.amortization;
      outstandingBalance = paidSchedules.last.outstandingBalance;
      carry = _principalShortfall(paidSchedules.last);
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
      final monthlyAmort = i == numOfPayments
          ? beginningBalance + interestPayment
          : min(
              loanMonthlyAmortization + carry,
              beginningBalance + interestPayment,
            );
      carry = 0;
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
        amortization: monthlyAmort,
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

    final last = paidSchedules.lastOrNull;
    if (numOfPayments <= 0 &&
        last != null &&
        _isPaid(last) &&
        leavesPrincipal(last)) {
      final remainder = LoanSchedule.create(
        dueAt: last.dueAt,
        outstandingBalance: 0,
        amortization: last.outstandingBalance,
        principalPayment: last.outstandingBalance,
        interestCharge: 0,
        loanId: 'loanId:1',
        interestDayMultiplier: 0,
        companyId: companyId,
      );
      totalLoanPayment += remainder.amortization;
      schedules.add(remainder);
    }

    return LoanCalculationResult(
      schedules: schedules,
      monthlyAmortization: monthlyAmortization,
      totalLoanPayment: totalLoanPayment,
    );
  }

  /// Whether an open-term [loan] bills cycles: a pending, declined,
  /// completed (settled) or bad-debt loan gets no new bills, no penalty and
  /// no "Make payment" (review of #146).
  static bool billsOpenTerm(Loan loan) => !const {
        LoanStatus.pending,
        LoanStatus.declined,
        LoanStatus.completed,
        LoanStatus.bad_debt,
      }.contains(loan.status);

  /// Only an approved top-up has released money, so only it moves the
  /// balance and the bill (#137). A top-up takes effect on the day it was
  /// approved (`effectiveAt`: the creation day for top-ups approved before
  /// `approved_at` was recorded; review of #149).
  static bool movesBalance(AdditionalLoanAmount topUp) =>
      topUp.status == LoanStatus.approved;

  /// Calculates the open-term bills owed after the loan's last stored row.
  ///
  /// Owner rules R1-R5 (2026-11-14 to 2026-11-19; golden set G14):
  /// - R1: a bill keeps its scheduled date. `'1m'` and `'15d'` bills fall
  ///   every 30 or 15 calendar days from [date] (the loan's local creation
  ///   day), the way the first bill always did; a stored bill within one
  ///   day of a scheduled date counts as that bill; salary-day terms (`'D1,D2'`) fall
  ///   on the next salary day after the previous bill (the month's last day
  ///   when the salary day does not exist). Never from today or from a
  ///   payment date (finstack#144). All days are local calendar days.
  /// - R2: every bill due before today is its own row, followed by the first
  ///   bill due today or later. Each row bills its own cycle: no interest
  ///   accrued to today, no one-month cap (finstack#120).
  /// - R4: what the last stored row left unpaid of its amount due (an
  ///   interest shortfall) is added to the first new bill's amount due
  ///   (`amortization`); its `interestCharge` stays the cycle's interest.
  /// - R5: an approved top-up not yet in the stored balance splits its
  ///   cycle: the old balance up to the top-up day (its approval day), the
  ///   new balance from that day on (finstack#117). Days between a top-up
  ///   and the start of
  ///   the first new cycle (the previous bill was paid early) are billed
  ///   with it.
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
    // The principal release approval stores for app-managed companies is
    // not a bill: continuing from it (balance 0) would bill 0 (#138).
    final last = paidSchedules
        .where((sched) => !sched.isPrincipalRelease)
        .sortedBy((sched) => sched.dueAt)
        .lastOrNull;
    final lastBill = last == null ? null : _localDay(last.lateFrom);
    final start = _localDay(date);
    // A stored row dated a day off the schedule (a first bill the old engine
    // dated on the creation day's UTC date, or a row written in another
    // zone) is the scheduled bill a day after it: no 1-day bill. A row ON a
    // scheduled date never absorbs the next one (salary days a day apart:
    // '15,16', '1,30' after Feb 28), and a row further away (an old clamp
    // row) does not move the schedule (reviews of #146).
    final offSchedule = lastBill != null &&
        !_isScheduledDate(term: term, start: start, day: lastBill);
    final today = _localDay(now ?? DateTime.now());

    var balance = last?.outstandingBalance ?? amount;
    var cycleStart = last == null ? start : _localDay(last.dueAt);
    var carry = last == null ? 0.0 : _interestShortfall(last);
    final topUps = additionalLoans
        .where(movesBalance)
        .where((topUp) => last == null || !_includesTopUp(last, topUp))
        // In the order they take effect (finstack#4: processed out of order,
        // a later top-up overwrote an earlier one's balance).
        .sortedBy((topUp) => topUp.effectiveAt);
    var nextTopUp = 0;

    final monthlyAmortization = calculateMonthlyPaymentSimple(
      outstandingBalance: balance,
      monthlyInterestRate: monthlyInterestRate,
    );
    _log.finest('loan amortization: $monthlyAmortization');

    final schedules = <LoanSchedule>[];
    for (final dueAt in _openTermDueDates(
      term: term,
      start: start,
      after: cycleStart,
    )) {
      if (offSchedule && _days(lastBill, dueAt) <= 1) {
        continue;
      }
      var interestCharge = 0.0;
      var from = cycleStart;
      while (nextTopUp < topUps.length) {
        final topUp = topUps[nextTopUp];
        final topUpDay = _localDay(topUp.effectiveAt);
        if (topUpDay.isAfter(dueAt)) {
          break;
        }
        final added = topUp.amount + topUp.additionalCharges;
        if (topUpDay.isBefore(cycleStart)) {
          // The previous bill was paid early, before this top-up: its days
          // up to that bill's due date were never billed (R5).
          interestCharge +=
              added * monthlyInterestRate * _days(topUpDay, cycleStart) / 30;
        } else {
          interestCharge +=
              balance * monthlyInterestRate * _days(from, topUpDay) / 30;
          from = topUpDay;
        }
        balance += added;
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
      // The bill due today or later is the current one; never dropped.
      if (!dueAt.isBefore(today)) {
        break;
      }
    }

    return (
      schedules: schedules,
      // Sentinel: an open-term loan has no fixed total.
      totalLoanPayment: double.infinity,
      monthlyAmortization: monthlyAmortization,
    );
  }

  /// R1: the scheduled bill dates after [after], in order, one at a time.
  /// `'D1,D2'` are the salary days of each month (the month's last day when
  /// one does not exist); `'15d'` steps 15 calendar days from [start] (the
  /// local creation day), anything else 30. Calendar days, so a
  /// daylight-saving change cannot move a date (campaign D11).
  static Iterable<Jiffy> _openTermDueDates({
    required String term,
    required Jiffy start,
    required Jiffy after,
  }) sync* {
    if (term.contains(',')) {
      yield* _salaryDueDates(term: term, after: after);
      return;
    }

    final step = term == '15d' ? 15 : 30;
    Jiffy billOn(int cycle) => Jiffy.parseFromDateTime(
          DateTime(start.year, start.month, start.date + step * cycle),
        );
    var cycle = 1;
    while (!billOn(cycle).isAfter(after)) {
      cycle++;
    }
    for (;; cycle++) {
      yield billOn(cycle);
    }
  }

  /// The salary days of each month after [after] (`'15,30'`: the 15th and
  /// the 30th, or the month's last day when it has no 30th).
  static Iterable<Jiffy> _salaryDueDates({
    required String term,
    required Jiffy after,
  }) sync* {
    final splitTerm = term.split(',');
    final tempFirstSalaryDay = int.parse(splitTerm[0]);
    final tempSecondSalaryDay = int.parse(splitTerm[1]);
    final salaryDays = [
      min(tempFirstSalaryDay, tempSecondSalaryDay),
      max(tempFirstSalaryDay, tempSecondSalaryDay),
    ];
    var previous = after;
    for (var month = after.month;; month++) {
      final lastDay = DateTime(after.year, month + 1, 0).day;
      for (final salaryDay in salaryDays) {
        final dueAt = Jiffy.parseFromDateTime(
          DateTime(after.year, month, min(salaryDay, lastDay)),
        );
        if (dueAt.isAfter(previous)) {
          yield dueAt;
          previous = dueAt;
        }
      }
    }
  }

  /// Whether [day] is one of the loan's scheduled bill dates.
  static bool _isScheduledDate({
    required String term,
    required Jiffy start,
    required Jiffy day,
  }) {
    final dayBefore = Jiffy.parseFromDateTime(
      DateTime(day.year, day.month, day.date - 1),
    );
    final next =
        _openTermDueDates(term: term, start: start, after: dayBefore).first;

    return _days(day, next) == 0;
  }

  /// Start of [dateTime]'s calendar day on this device. Stored dates come
  /// back in UTC.
  static Jiffy _localDay(DateTime dateTime) =>
      Jiffy.parseFromDateTime(dateTime.toLocal()).startOf(Unit.day);

  /// Calendar days from [from] to [to]: a daylight-saving change on the way
  /// cannot make a day 23 hours and drop it (campaign D11).
  static int _days(Jiffy from, Jiffy to) =>
      DateTime.utc(to.year, to.month, to.date)
          .difference(DateTime.utc(from.year, from.month, from.date))
          .inDays;

  /// Whether stored [row]'s balance already holds [topUp]: the row was
  /// computed after the top-up, and the top-up is not after the row's due
  /// day. (Rows from before R1 were never dated before the day they were
  /// computed, so for them only the first condition decides.)
  ///
  /// A top-up counts from its approval: one still pending when the row was
  /// computed is not in it (review of #146). Top-ups approved before the
  /// approval time was recorded fall back to their creation time.
  static bool _includesTopUp(LoanSchedule row, AdditionalLoanAmount topUp) =>
      topUp.effectiveAt.isBefore(row.createdAt) &&
      !_localDay(topUp.effectiveAt).isAfter(_localDay(row.dueAt));

  /// R4: what paid [row] left unpaid of its amount due, to the centavo. The
  /// amount due is the larger of `amortization` and `interestCharge`: a row
  /// from the old clamp (also written by app builds not yet updated)
  /// charged more interest than the one month it asked for. Only a recorded
  /// interest payment counts: a borrower submission records none (0) and is
  /// paid in full.
  static double _interestShortfall(LoanSchedule row) {
    if (!_isPaid(row) || !row.isOpenTerm || row.interestPayment <= 0) {
      return 0;
    }
    final amountDue = max(row.amortization, row.interestCharge);

    return max(0, ((amountDue - row.interestPayment) * 100).round()) / 100;
  }

  /// #152: the principal paid fixed-term [row] left unpaid of its bill
  /// (`amortization - interestCharge`), to the centavo. A row not paid
  /// yet (submitted or rejected) is still owed itself and carries nothing.
  static double _principalShortfall(LoanSchedule row) {
    if (!_isPaid(row)) {
      return 0;
    }
    final billed = row.amortization - row.interestCharge;

    return max(0, ((billed - row.principalPayment) * 100).round()) / 100;
  }

  /// Whether fixed-term [row] leaves principal owed (#152): more than half
  /// a centavo, so display rounding never keeps a loan open.
  static bool leavesPrincipal(LoanSchedule row) =>
      row.outstandingBalance > 0.005;

  static bool _isPaid(LoanSchedule row) =>
      row.status == LoanStatus.paid_on_time ||
      row.status == LoanStatus.paid_late;

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
      // A declined, settled or bad-debt loan bills nothing new; a pending
      // application shows its projected first bill, which nothing counts as
      // owed (no penalty, no "Make payment", not in any total).
      if (loan == null || billsOpenTerm(loan))
        ...schedules
      else if (loan.status == LoanStatus.pending)
        ...schedules.take(1),
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

      // Sort by the day each takes effect, ascending, so earlier additional
      // loans are processed first. Processing out of order causes incorrect
      // outstanding balances because later iterations overwrite earlier
      // schedules' OB values (finstack#4).
      final sortedAdditionalLoans =
          loan.additionalLoanAmounts.sortedBy((a) => a.effectiveAt);

      for (final additionalLoanAmount in sortedAdditionalLoans) {
        // The top-up row is shown, not billed (R5 bills the cycle on its due
        // row). It sits before the first bill due on or after its day and
        // shows what the old balance accrued since the row before it.
        final topUpDay = _localDay(additionalLoanAmount.effectiveAt);
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
            createdAt: additionalLoanAmount.effectiveAt,
            loanId: loan.id,
            // Only an approved top-up moves the balance (#137).
            outstandingBalance: balanceBefore +
                (movesBalance(additionalLoanAmount)
                    ? additionalLoanAmount.amount +
                        additionalLoanAmount.additionalCharges
                    : 0),
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
