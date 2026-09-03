import 'package:bloc_test/bloc_test.dart';
import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/cash_pool/model/cash_pool_display.dart';
import 'package:loooans/features/users/widget/cash_pool_information_widget.dart';
import 'package:mocktail/mocktail.dart';

class _MockCashPoolBloc extends MockBloc<CashPoolEvent, CashPoolState>
    implements CashPoolBloc {}

void main() {
  late _MockCashPoolBloc cashPool;

  setUp(() {
    cashPool = _MockCashPoolBloc();
    when(() => cashPool.state).thenReturn(const CashPoolState());
    when(() => cashPool.cashPoolDisplay).thenReturn(
      const CashPoolDisplay(
        totalCashPool: 1500,
        totalAcknowledged: 500,
        balance: 1000,
        change: 0,
        savings: 0,
      ),
    );
    when(() => cashPool.loadCashPoolList2(any())).thenAnswer(
      (_) => Stream.value([
        CashPool.create(userId: 'user-7', amount: 1500),
        CashPool.create(
          userId: 'user-7',
          amount: 500,
          status: CashPoolStatus.acknowledged_payment,
          paymentId: 'payment-1',
          loanId: 'loan-1',
        ),
      ]),
    );
  });

  void resize(WidgetTester tester, Size logical) {
    // `tester.view`, not `setSurfaceSize`: `MediaQuery.sizeOf`, which
    // `getScreenSize` reads, only follows the former.
    tester.view
      ..physicalSize = logical
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(WidgetTester tester, {required Widget host}) {
    return tester.pumpWidget(
      BlocProvider<CashPoolBloc>.value(
        value: cashPool,
        child: MaterialApp(home: Scaffold(body: host)),
      ),
    );
  }

  testWidgets(
      '390px: the two columns stack, the list sizes to its rows, '
      'nothing overflows', (tester) async {
    resize(tester, const Size(390, 844));

    // Inside a ListView, as `BorrowerDetailScreen`'s compact body has it:
    // no height on offer, which is what an `Expanded` list cannot take.
    await pump(
      tester,
      host: ListView(children: [CashPoolInformationWidget(userId: 'user-7')]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final wallet = tester.getTopLeft(find.text('Wallet'));
    final transactions = tester.getTopLeft(find.text('Cash pool transactions'));
    expect(transactions.dx, wallet.dx);
    expect(transactions.dy, greaterThan(wallet.dy));
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('Add to pool'), findsOneWidget);
    expect(find.text('Acknowledged payment'), findsOneWidget);
  });

  testWidgets('wide: the two columns sit side by side, as before',
      (tester) async {
    resize(tester, const Size(1600, 900));

    await pump(
      tester,
      host: SizedBox(
        height: 480,
        child: CashPoolInformationWidget(userId: 'user-7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final wallet = tester.getTopLeft(find.text('Wallet'));
    final transactions = tester.getTopLeft(find.text('Cash pool transactions'));
    // Same band at the top ('Wallet' sits centred beside a taller button),
    // second column to the right.
    expect((transactions.dy - wallet.dy).abs(), lessThan(48));
    expect(transactions.dx, greaterThan(wallet.dx));
    expect(find.text('Acknowledged payment'), findsOneWidget);
  });
}
