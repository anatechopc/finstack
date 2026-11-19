import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/widget/add_product/penalties_section.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/loan_calculation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/pdf_generator.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans/widgets/penalty_dialog.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../helpers/helpers.dart';

// The penalty "Based on" option (owner, 2026-11-19) at widget and bloc
// level. Numbers derived by hand before the code:
//
// Payment dialog and borrower amounts, open-term 10,000 at 5% ('1m', 500 a
// cycle), created Jul 2, the Aug 1 cycle paid; seen and collected Oct 5:
// the Aug 31 and Sep 30 bills are missed (35 and 5 days late), Oct 30 is
// current. Penalties "Late fee" 100 once (flat: per missed bill, owner
// 2026-11-19) + "Bill surcharge" 1% of the missed bill per day (5 a
// day on a 500 bill, per bill):
//   Aug 31 bill: 100 + 5 x 35 = 275; Sep 30 bill: 100 + 5 x 5 = 125 -> 400
//   (300 before the flat fee counted per bill).
//   Dialog: 2 installments 1,000 + 400 = 1,400.
//   Borrower: Pay now 1,000 + 400 = 1,400; Pay in full + Oct 30's 500 =
//   1,900. (With "1% of the balance" it would be 100 x 35 = 3,500 once +
//   100 + 100, as in open_term_late_payments_test.dart.)

class _MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

class _MockLoansBloc extends MockBloc<LoansEvent, LoansState>
    implements LoansBloc {}

const onceOfBill = Penalty(
  id: 'once-bill',
  name: 'Late fee',
  amount: 10,
  isPercentage: true,
  basedOn: PenaltyBase.missedBill,
);
const dailyOfBalance = Penalty(
  id: 'daily-balance',
  name: 'Daily surcharge',
  amount: 0.1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
  basedOn: PenaltyBase.outstandingBalance,
);
const legacyDaily = Penalty(
  id: 'legacy',
  name: 'Old surcharge',
  amount: 1,
  isPercentage: true,
  frequency: PenaltyFrequency.daily,
);
const flatOnce = Penalty(id: 'flat', name: 'Fee', amount: 100);

void main() {
  group('penalty dialog: "Based on"', () {
    Penalty? saved;

    Future<void> open(WidgetTester tester) async {
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showPenaltyDialog(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(
      WidgetTester tester, {
      required String amount,
      PenaltyFrequency? frequency,
    }) async {
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), amount);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fee');
      await tester.pump();
      if (frequency != null) {
        await tester.tap(find.text(PenaltyFrequency.once.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(frequency.label).last);
        await tester.pumpAndSettle();
      }
    }

    Future<void> add(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    setUp(() => saved = null);

    testWidgets('a percentage shows the choice, starting on the missed bill',
        (tester) async {
      await open(tester);
      expect(find.text('Based on'), findsNothing, reason: 'nothing typed');

      await fill(tester, amount: '10%');
      expect(find.text('Based on'), findsOneWidget);
      expect(find.text('The missed bill'), findsOneWidget);
      expect(find.text('The outstanding balance'), findsOneWidget);

      await add(tester);
      expect(saved!.isPercentage, isTrue);
      expect(saved!.frequency, PenaltyFrequency.once);
      expect(saved!.basedOn, PenaltyBase.missedBill);
      expect(saved!.toJson()['based_on'], 'missed_bill');
    });

    testWidgets('picking "Per day" selects the outstanding balance',
        (tester) async {
      await open(tester);
      await fill(tester, amount: '0.1%', frequency: PenaltyFrequency.daily);
      await add(tester);

      expect(saved!.frequency, PenaltyFrequency.daily);
      expect(saved!.basedOn, PenaltyBase.outstandingBalance);
    });

    testWidgets('after "Per day" the lender can pick the missed bill',
        (tester) async {
      await open(tester);
      await fill(tester, amount: '1%', frequency: PenaltyFrequency.daily);
      await tester.tap(find.text('The missed bill'));
      await tester.pumpAndSettle();
      await add(tester);

      expect(saved!.frequency, PenaltyFrequency.daily);
      expect(saved!.basedOn, PenaltyBase.missedBill);
    });

    Future<void> pickFrequency(
      WidgetTester tester,
      PenaltyFrequency from,
      PenaltyFrequency to,
    ) async {
      await tester.tap(find.text(from.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(to.label).last);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a base the lender picked survives "Per day" again: Per day, missed '
        'bill, Monthly, Per day', (tester) async {
      await open(tester);
      await fill(tester, amount: '1%', frequency: PenaltyFrequency.daily);
      await tester.tap(find.text('The missed bill'));
      await tester.pumpAndSettle();
      await pickFrequency(
        tester,
        PenaltyFrequency.daily,
        PenaltyFrequency.monthly,
      );
      await pickFrequency(
        tester,
        PenaltyFrequency.monthly,
        PenaltyFrequency.daily,
      );
      await add(tester);

      expect(saved!.frequency, PenaltyFrequency.daily);
      expect(saved!.basedOn, PenaltyBase.missedBill);
    });

    testWidgets('untouched, Monthly then Per day still selects the balance',
        (tester) async {
      await open(tester);
      await fill(tester, amount: '1%', frequency: PenaltyFrequency.monthly);
      await pickFrequency(
        tester,
        PenaltyFrequency.monthly,
        PenaltyFrequency.daily,
      );
      await add(tester);

      expect(saved!.basedOn, PenaltyBase.outstandingBalance);
    });

    testWidgets('a flat amount hides the choice and saves no base',
        (tester) async {
      await open(tester);
      await fill(tester, amount: '100', frequency: PenaltyFrequency.daily);
      expect(find.text('Based on'), findsNothing);
      expect(find.text('The missed bill'), findsNothing);

      await add(tester);
      expect(saved!.isPercentage, isFalse);
      expect(saved!.basedOn, isNull);
      expect(saved!.toJson().containsKey('based_on'), isFalse);
    });
  });

  group('quotation and PDF penalty lines', () {
    final penalties = [onceOfBill, dailyOfBalance, legacyDaily, flatOnce];

    Loan loanWith({required int period, bool allowLate = false}) => Loan.create(
          userId: 'u1',
          companyId: 'co-1',
          productId: 'pr-1',
          amount: 10000,
          additionalCharges: 0,
          deductions: 0,
          period: period,
          requirements: const [],
          isForceCollect: false,
          status: LoanStatus.approved,
          dueAt: null,
          reason: 'quotation',
          interestRate: 5,
          term: '1m',
          amortization: 500,
          penalties: penalties,
          allowLatePayments: allowLate,
        );

    test('PDF: each base in words; a saved penalty shows its loan type', () {
      for (final (period, legacyBase) in [
        (3, 'of the missed bill'),
        (0, 'of the balance'),
      ]) {
        final lines = pdfPenaltyLines(loanWith(period: period));
        expect(
          lines.map((l) => l.title),
          [
            'Penalty if paid late: Late fee',
            'Penalty if paid late: Daily surcharge',
            'Penalty if paid late: Old surcharge',
            'Penalty if paid late: Fee',
          ],
        );
        expect(
          lines.map((l) => l.detail),
          [
            '10% of the missed bill, once',
            '0.1% of the balance, per day',
            '1% $legacyBase, per day',
            '${100.0.toCurrency()}, once',
          ],
          reason: 'period $period',
        );
      }
      expect(
        pdfPenaltyLines(loanWith(period: 3, allowLate: true))
            .map((l) => '${l.title}: ${l.detail}'),
        ['Late payments: Allowed, no penalties'],
      );
    });

    late _MockProductBloc products;
    late _MockLoansBloc loans;

    setUp(() {
      products = _MockProductBloc();
      loans = _MockLoansBloc();
      when(() => products.state).thenReturn(const ProductState());
      when(() => products.charges).thenReturn([]);
      when(() => products.deductions).thenReturn([]);
      when(() => products.penalties).thenReturn([]);
      when(() => products.selectedProduct).thenReturn(null);
      when(() => loans.state).thenReturn(const LoansState());
      when(() => loans.totalLoanPayment).thenReturn(0);
      when(() => loans.totalLoanAmountReceivable).thenReturn(0);
      when(() => loans.monthlyAmortization).thenReturn(0);
    });

    Future<void> pumpQuotation(WidgetTester tester, Loan loan) {
      return tester.pumpApp(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProductBloc>.value(value: products),
            BlocProvider<LoansBloc>.value(value: loans),
          ],
          child: Scaffold(
            body: SingleChildScrollView(
              child: QuotationWidget(
                loanAmount: loan.amount,
                period: loan.period,
                interestRate: loan.interestRate,
                penalties: loan.penalties,
                allowLatePayments: loan.allowLatePayments,
                isOpenTerm: loan.period == 0,
              ),
            ),
          ),
        ),
      );
    }

    for (final (period, legacyBase) in [
      (3, 'of the missed bill'),
      (0, 'of the balance'),
    ]) {
      testWidgets('quotation on a loan with period $period', (tester) async {
        await pumpQuotation(tester, loanWith(period: period));

        expect(find.text('10% of the missed bill, once'), findsOneWidget);
        expect(find.text('0.1% of the balance, per day'), findsOneWidget);
        expect(find.text('1% $legacyBase, per day'), findsOneWidget);
        expect(find.text('${100.0.toCurrency()}, once'), findsOneWidget);
        expect(
          find.text('Penalty if paid late: Old surcharge'),
          findsOneWidget,
        );
      });
    }
  });

  group('labels say the base in words', () {
    test('explicit bases, flat amounts, and the loan type default', () {
      expect(onceOfBill.amountLabel(), '10% of the missed bill, once');
      expect(dailyOfBalance.amountLabel(), '0.1% of the balance, per day');
      expect(flatOnce.amountLabel(), '${100.0.toCurrency()}, once');
      expect(
        legacyDaily.amountLabel(isOpenTerm: false),
        '1% of the missed bill, per day',
      );
      expect(
        legacyDaily.amountLabel(isOpenTerm: true),
        '1% of the balance, per day',
      );
      expect(
        legacyDaily.amountLabel(),
        '1% of the missed bill (fixed term) or the balance (open term), '
        'per day',
      );
      expect(
        dailyOfBalance.chipLabel(isOpenTerm: false),
        'Daily surcharge · 0.1% of the balance, per day',
      );
    });
  });

  // The real ProductBloc builds Firestore-backed repositories (final
  // classes, no fake), so the bloc is mocked here the way it fills its
  // list: `initializeAddProduct` adds the company defaults and the save
  // hands `List<Penalty>.of(...)` to `Product.create`; each Penalty, its
  // "Based on" included, is kept as it is. The section and the stored
  // shape (`Penalty.listToJson`, used by the company, product, loan and row
  // documents) are the production code.
  group("the wizard's penalties, copied from company defaults", () {
    final defaults = [onceOfBill, dailyOfBalance, legacyDaily, flatOnce];
    late _MockProductBloc bloc;

    setUp(() {
      AuthenticationService.instance
        ..user = (User()
          ..id = 'admin-1'
          ..firstName = 'Ana'
          ..lastName = 'Reyes'
          ..profilePhotoUrl = null
          ..userRole = UserRole.admin)
        ..company = (Company()
          ..id = 'co-1'
          ..name = 'Acme Lending'
          ..defaultPenalties = defaults);
      bloc = _MockProductBloc();
      when(() => bloc.state).thenReturn(const ProductState());
      when(() => bloc.penalties).thenReturn(List<Penalty>.of(defaults));
    });

    Future<void> pumpSection(WidgetTester tester, {required int maxPeriod}) {
      when(() => bloc.tempProductView).thenReturn(
        ProductView.create(
          companyId: 'co-1',
          companyName: 'Acme Lending',
          productId: NO_ID,
          loanType: 'Personal loan',
          term: '1m',
          interestRate: 5,
          maxLoanableAmount: 10000,
          reviewRatingAvg: 0,
          reviewCount: 0,
          maxPeriod: maxPeriod,
          allowAddOns: true,
        ),
      );
      return tester.pumpApp(
        BlocProvider<ProductBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: SingleChildScrollView(
              child: FormBuilder(child: PenaltiesSection()),
            ),
          ),
        ),
      );
    }

    testWidgets('a fixed-term product: each default in words', (tester) async {
      await pumpSection(tester, maxPeriod: 3);

      expect(
        find.text('Default · Late fee · 10% of the missed bill, once'),
        findsOneWidget,
      );
      expect(
        find.text('Default · Daily surcharge · 0.1% of the balance, per day'),
        findsOneWidget,
      );
      expect(
        find.text('Default · Old surcharge · 1% of the missed bill, per day'),
        findsOneWidget,
        reason: 'saved without "Based on": the fixed-term default',
      );
      expect(
        find.text('Default · Fee · ${100.0.toCurrency()}, once'),
        findsOneWidget,
      );

      await tester.tap(find.text('Reset to company defaults'));
      verify(() => bloc.resetPenalties()).called(1);
    });

    testWidgets(
        'an open-term product (max period 0): only the default base '
        'changes', (tester) async {
      await pumpSection(tester, maxPeriod: 0);

      expect(
        find.text('Default · Old surcharge · 1% of the balance, per day'),
        findsOneWidget,
      );
      expect(
        find.text('Default · Late fee · 10% of the missed bill, once'),
        findsOneWidget,
      );
      expect(
        find.text('Default · Daily surcharge · 0.1% of the balance, per day'),
        findsOneWidget,
      );
    });

    test(
        'company -> product -> loan keeps "Based on"; old ones stay without '
        'it', () {
      final companyJson = Penalty.listToJson(defaults);
      expect(
        companyJson.map((p) => p['based_on']),
        ['missed_bill', 'outstanding_balance', null, null],
      );
      expect(
        companyJson.map((p) => p.containsKey('based_on')),
        [true, true, false, false],
        reason: 'penalties without the choice keep their stored shape',
      );

      final product = Product.create(
        providerId: 'co-1',
        loanType: 'Personal loan',
        term: '1m',
        interestRate: 5,
        maxLoanableAmount: 10000,
        maxPeriod: 3,
        penalties: List<Penalty>.of(companyJson.map(Penalty.fromJson)),
      );
      final loan = Loan.create(
        userId: 'u1',
        companyId: 'co-1',
        productId: 'pr-1',
        amount: 10000,
        additionalCharges: 0,
        deductions: 0,
        period: 3,
        requirements: const [],
        isForceCollect: false,
        status: LoanStatus.approved,
        dueAt: null,
        reason: 'copy',
        interestRate: 5,
        term: '1m',
        amortization: 3672.09,
        penalties: List<Penalty>.of(product.penalties),
      );

      expect(loan.penalties, defaults);
      expect(
        Penalty.listToJson(loan.penalties).map(Penalty.fromJson),
        defaults,
      );
    });
  });

  group('two missed open-term bills, a penalty on the missed bill', () {
    final oct5 = DateTime(2026, 10, 5, 12);

    const lateFee100 = Penalty(id: 'late-fee', name: 'Late fee', amount: 100);
    const billDaily1 = Penalty(
      id: 'bill-daily',
      name: 'Bill surcharge',
      amount: 1,
      isPercentage: true,
      frequency: PenaltyFrequency.daily,
      basedOn: PenaltyBase.missedBill,
    );

    final loan = Loan.create(
      userId: 'u1',
      companyId: 'co-1',
      productId: 'pr-1',
      amount: 10000,
      additionalCharges: 0,
      deductions: 0,
      period: 0,
      requirements: const [],
      isForceCollect: false,
      status: LoanStatus.approved,
      dueAt: null,
      reason: 'open term',
      interestRate: 5,
      term: '1m',
      amortization: 500,
      penalties: const [lateFee100, billDaily1],
    )
      ..id = 'loan-1'
      ..createdAt = DateTime(2026, 7, 2)
      ..additionalLoanAmounts = [];

    final paidAug1 = LoanSchedule()
      ..id = 'sched-1'
      ..loanId = 'loan-1'
      ..companyId = 'co-1'
      ..createdAt = DateTime(2026, 8)
      ..updatedAt = DateTime(2026, 8)
      ..dueAt = DateTime(2026, 8)
      ..paidAt = DateTime(2026, 8)
      ..status = LoanStatus.paid_on_time
      ..isOpenTerm = true
      ..outstandingBalance = 10000
      ..principalPayment = 0
      ..interestPayment = 0
      ..interestCharge = 0
      ..amortization = 0
      ..extraPayment = 0
      ..advanceInterestPayments = 0
      ..interestDayMultiplier = 1;

    List<LoanSchedule> clientRows() => LoanCalculationService.calculateOpenTerm(
          amount: 10000,
          date: loan.createdAt,
          interestRate: 5,
          term: '1m',
          companyId: 'co-1',
          paidSchedules: [paidAug1],
          loan: loan,
          now: oct5,
        ).schedules;

    testWidgets('payment dialog: each bill its own days, 1,000 + 400',
        (tester) async {
      final rows = LoanCalculationService.calculateOpenTermSchedules(
        amount: 10000,
        date: DateTime(2026, 7, 2),
        interestRate: 5,
        term: '1m',
        companyId: 'co-1',
        paidSchedules: [paidAug1],
        now: oct5,
      ).schedules;
      expect(
        rows.map((r) => DateUtils.dateOnly(r.dueAt)).take(2),
        [DateTime(2026, 8, 31), DateTime(2026, 9, 30)],
      );

      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: FormBuilder(
              child: PaymentPenaltySection(
                schedules: rows.sublist(0, 2),
                loan: loan,
                initialCollectedAt: DateTime(2026, 10, 5),
                loanRows: [paidAug1, ...rows],
              ),
            ),
          ),
        ),
      );

      expect(find.text('2 installments'), findsOneWidget);
      expect(find.text(1000.toCurrency()), findsOneWidget);
      expect(
        find.text('Late fee · ${100.0.toCurrency()}, once × 1'),
        findsNWidgets(2),
      );
      expect(
        find.text('Bill surcharge · 1% of the missed bill, per day × 35'),
        findsOneWidget,
      );
      expect(
        find.text('Bill surcharge · 1% of the missed bill, per day × 5'),
        findsOneWidget,
      );
      expect(find.text(175.toCurrency()), findsOneWidget);
      expect(find.text(25.toCurrency()), findsOneWidget);
      expect(find.text(1400.toCurrency()), findsOneWidget);
    });

    test('borrower: Pay now 1,000 + 400 = 1,400, Pay in full 1,900', () {
      final due = borrowerAmountsDue(
        schedules: clientRows(),
        loan: loan,
        asOf: oct5,
      );

      expect(
        due.payNow.map((s) => DateUtils.dateOnly(s.dueAt)),
        [DateTime(2026, 8, 31), DateTime(2026, 9, 30)],
      );
      expect(due.nextDuePenalty, closeTo(400, 0.005));
      expect(due.nextDueAmount, closeTo(1400, 0.005));
      expect(due.remainingPenalty, closeTo(400, 0.005));
      expect(due.remainingTotal, closeTo(1900, 0.005));
    });
  });
}
