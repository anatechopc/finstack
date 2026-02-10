import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/reports/bloc/reports_bloc_extension_soa.dart';
import 'package:loooans/features/reports/models/soa_model.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:product_repository/product_repository.dart' as pr;
import 'package:reports_repository/reports_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'reports_event.dart';

part 'reports_state.dart';

enum MomSalesInterval {
  yearly,
  monthly,
  weekly,
  daily;
}

class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  ReportsBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        reportsRepository = context.read<ReportsRepository>(),
        userRepository = context.read<UserRepository>(),
        loanRepository = context.read<LoanRepository>(),
        loanScheduleRepository = context.read<LoanScheduleRepository>(),
        productRepository = context.read<pr.ProductRepository>(),
        super(const ReportsState()) {
    on(_handleGetReportSummaryEvent);
    on(handleGenerateSOAEvent);
    _handleGetCountsPerStatus();
    _listenReportSummary();
  }

  final log = Logger('reports_bloc');

  final AuthenticationService authService;
  final ReportsRepository reportsRepository;
  final UserRepository userRepository;
  final LoanRepository loanRepository;
  final LoanScheduleRepository loanScheduleRepository;
  final pr.ProductRepository productRepository;

  final Map<String, TotalSummaryItem?> _totalSummary = {};

  Map<String, TotalSummaryItem?> get totalSummary => _totalSummary;

  List<DataItem> _capitalDataItems = [];

  List<DataItem> get capitalDataItems => _capitalDataItems;

  SOAModel? soaModel;

  final Map<String, int> _loanStatusCount = {};

  Map<String, int> get loanStatusCount => _loanStatusCount;

  CapitalUsage? _capitalUsage;

  CapitalUsage? get capitalUsage => _capitalUsage;

  Sales? _sales;

  Sales? get sales => _sales;

  Map<String, ProductTotals>? _products;

  Map<String, ProductTotals>? get products => _products;

  double? _receivables;

  double? get receivables => _receivables;


  void getReportSummary() {
    add(GetReportSummaryEvent());
  }

  void generateSoa(String loanId) {
    add(GenerateSOAEvent(loanId: loanId));
  }

  String getContentFromTotalSummary({
    required DateTime dateTime,
    String getFor = 'collections',
    String keyFor = 'month',
  }) {
    if (_totalSummary.isEmpty) {
      return 0.toCurrency();
    }

    final jiffyDate = Jiffy.parseFromDateTime(dateTime);
    var key = '';

    if (keyFor == 'month') {
      key = 'year:${jiffyDate.year}:month:${jiffyDate.month}';
    } else if (keyFor == 'day') {
      key =
          'year:${jiffyDate.year}:month:${jiffyDate.month}:week:${jiffyDate.weekOfYear}:day:${jiffyDate.date}';
    }

    final summary = _totalSummary[key];

    if (summary == null) {
      return 0.toCurrency();
    }

    if (getFor == 'collections') {
      return summary.totalCollections.toCurrency();
    } else if (getFor == 'releases') {
      return summary.totalAmountReleased.toCurrency();
    }

    return 0.toCurrency();
  }

  Future<void> _handleGetReportSummaryEvent(
    GetReportSummaryEvent event,
    Emitter<ReportsState> emit,
  ) async {
    log.finest('Getting reports');
    try {
      final now = Jiffy.parseFromDateTime(DateTime.now().toUtc());
      final company = authService.company;
      log.info('Getting report summary for company: ${company.id}');
      reportsRepository.init(companyId: company.id);
      _products = await reportsRepository.getProducts();
      log.fine('products: ${products?.map((k, v) => MapEntry(k, v.toJson()))}');
      emit(const ReportsState.salesByProductRefresh());
      _capitalUsage = await reportsRepository.getCapitalUsage();
      log.finest('capitalUsage: ${capitalUsage?.toJson()}');
      emit(const ReportsState.capitalUsageRefresh());
      _sales = await reportsRepository.getSales();
      emit(const ReportsState.allSalesRefresh());

      if (company.managementType == CompanyManagementType.selfManaged) {
        // collections
        final lastMonth = now.subtract(months: 1);
        final yesterday = now.subtract(days: 1);

        final totalSummary = await reportsRepository.getTotalSummary(
          keys: [
            'year:${now.year}:month:${now.month}:week:${now.weekOfYear}:day:${now.date}',
            'year:${yesterday.year}:month:${yesterday.month}:week:${yesterday.weekOfYear}:day:${yesterday.date}',
            'year:${now.year}:month:${now.month}',
            'year:${lastMonth.year}:month:${lastMonth.month}',
          ],
        );

        _totalSummary
          ..clear()
          ..addAll(totalSummary);
        log..fine(
            'totalSummary: ${totalSummary.map((k, v) => MapEntry(k, v?.toJson()))}',)
        ..fine('totalsummary done');
        emit(const ReportsState.success('success'));
      }
      _listenReportSummary();
    } catch (err) {
      final message = 'Cannot get report summary: $err';
      log.severe(message, err);

      // emit(const ReportsState.loading());
      emit(ReportsState.error(message));
    }
  }

  // status to count do be displayed in dashboard_screen.dart
  // 'New' = LoanStatus.pending
  // 'Approved' = LoanStatus.approved
  // 'Active' = LOanStatus.paid_on_time, LoanStatus.paid_late, LoanStatus.not_paid, LoanStatus.payment_submitted
  // 'Overdue' = LoanStatus.not_paid_overdeu
  // 'Settled' = LoanStatus.completed
  // 'Declined' = LoanStatus.declined
  void _handleGetCountsPerStatus() {
    if (!authService.user.isCustomer()) {
      loanRepository.loadNext(
        statements: [
          QueryStatement(
            field: 'company_id',
            isEqualTo: authService.company.id,
          ),
        ],
        limit: null,
      );
    }
  }

  Stream<Map<String, int>> loanStatusCountStream() {
    return loanRepository.dataStream.asyncMap((loans) async {
      _receivables = await _computeReceivables(loans);
      final groupedLoans = loans.groupListsBy((loan) => loan.status);
      _initializeStatusCounts();
      for (final entry in groupedLoans.entries) {
        if (entry.key == LoanStatus.pending) {
          _loanStatusCount['New'] = entry.value.length;
        }
        /*else if (entry.key == LoanStatus.approved) {
          _loanStatusCount['Approved'] = entry.value.length;
        }*/
        else if (entry.key == LoanStatus.not_paid_overdue) {
          _loanStatusCount['Overdue'] = entry.value.length;
        } else if (entry.key == LoanStatus.declined) {
          _loanStatusCount['Declined'] = entry.value.length;
        } else if (entry.key == LoanStatus.completed) {
          _loanStatusCount['Settled'] = entry.value.length;
        } else if ([
          LoanStatus.approved,
          LoanStatus.paid_on_time,
          LoanStatus.paid_late,
          LoanStatus.payment_submitted,
          LoanStatus.not_paid,
        ].contains(entry.key)) {
          var value = _loanStatusCount['Active'] ?? 0;
          _loanStatusCount['Active'] = value += entry.value.length;

          if (entry.key == LoanStatus.approved) {
            _loanStatusCount['Approved'] = entry.value.length;
          }
        }
      }

      // do checking here
      log.finest(
          'loan counts per status updated: active ${_loanStatusCount['Active']}',);
      return _loanStatusCount;
    });
  }

  Future<double> _computeReceivables(List<Loan> loans) {
    return Future.microtask(() {
      var totalAmount = 0.0;

      for (final loan in loans) {
        if ([
          LoanStatus.pending,
          LoanStatus.declined,
          LoanStatus.completed,
          LoanStatus.bad_debt,
        ].contains(loan.status)) {
          // do not include computation of these statuses.
          continue;
        }

        final amt = loan.amount +
            loan.additionalCharges -
            (loan.deductions + loan.additionalChargeUpfrontCollection);

        if (loan.dueAt == null) {
          // open term
          totalAmount += amt;
        } else {
          final monthly = amt.calculateMonthlyPayment(
            monthlyInterestRate: loan.interestRate / 100,
            monthsToPay: loan.period,
            term: loan.term,
          );
          totalAmount += monthly * loan.period;
        }
      }

      return totalAmount;
    });
  }

  void _initializeStatusCounts() {
    _loanStatusCount.clear();
    _loanStatusCount['New'] = 0;
    _loanStatusCount['Approved'] = 0;
    _loanStatusCount['Overdue'] = 0;
    _loanStatusCount['Declined'] = 0;
    _loanStatusCount['Settled'] = 0;
    _loanStatusCount['Active'] = 0;
  }

  void _listenReportSummary() {
    if (!authService.user.isCustomer()) {
      final company = authService.company;
      // log.info('Listening report summary for company: ${company.id}');
      reportsRepository.init(companyId: company.id);
    }
  }

  Stream<ReportSummary> reportSummaryStream() {
    _listenReportSummary();

    return reportsRepository.stream.where((summary) => summary != null).map(
      (summary) {
        if (summary != null) {
          _capitalDataItems = summary.data?.values
              .where((value) => value.dataType == ItemType.add_capital)
              .toList() ?? [];
          _capitalUsage = summary.capitalUsage;
          _products = summary.products;
          _sales = summary.sales;

          if (summary.totalSummary != null) {
            _totalSummary
              ..clear()
              ..addAll(summary.totalSummary!);
          }

          // log.finest('report summary refresh');
        }

        return summary!;
      },
    );
  }

  /// returns the last x amount of TotalSummaryItem based
  /// from the current date.
  ({Map<String, TotalSummaryItem> items, Map<String, int> dates})
      getLastTotalSummaryItems({
    MomSalesInterval interval = MomSalesInterval.monthly,
    int count = 4,
  }) {
    if (_totalSummary.isEmpty) {
      return (items: {}, dates: {});
    }

    final map = <String, TotalSummaryItem>{};
    final dateMap = <String, int>{};
    var now = Jiffy.now();

    for (var i = 1; i <= count; i++) {
      final key = switch (interval) {
        MomSalesInterval.yearly => 'year:${now.year}',
        MomSalesInterval.monthly => 'year:${now.year}:month:${now.month}',
        MomSalesInterval.weekly =>
          'year:${now.year}:month:${now.month}:week:${now.weekOfYear}',
        MomSalesInterval.daily =>
          'year:${now.year}:month:${now.month}:week:${now.weekOfYear}:day:${now.date}'
      };

      dateMap[key] = now.millisecondsSinceEpoch;
      // update now date before doing anything
      now = switch (interval) {
        MomSalesInterval.yearly => now.subtract(years: 1),
        MomSalesInterval.monthly => now.subtract(months: 1),
        MomSalesInterval.weekly => now.subtract(weeks: 1),
        MomSalesInterval.daily => now.subtract(days: 1)
      };

      final item = _totalSummary[key];

      if (item == null) {
        continue;
      }

      map[key] = item;
    }

    return (
      items: map,
      dates: dateMap,
    );
  }

  ({
    Map<String, TotalSummaryItem> items,
    Map<String, int> dates,
    double largest
  }) getLastTotalSummaryItemsWithLargestCollection({
    MomSalesInterval interval = MomSalesInterval.monthly,
    int count = 4,
  }) {
    final (:items, :dates) = getLastTotalSummaryItems();
    var largest = 0.0;

    for (final MapEntry(:value) in items.entries) {
      largest = max(largest, value.totalCollections);
    }

    return (
      items: items,
      dates: dates,
      largest: largest,
    );
  }

  String getMomYearRangeTitle({
    MomSalesInterval interval = MomSalesInterval.monthly,
    int count = 4,
  }) {
    final now = Jiffy.now();
    final other = switch (interval) {
      MomSalesInterval.yearly => now.subtract(years: count),
      MomSalesInterval.monthly => now.subtract(months: count),
      MomSalesInterval.weekly => now.subtract(weeks: count),
      MomSalesInterval.daily => now.subtract(days: count)
    };

    if (now.year == other.year) {
      return 'Year ${now.year}';
    }

    return 'Year ${other.year} - ${now.year}';
  }
}
