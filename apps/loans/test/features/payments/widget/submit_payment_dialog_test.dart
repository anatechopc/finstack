import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payments/bloc/payment_submission_bloc.dart';
import 'package:loooans/features/payments/widget/submit_payment_dialog.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockSubmissionBloc
    extends MockBloc<PaymentSubmissionEvent, PaymentSubmissionState>
    implements PaymentSubmissionBloc {}

class _MockBankRepo extends Mock implements BaseRepository<BankDetails> {}

LoanSchedule _schedule(String id) => LoanSchedule()
  ..id = id
  ..loanId = 'loan-1'
  ..status = LoanStatus.not_paid
  ..dueAt = DateTime(2026, 6, 30)
  ..amortization = 1000;

BankDetails _companyBankDetails() => BankDetails()
  ..id = 'bd-1'
  ..dataId = 'company-1'
  ..dataType = DataType.provider
  ..bankName = 'Acme Bank'
  ..accountName = 'Acme Lending'
  ..accountNumber = '0001112223';

BankDetails _secondCompanyBankDetails() => BankDetails()
  ..id = 'bd-2'
  ..dataId = 'company-1'
  ..dataType = DataType.provider
  ..bankName = 'Beta Bank'
  ..accountName = 'Beta Lending'
  ..accountNumber = '0004445556';

void main() {
  late PaymentSubmissionBloc bloc;
  late BaseRepository<BankDetails> bankRepo;

  setUp(() {
    bloc = _MockSubmissionBloc();
    bankRepo = _MockBankRepo();
    when(() => bloc.state).thenReturn(const PaymentSubmissionState());
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<BankDetails> bankDetails,
  }) async {
    when(
      () => bankRepo.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => bankDetails);

    await tester.pumpApp(
      RepositoryProvider<BaseRepository<BankDetails>>.value(
        value: bankRepo,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showSubmitPaymentDialog(
                    context,
                    schedules: [_schedule('sched-1')],
                    loanId: 'loan-1',
                    companyId: 'company-1',
                    amount: 1000,
                    createBloc: (_) => bloc,
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton sendButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Send'),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets(
    'shows no-bank-details message and disables Send when lender has '
    'no bank details',
    (tester) async {
      await pumpDialog(tester, bankDetails: []);

      expect(
        find.textContaining("hasn't set up bank details"),
        findsOneWidget,
      );
      expect(sendButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'shows bank details when present; Send disabled until a file is chosen',
    (tester) async {
      await pumpDialog(tester, bankDetails: [_companyBankDetails()]);

      expect(find.textContaining('Acme Bank'), findsOneWidget);
      expect(find.textContaining('Acme Lending'), findsOneWidget);
      expect(find.textContaining('0001112223'), findsOneWidget);
      expect(find.text('Choose screenshot'), findsOneWidget);

      // No file chosen yet -> Send still disabled.
      expect(sendButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'shows a payout-account dropdown when the lender has more than one '
    'account; Send disabled until an account and file are chosen',
    (tester) async {
      await pumpDialog(
        tester,
        bankDetails: [_companyBankDetails(), _secondCompanyBankDetails()],
      );

      // More than one account -> borrower must choose where to pay.
      expect(find.text('Choose account to pay to'), findsOneWidget);
      expect(find.byType(DropdownButton<BankDetails>), findsOneWidget);

      // Nothing selected and no file chosen yet -> Send still disabled.
      expect(sendButton(tester).onPressed, isNull);
    },
  );
}
