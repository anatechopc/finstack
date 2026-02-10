import 'dart:math';

import 'package:collection/collection.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans_helpers/logging_helpers.dart';

/// Note:
///   1 month = 30 days. even if in a month there are 31 or 28 days,
///   a month is 30 days
double calculateMonthlyPaymentSimple({
  required double outstandingBalance,
  required double monthlyInterestRate,
}) {
  return outstandingBalance * monthlyInterestRate;
}

({
  List<LoanSchedule> schedules,
  double totalLoanPayment,
  double monthlyAmortization
}) calculateLoanOpen({
  required double amount,
  required DateTime date,
  required double interestRate,
  required String term,
  required String companyId,
  List<LoanSchedule> paidSchedules = const [],
  bool forSoa = false,
}) {
  final clientLoanSchedules = <LoanSchedule>[];
  final log = Logger('loans_bloc_extension_calculate_loan_open');
  final monthlyInterestRate = interestRate / 100;
  var outstandingBalance = amount;
  var totalLoanPayment = 0.0;
  var monthlyAmortization = 0.0;
  // defaults to 1 month of monthly / bi-monthly / salary days payments
  // but this does not really matter in the actual schedule
  const numOfPayments = 1;
  var nextDate = Jiffy.parseFromDateTime(date).startOf(Unit.day);
  final now = Jiffy.now();
  // making sure that paid schedules are sorted by payment date
  paidSchedules.sortBy((sched) => sched.dueAt);

  var loanMonthlyAmortization = 0.0;

  if (paidSchedules.isNotEmpty) {
    outstandingBalance = paidSchedules.last.outstandingBalance;
    final lastPaidLoanSchedule = paidSchedules.last;

    if (lastPaidLoanSchedule.paidAt != null) {
      nextDate = Jiffy.parseFromMillisecondsSinceEpoch(
        lastPaidLoanSchedule.dueAt.millisecondsSinceEpoch,
      ).startOf(Unit.day);
    } else {
      log.warning(
          'loan schedules last payment date should not be null. Are you sure this is intentional?',);

      nextDate = Jiffy.parseFromMillisecondsSinceEpoch(
        lastPaidLoanSchedule.dueAt.millisecondsSinceEpoch,
      ).startOf(Unit.day);
    }
  }

  if (term.contains(',')) {
    // salary days
    final nextDay = nextDate.date;
    final splitTerm = term.split(',');
    final tempFirstSalaryDay = int.parse(splitTerm[0]);
    final tempSecondSalaryDay = int.parse(splitTerm[1]);
    final firstSalaryDay = min(tempFirstSalaryDay, tempSecondSalaryDay);
    final secondSalaryDay = max(tempFirstSalaryDay, tempSecondSalaryDay);

    if (nextDay == firstSalaryDay) {
      // next date should the 2nd day
      nextDate = Jiffy.parseFromDateTime(
        DateTime(nextDate.year, nextDate.month, secondSalaryDay),
      ).startOf(Unit.day);
    } else if (nextDay == secondSalaryDay) {
      // nextDate should be the 1st day of next mon
      nextDate = nextDate.add(months: 1);
      nextDate = Jiffy.parseFromDateTime(
        DateTime(nextDate.year, nextDate.month, firstSalaryDay),
      ).startOf(Unit.day);
    } else {
      final nowDay = now.date;

      if (nowDay < firstSalaryDay) {
        nextDate = Jiffy.parseFromDateTime(
          DateTime(now.year, now.month, firstSalaryDay),
        ).startOf(Unit.day);
      } else if (nowDay < firstSalaryDay) {
        nextDate = Jiffy.parseFromDateTime(
          DateTime(now.year, now.month, secondSalaryDay),
        ).startOf(Unit.day);
      } else {
        // first salary day of next month;
        nextDate = Jiffy.parseFromDateTime(
          DateTime(now.year, now.month, firstSalaryDay),
        ).startOf(Unit.day).add(months: 1);
      }
    }
  } else if (term == '15d') {
    // every 15 days
    nextDate = nextDate.add(days: 15);
  } else {
    // this is 1 month
    nextDate = nextDate.add(days: 30);
  }

  if (nextDate.isSameOrBefore(now)) {
    nextDate = now.startOf(Unit.day);
  }

  loanMonthlyAmortization = calculateMonthlyPaymentSimple(
    outstandingBalance: outstandingBalance,
    monthlyInterestRate: monthlyInterestRate,
  );

  log.finest('loan amortization: $loanMonthlyAmortization');

  monthlyAmortization = loanMonthlyAmortization;
  totalLoanPayment = double.infinity;
  log
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

    // the difference in days is added by 1. This is because the
    // Jiffy.diff() computes how many days has elapsed between 2 days.
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
    // final principalPayment = monthlyAmortization - interestCharge;
    // outstandingBalance -= principalPayment;
    log
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
      // beginningBalance: beginningBalance,
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
