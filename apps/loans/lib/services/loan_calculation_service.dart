import 'dart:math';

import 'package:collection/collection.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
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

  /// Calculates loan schedules for open-term loans.
  ///
  /// Note: 1 month = 30 days (even if in a month there are 31 or 28 days)
  ///
  /// [now] is the clock used to clamp a past due date to today and, for
  /// `'D1,D2'` terms, to pick the next salary day when the start date is on
  /// neither. Defaults to the wall clock; tests pass a fixed date.
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
  }) {
    final clientLoanSchedules = <LoanSchedule>[];
    final monthlyInterestRate = interestRate / 100;
    var outstandingBalance = amount;
    var totalLoanPayment = 0.0;
    var monthlyAmortization = 0.0;
    const numOfPayments = 1;
    var nextDate = Jiffy.parseFromDateTime(date).startOf(Unit.day);
    final clock = Jiffy.parseFromDateTime(now ?? DateTime.now());
    paidSchedules.sortBy((sched) => sched.dueAt);

    if (paidSchedules.isNotEmpty) {
      outstandingBalance = paidSchedules.last.outstandingBalance;
      final lastPaidLoanSchedule = paidSchedules.last;

      if (lastPaidLoanSchedule.paidAt != null) {
        nextDate = Jiffy.parseFromMillisecondsSinceEpoch(
          lastPaidLoanSchedule.dueAt.millisecondsSinceEpoch,
        ).startOf(Unit.day);
      } else {
        _log.warning(
          'loan schedules last payment date should not be null. '
          'Are you sure this is intentional?',
        );
        nextDate = Jiffy.parseFromMillisecondsSinceEpoch(
          lastPaidLoanSchedule.dueAt.millisecondsSinceEpoch,
        ).startOf(Unit.day);
      }
    }

    if (term.contains(',')) {
      final nextDay = nextDate.date;
      final splitTerm = term.split(',');
      final tempFirstSalaryDay = int.parse(splitTerm[0]);
      final tempSecondSalaryDay = int.parse(splitTerm[1]);
      final firstSalaryDay = min(tempFirstSalaryDay, tempSecondSalaryDay);
      final secondSalaryDay = max(tempFirstSalaryDay, tempSecondSalaryDay);

      if (nextDay == firstSalaryDay) {
        nextDate = Jiffy.parseFromDateTime(
          DateTime(nextDate.year, nextDate.month, secondSalaryDay),
        ).startOf(Unit.day);
      } else if (nextDay == secondSalaryDay) {
        nextDate = nextDate.add(months: 1);
        nextDate = Jiffy.parseFromDateTime(
          DateTime(nextDate.year, nextDate.month, firstSalaryDay),
        ).startOf(Unit.day);
      } else {
        final nowDay = clock.date;

        if (nowDay < firstSalaryDay) {
          nextDate = Jiffy.parseFromDateTime(
            DateTime(clock.year, clock.month, firstSalaryDay),
          ).startOf(Unit.day);
        } else if (nowDay < secondSalaryDay) {
          nextDate = Jiffy.parseFromDateTime(
            DateTime(clock.year, clock.month, secondSalaryDay),
          ).startOf(Unit.day);
        } else {
          nextDate = Jiffy.parseFromDateTime(
            DateTime(clock.year, clock.month, firstSalaryDay),
          ).startOf(Unit.day).add(months: 1);
        }
      }
    } else if (term == '15d') {
      nextDate = nextDate.add(days: 15);
    } else {
      nextDate = nextDate.add(days: 30);
    }

    if (nextDate.isSameOrBefore(clock)) {
      nextDate = clock.startOf(Unit.day);
    }

    final loanMonthlyAmortization = calculateMonthlyPaymentSimple(
      outstandingBalance: outstandingBalance,
      monthlyInterestRate: monthlyInterestRate,
    );

    _log.finest('loan amortization: $loanMonthlyAmortization');

    monthlyAmortization = loanMonthlyAmortization;
    totalLoanPayment = double.infinity;
    _log
      ..finest('totalLoanPayment: $totalLoanPayment')
      ..finest('---------------------------------------------------');
    for (var i = 1; i <= numOfPayments; i++) {
      var interestDayMultiplier = 1.0;
      var lastDate = Jiffy.parseFromDateTime(date).startOf(Unit.day);

      if (paidSchedules.isNotEmpty) {
        lastDate = Jiffy.parseFromDateTime(
          paidSchedules[paidSchedules.length - 1].dueAt,
        ).startOf(Unit.day);
      }

      final diffDays = nextDate
          .diff(
            lastDate,
            unit: Unit.day,
          )
          .abs();

      interestDayMultiplier = (diffDays / 30).abs();

      final beginningBalance = outstandingBalance;
      final interestCharge =
          outstandingBalance * monthlyInterestRate * interestDayMultiplier;
      _log
        ..finest('month: $i')
        ..finest('date: ${nextDate.format()}')
        ..finest('monthly: $monthlyAmortization')
        ..finest('interestCharge: $interestCharge')
        ..finest('interestDayMultiplier: $interestDayMultiplier')
        ..finest('principalPayment: 0')
        ..finest('outstandingBalance: $outstandingBalance')
        ..finest('beginningBalance: $beginningBalance')
        ..finest('---------------------------------------------------');
      final schedule = LoanSchedule.create(
        dueAt: nextDate.dateTime,
        outstandingBalance: outstandingBalance,
        amortization: min(
          min(loanMonthlyAmortization, beginningBalance + interestCharge),
          interestCharge,
        ),
        principalPayment: 0,
        interestCharge: interestCharge,
        loanId: 'loanId:$i',
        isOpenTerm: true,
        interestDayMultiplier: interestDayMultiplier,
        companyId: companyId,
      );

      clientLoanSchedules.add(schedule);
    }

    return (
      schedules: clientLoanSchedules,
      totalLoanPayment: totalLoanPayment,
      monthlyAmortization: monthlyAmortization,
    );
  }

  /// Calculates open-term loan with additional loan amounts and creates
  /// the full schedule list including paid schedules and placeholders.
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
    final allSchedules = <LoanSchedule>[];
    var totalLoanPayment = 0.0;
    var monthlyAmortization = 0.0;

    final (:schedules, totalLoanPayment: tlp, monthlyAmortization: ma) =
        calculateOpenTermSchedules(
      amount: amount,
      date: date,
      interestRate: interestRate,
      term: term,
      forSoa: forSoa,
      companyId: companyId,
      paidSchedules: paidSchedules,
      now: now,
    );

    final tempClientLoanSchedules = <LoanSchedule>[];
    tempClientLoanSchedules
      ..addAll(paidSchedules)
      ..addAll(schedules);
    totalLoanPayment = tlp;
    monthlyAmortization = ma;

    if (loan != null) {
      final firstSchedule = LoanSchedule.create(
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

      tempClientLoanSchedules.insert(0, firstSchedule);

      // Sort by createdAt ascending so older additional loans are processed
      // first. Processing out of order causes incorrect outstanding balances
      // because later iterations overwrite earlier schedules' OB values.
      final sortedAdditionalLoans = loan.additionalLoanAmounts
          .sortedBy((a) => a.createdAt);

      for (final additionalLoanAmount in sortedAdditionalLoans) {
        var index = -1;
        var lastLoanSchedule =
            tempClientLoanSchedules.sublist(1).firstWhereOrNull((schedule) {
          if (Jiffy.parseFromDateTime(schedule.createdAt).isSameOrAfter(
            Jiffy.parseFromDateTime(additionalLoanAmount.createdAt),
          )) {
            return true;
          }
          return false;
        });

        if (lastLoanSchedule == null) {
          index = tempClientLoanSchedules.length;
          lastLoanSchedule = tempClientLoanSchedules.last;
        } else {
          index = tempClientLoanSchedules.indexOf(lastLoanSchedule);
        }

        LoanSchedule additionalSchedule;
        if (Jiffy.parseFromDateTime(lastLoanSchedule.dueAt).isSame(
          Jiffy.parseFromDateTime(additionalLoanAmount.createdAt),
        )) {
          additionalSchedule = LoanSchedule.createAdditionalLoan(
            additionalLoanId: additionalLoanAmount.id,
            createdAt: additionalLoanAmount.createdAt,
            loanId: loan.id,
            outstandingBalance: (lastLoanSchedule.outstandingBalance) +
                additionalLoanAmount.amount +
                additionalLoanAmount.additionalCharges,
            principalPayment: lastLoanSchedule.principalPayment,
            interestCharge: lastLoanSchedule.interestCharge,
            amortization: lastLoanSchedule.amortization,
            interestDayMultiplier: lastLoanSchedule.interestDayMultiplier,
            companyId: companyId,
            isOpenTerm: true,
            isPlaceholder: true,
            advanceInterestPayments: additionalLoanAmount.advanceCharges,
            principalLoan: additionalLoanAmount.amount,
            status: additionalLoanAmount.status,
          );

          tempClientLoanSchedules.setAll(index, [additionalSchedule]);
        } else {
          num diffDays = 0;

          if (lastLoanSchedule.id == NO_ID &&
              !lastLoanSchedule.isPlaceholder) {
            if (index > 0) {
              final priorSchedule = tempClientLoanSchedules[index - 1];
              final priorScheduleDate =
                  Jiffy.parseFromDateTime(priorSchedule.dueAt);
              final additionalLoanDate =
                  Jiffy.parseFromDateTime(additionalLoanAmount.createdAt);

              if (additionalLoanDate.isSame(priorScheduleDate)) {
                diffDays = 0;
              } else {
                diffDays = additionalLoanDate
                    .diff(priorScheduleDate, unit: Unit.day)
                    .abs();
              }
            } else {
              _log.warning(
                'Cannot calculate diff days for additional loan: '
                'Index is 0 therefore there is a problem creating '
                'tempClientLoanSchedules. Developers, please check.',
              );
              diffDays = 0;
            }
          } else {
            diffDays =
                Jiffy.parseFromDateTime(additionalLoanAmount.createdAt)
                    .diff(
                      Jiffy.parseFromDateTime(lastLoanSchedule.dueAt),
                      unit: Unit.day,
                    )
                    .abs();
          }

          final interestDayMultiplier = (diffDays / 30).abs();
          final interestCharge = lastLoanSchedule.outstandingBalance *
              (interestRate / 100) *
              interestDayMultiplier;
          additionalSchedule = LoanSchedule.createAdditionalLoan(
            additionalLoanId: additionalLoanAmount.id,
            createdAt: additionalLoanAmount.createdAt,
            loanId: loan.id,
            outstandingBalance: (lastLoanSchedule.outstandingBalance) +
                additionalLoanAmount.amount +
                additionalLoanAmount.additionalCharges,
            principalPayment: lastLoanSchedule.principalPayment,
            interestCharge: interestCharge,
            amortization: lastLoanSchedule.amortization,
            interestDayMultiplier: interestDayMultiplier,
            companyId: companyId,
            isOpenTerm: true,
            isPlaceholder: true,
            advanceInterestPayments: additionalLoanAmount.advanceCharges,
            principalLoan: additionalLoanAmount.amount,
            status: additionalLoanAmount.status,
          );

          tempClientLoanSchedules.insert(index, additionalSchedule);
          lastLoanSchedule
            ..outstandingBalance = additionalSchedule.outstandingBalance
            ..interestCharge = additionalSchedule.interestCharge;
        }
      }
    }
    allSchedules.addAll(tempClientLoanSchedules);

    return LoanCalculationResult(
      schedules: allSchedules,
      monthlyAmortization: monthlyAmortization,
      totalLoanPayment: totalLoanPayment,
    );
  }
}
