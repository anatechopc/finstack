import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/bank_details/bloc/bank_details_bloc.dart';
import 'package:loooans/features/bank_details/widget/payout_accounts_section.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockBankDetailsBloc
    extends MockBloc<BankDetailsEvent, BankDetailsState>
    implements BankDetailsBloc {}

BankDetails _account({
  required String id,
  required String bankName,
  required String accountName,
  required String accountNumber,
}) =>
    BankDetails()
      ..id = id
      ..dataId = 'company-1'
      ..dataType = DataType.provider
      ..bankName = bankName
      ..accountName = accountName
      ..accountNumber = accountNumber;

void main() {
  late BankDetailsBloc bloc;

  setUpAll(() {
    registerFallbackValue(LoadBankDetailsEvent());
  });

  setUp(() {
    bloc = _MockBankDetailsBloc();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpApp(
      Scaffold(
        body: PayoutAccountsSection(createBloc: (_) => bloc),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders each account row and the Add control when loaded',
      (tester) async {
    when(() => bloc.state).thenReturn(
      BankDetailsState(
        status: BankDetailsStatus.loaded,
        accounts: [
          _account(
            id: 'bd-1',
            bankName: 'Acme Bank',
            accountName: 'Acme Lending',
            accountNumber: '0001112223',
          ),
          _account(
            id: 'bd-2',
            bankName: 'Globex Bank',
            accountName: 'Globex Capital',
            accountNumber: '9998887776',
          ),
        ],
      ),
    );

    await pumpSection(tester);

    expect(find.text('Payout accounts'), findsOneWidget);
    expect(
      find.text('Acme Bank · Acme Lending · 0001112223'),
      findsOneWidget,
    );
    expect(
      find.text('Globex Bank · Globex Capital · 9998887776'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.edit), findsNWidgets(2));
    expect(find.byIcon(Icons.delete), findsNWidgets(2));
    expect(find.text('+ Add account'), findsOneWidget);
  });

  testWidgets('shows empty-state message when there are no accounts',
      (tester) async {
    when(() => bloc.state).thenReturn(
      const BankDetailsState(status: BankDetailsStatus.loaded),
    );

    await pumpSection(tester);

    expect(
      find.textContaining('No payout accounts yet'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping Add, filling the form and saving dispatches '
    'AddBankDetailsEvent',
    (tester) async {
      when(() => bloc.state).thenReturn(
        const BankDetailsState(status: BankDetailsStatus.loaded),
      );

      await pumpSection(tester);

      await tester.tap(find.text('+ Add account'));
      await tester.pumpAndSettle();

      expect(find.text('Add payout account'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Bank name'),
        'New Bank',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account name'),
        'New Holder',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account number'),
        '1234509876',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final captured = verify(() => bloc.add(captureAny())).captured;
      final addEvents =
          captured.whereType<AddBankDetailsEvent>().toList();
      expect(addEvents, hasLength(1));
      expect(addEvents.single.bankName, 'New Bank');
      expect(addEvents.single.accountName, 'New Holder');
      expect(addEvents.single.accountNumber, '1234509876');
    },
  );
}
