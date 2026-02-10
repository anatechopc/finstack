import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/reports/bloc/report_bloc_exceptions.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/features/reports/models/charge_simple.dart';
import 'package:loooans/features/reports/models/loan_balance_simple.dart';
import 'package:loooans/features/reports/models/soa_entry.dart';
import 'package:loooans/features/reports/models/soa_model.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_repository/user_repository.dart';

extension ReportsBlocExtensionSoa on ReportsBloc {
  Future<void> handleGenerateSOAEvent(
    GenerateSOAEvent event,
    Emitter<ReportsState> emit,
  ) async {
    try {
      emit(const ReportsState.loading(isLoading: true));
      final loan = await loanRepository.get(id: event.loanId);

      if (loan.dueAt != null) {
        throw GenerateSOAException('Not an Open term loan');
      }
      final results = await Future.wait([
        userRepository.get(id: loan.userId),
        loanScheduleRepository.allByLoanId(
          loanId: loan.id,
        ),
      ]);
      final paidSchedules = results[1] as List<LoanSchedule>;

      final (:schedules, :totalLoanPayment, :monthlyAmortization) =
          LoanCalculationService.calculateOpenTermSchedules(
        amount: loan.amount,
        date: loan.createdAt,
        interestRate: loan.interestRate,
        term: loan.term,
        paidSchedules: paidSchedules,
        forSoa: true,
        companyId: loan.companyId,
      );

      // do post updates here for
      schedules.addAll(paidSchedules);
      final otherLoans = await _getOtherLoans(
        userId: loan.userId,
        loanId: loan.id,
      );
      soaModel = await _generateSOA(
        user: results[0] as User,
        loan: loan,
        schedules: schedules,
        otherLoans: otherLoans,
      );

      emit(const ReportsState.loading());
      emit(const ReportsState.soaGeneratedRefresh());
    } on GenerateSOAException catch (err) {
      log.severe('GenerateSOAEvent: $err', err);
      emit(const ReportsState.loading());
      emit(ReportsState.error(
          'Cannot generate Statement of account: $err',),);
    } catch (err) {
      log.severe('GenerateSOAEvent: $err', err);
      emit(const ReportsState.loading());
      emit(const ReportsState.error('Cannot generate Statement of account'));
    }
  }

  /// getting other loans other than the loan id
  Future<List<LoanBalanceSimple>> _getOtherLoans({
    required String userId,
    required String loanId,
  }) async {
    final otherLoans = <LoanBalanceSimple>[];
    final loans = await loanRepository.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(
          field: 'user_id',
          isEqualTo: userId,
        ),
        QueryStatement(
          field: 'status',
          whereIn: [
            LoanStatus.approved.name,
            LoanStatus.payment_submitted.name,
            LoanStatus.paid_on_time.name,
            LoanStatus.paid_late.name,
            LoanStatus.not_paid.name,
            LoanStatus.not_paid_overdue.name,
          ],
        ),
        QueryStatement(
          field: 'parent_id',
          isEqualTo: loanId,
        ),
      ],
    );

    for (final loan in loans) {
      // there should only be one schedule.
      // if there's no schedule, this will throw an error
      LoanSchedule? schedule;

      try {
        schedule = (await loanScheduleRepository.load(
          reset: true,
          limit: 1,
          statements: [
            QueryStatement(
              field: 'loan_id',
              isEqualTo: loan.id,
            ),
          ],
        ))
            .single;
      } catch (err) {
        log.warning(
            'No schedule retrieved. Make sure this is an intentional attempt.',);
      }

      final product = await productRepository.get(id: loan.productId);

      otherLoans.add(
        LoanBalanceSimple(
          outstandingBalance: schedule?.outstandingBalance ?? loan.amount,
          name: product.loanType,
        ),
      );
    }

    return otherLoans;
  }

  Future<SOAModel> _generateSOA({
    required User user,
    required Loan loan,
    required List<LoanSchedule> schedules,
    List<LoanBalanceSimple> otherLoans = const [],
  }) async {
    return Future<SOAModel>.microtask(() async {
      final now = DateTime.now();
      schedules.sortBy((sched) => sched.dueAt);

      // add the first loan entry
      final entries = <SOAEntry>[
        SOAEntry(
          date: loan.createdAt,
          principalLoan: loan.amount,
          interestCharge: 0,
          // it is assumed that the additional charges are additional interests
          advanceInterest: loan.additionalCharges,
          interestPayment: 0,
          principalPayment: 0,
          principalBalance: loan.amount,
          numberOfDays: '',
        ),
      ];

      for (final sched in schedules) {
        entries.add(
          SOAEntry(
              date: sched.dueAt,
              principalLoan: 0,
              interestCharge: sched.interestCharge,
              advanceInterest: sched.advanceInterestPayments,
              interestPayment: sched.interestPayment,
              principalPayment: sched.principalPayment,
              principalBalance: sched.outstandingBalance,
              numberOfDays: (sched.interestDayMultiplier * 30).toString(),),
        );
      }

      for (final amount in loan.additionalLoanAmounts) {
        // NOTE: the implementation below will have an impact for large data sets,
        // by large meaning, by thousands of [entries]
        // Also, since the application is running primarily on the browser, this
        // will affect user experience as well.
        var entry = entries.singleWhereOrNull(
          (entry) => Jiffy.parseFromDateTime(entry.date).isSame(
            Jiffy.parseFromDateTime(amount.createdAt),
            unit: Unit.day,
          ),
        );

        // if entry is null, get the nearest entry before the date of the
        // amount created
        entry ??=
            entries.lastWhereOrNull((e) => e.date.isBefore(amount.createdAt));

        var outstandingBalance = 0.0;
        var interestCharge = 0.0;
        var interestPayment = 0.0;
        var principalPayment = 0.0;

        if (entry != null) {
          outstandingBalance = entry.principalBalance;
          interestCharge = entry.interestCharge;
          interestPayment = entry.interestPayment;
          principalPayment = entry.principalPayment;
          entry.toRemove = Jiffy.parseFromDateTime(entry.date).isSame(
            Jiffy.parseFromDateTime(amount.createdAt),
            unit: Unit.day,
          );
        }

        entries.add(
          SOAEntry(
            date: amount.createdAt,
            principalLoan: amount.amount,
            interestCharge: interestCharge,
            advanceInterest: amount.amount * (loan.interestRate / 100),
            interestPayment: interestPayment,
            principalPayment: principalPayment,
            principalBalance: outstandingBalance + amount.amount,
            numberOfDays: '',
          ),
        );
      }

      // remove all to remove entries
      entries
        ..removeWhere((entry) => entry.toRemove)
        ..sortBy((entry) => entry.date);

      // process entries principal balance
      final lastEntry = entries.last;
      final lastPreviousEntry = entries[entries.length - 2];
      lastEntry.principalBalance = math.max(
        lastPreviousEntry.principalBalance,
        lastPreviousEntry.principalBalance,
      );

      final results = await Future.wait([
        Future.microtask(() {
          return entries.fold<double>(0, (prev, next) {
            return prev + next.interestCharge;
          });
        }),
        Future.microtask(() {
          return entries.fold<double>(0, (prev, next) {
            return prev + next.advanceInterest;
          });
        }),
        Future.microtask(() {
          return entries.fold<double>(0, (prev, next) {
            return prev + next.interestPayment;
          });
        }),
        Future.microtask(() {
          return entries.fold<double>(0, (prev, next) {
            return prev + next.principalLoan;
          });
        }),
        Future.microtask(() {
          return entries.fold<double>(0, (prev, next) {
            return prev + next.principalPayment;
          });
        }),
      ]);

      // add the last entry
      entries.add(
        SOAEntry(
          isTotal: true,
          date: now,
          principalLoan: results[3],
          interestCharge: results[0],
          advanceInterest: results[1],
          interestPayment: results[2],
          principalPayment: results[4],
          principalBalance: entries.last.principalBalance,
          numberOfDays: '',
        ),
      );

      final deductions = [
        ChargeSimple(
          amount: results[0] - results[1] - results[2],
          description: 'Rebates',
        ),
      ];

      final additionalCharges = otherLoans
          .map(
            (other) => ChargeSimple(
              amount: other.outstandingBalance,
              description: other.name,
            ),
          )
          .toList();

      final totalAmount = entries.last.principalBalance -
          deductions.fold<double>(0, (prev, next) {
            return prev + next.amount;
          }).abs();

      final totalAmountDue = totalAmount +
          additionalCharges.fold(0.0, (prev, next) {
            return prev + next.amount;
          });

      return SOAModel(
        userId: user.id,
        date: now,
        fullName: user.completeNameEasternOrder,
        interest: loan.interestRate,
        term: loan.completeTerm,
        entries: entries,
        totalInterestCharge: results[0],
        lessAdvanceInterest: results[1],
        lessTotalInterestCollected: results[2],
        deductions: deductions,
        outstandingPrincipalBalance: entries.last.principalBalance,
        totalAmount: totalAmount,
        additionalCharges: additionalCharges,
        totalAmountDue: totalAmountDue,
        // the 6 represents the fields that are not in the list but is needed
        // to include in the count to generate how many rows in a table should
        // have. the count doesn't include the date, fullName, interest and term.
        // the +1 is the rebate
        size: entries.length +
            deductions.length +
            additionalCharges.length +
            6 +
            1,
      );
    });
  }
}
