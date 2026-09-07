import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockLoanRepo extends Mock implements LoanRepository {}

class _MockLoanScheduleRepo extends Mock implements LoanScheduleRepository {}

class _MockPaymentRepo extends Mock implements PaymentRepository {}

class _MockStorageRepo extends Mock implements StorageRepository {}

class _MockViews extends Mock implements BaseRepository<UserLoanView> {}

class _MockAuthService extends Mock implements AuthenticationService {}

void main() {
  late _MockUserRepo users;
  late _MockViews views;
  late _MockAuthService auth;

  setUp(() {
    users = _MockUserRepo();
    views = _MockViews();
    auth = _MockAuthService();
    when(() => auth.company).thenReturn(Company()..id = 'c1');

    when(
      () => users.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer((_) async => <User>[]);

    when(
      () => views.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      ),
    ).thenAnswer(
      (_) async => [
        UserLoanView()
          ..userId = 'u-market'
          ..userFullName = 'Dugd, Asdf'
          ..companyId = 'c1',
      ],
    );

    when(() => users.get(id: 'u-market')).thenAnswer(
      (_) async => User()
        ..id = 'u-market'
        ..firstName = 'Asdf'
        ..lastName = 'Dugd',
    );
  });

  PaymentCenterBloc buildBloc() => PaymentCenterBloc.withDependencies(
        userRepository: users,
        loanRepository: _MockLoanRepo(),
        loanScheduleRepository: _MockLoanScheduleRepo(),
        paymentRepository: _MockPaymentRepo(),
        storageRepository: _MockStorageRepo(),
        userLoanViewRepository: views,
        authService: auth,
      );

  group('PaymentCenterBloc search', () {
    blocTest<PaymentCenterBloc, PaymentCenterState>(
      'finds a marketplace borrower (company_id null) via user_loan_views',
      build: buildBloc,
      act: (bloc) => bloc.add(const SearchBorrowersEvent(query: 'dugd')),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.searchResults);
        expect(bloc.state.searchResults.single.id, 'u-market');
      },
    );

    blocTest<PaymentCenterBloc, PaymentCenterState>(
      'returns no results for a query that matches nobody',
      build: buildBloc,
      act: (bloc) => bloc.add(const SearchBorrowersEvent(query: 'zzz')),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, PaymentCenterStatus.searchResults);
        expect(bloc.state.searchResults, isEmpty);
      },
    );

    test('findBorrowers finds a marketplace borrower directly', () async {
      final bloc = buildBloc();
      final result = await bloc.findBorrowers('dugd');
      expect(result.single.id, 'u-market');
    });

    test('findBorrowers returns nothing for a blank query', () async {
      final bloc = buildBloc();
      final result = await bloc.findBorrowers('   ');
      expect(result, isEmpty);
      verifyNever(
        () => users.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      );
    });
  });
}
