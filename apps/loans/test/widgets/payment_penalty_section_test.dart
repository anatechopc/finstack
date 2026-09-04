import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans_helpers/data_helpers.dart';

import '../helpers/helpers.dart';

void main() {
  const daily100 = Penalty(
    id: 'p1',
    name: 'Late fee',
    amount: 100,
    frequency: PenaltyFrequency.daily,
  );

  LoanSchedule row(DateTime dueAt) => LoanSchedule()
    ..id = 's1'
    ..loanId = 'l1'
    ..status = LoanStatus.not_paid
    ..dueAt = dueAt
    ..amortization = 5000
    ..outstandingBalance = 5000
    ..isOpenTerm = false;

  Loan loan({bool allowLate = false}) => Loan()
    ..id = 'l1'
    ..term = '1m'
    ..penalties = [daily100]
    ..allowLatePayments = allowLate;

  late GlobalKey<FormBuilderState> key;

  setUp(() => key = GlobalKey<FormBuilderState>());

  Widget host({required List<LoanSchedule> schedules, required Loan loan}) {
    return Scaffold(
      body: SingleChildScrollView(
        child: FormBuilder(
          key: key,
          child: PaymentPenaltySection(
            schedules: schedules,
            loan: loan,
            initialCollectedAt: DateTime(2026, 9, 3),
          ),
        ),
      ),
    );
  }

  testWidgets('late row shows the penalty line, total, and waive control',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 8, 31))], loan: loan()),
    );

    expect(find.textContaining('Late fee'), findsOneWidget);
    expect(find.textContaining('× 3'), findsOneWidget);
    expect(find.text('Waive penalties'), findsOneWidget);
    expect(find.text('Waive reason'), findsNothing);
  });

  testWidgets('on-time row shows no penalty and no waive control',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 9, 3))], loan: loan()),
    );

    expect(find.textContaining('Late fee'), findsNothing);
    expect(find.text('Waive penalties'), findsNothing);
  });

  testWidgets('allow-late loan explains why nothing is charged',
      (tester) async {
    await tester.pumpApp(
      host(
        schedules: [row(DateTime(2026, 8, 31))],
        loan: loan(allowLate: true),
      ),
    );

    expect(find.textContaining('late payments allowed'), findsOneWidget);
    expect(find.text('Waive penalties'), findsNothing);
  });

  testWidgets('ticking waive reveals the reason field and saves the values',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 8, 31))], loan: loan()),
    );

    await tester.tap(find.text('Waive penalties'));
    await tester.pumpAndSettle();
    expect(find.text('Waive reason'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('waive_reason_field')),
      'goodwill',
    );
    key.currentState!.save();
    expect(key.currentState!.value['waive_penalty'], true);
    expect(key.currentState!.value['waive_reason'], 'goodwill');
    expect(key.currentState!.value['collected_at'], DateTime(2026, 9, 3));
  });

  testWidgets('many rows sum their penalties', (tester) async {
    await tester.pumpApp(
      host(
        schedules: [row(DateTime(2026, 8, 31)), row(DateTime(2026, 9, 2))],
        loan: loan(),
      ),
    );

    // 3 days × ₱100 + 1 day × ₱100 on top of 2 × ₱5,000.
    expect(find.textContaining('10,400.00'), findsOneWidget);
  });

  testWidgets('moving the date to on-time clears a ticked waive',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 8, 31))], loan: loan()),
    );

    await tester.tap(find.text('Waive penalties'));
    await tester.pumpAndSettle();

    key.currentState!.fields['collected_at']!.didChange(
      DateTime(2026, 8, 31),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waive penalties'), findsNothing);

    key.currentState!.fields['collected_at']!.didChange(
      DateTime(2026, 9, 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waive penalties'), findsOneWidget);
    expect(
      tester
          .widget<FormBuilderCheckbox>(find.byType(FormBuilderCheckbox))
          .initialValue,
      false,
    );

    key.currentState!.save();
    expect(key.currentState!.value['waive_penalty'], false);
    // 3 days × ₱100 on top of ₱5,000, not waived.
    expect(find.textContaining('5,300.00'), findsOneWidget);
  });
}
