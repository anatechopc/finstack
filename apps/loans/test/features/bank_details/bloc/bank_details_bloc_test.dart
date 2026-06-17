import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/bank_details/bloc/bank_details_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';

class _MockBankDetailsRepo extends Mock
    implements BaseRepository<BankDetails> {}

class _MockAuth extends Mock implements AuthenticationService {}

class _MockCompany extends Mock implements Company {}

BankDetails _account({
  required DataType dataType,
  String dataId = 'co-1',
  String id = 'NO_ID',
  String bankName = 'BPI',
  String accountName = 'X',
  String accountNumber = '123',
}) =>
    BankDetails.create(
      dataId: dataId,
      dataType: dataType,
      bankName: bankName,
      accountName: accountName,
      accountNumber: accountNumber,
    )..id = id;

void main() {
  late BaseRepository<BankDetails> repo;
  late AuthenticationService auth;
  late Company company;

  setUpAll(() {
    registerFallbackValue(_account(dataType: DataType.provider));
  });

  setUp(() {
    repo = _MockBankDetailsRepo();
    auth = _MockAuth();
    company = _MockCompany();
    when(() => auth.company).thenReturn(company);
    when(() => company.id).thenReturn('co-1');
  });

  BankDetailsBloc build() => BankDetailsBloc.withDependencies(
        bankDetailsRepository: repo,
        authService: auth,
      );

  blocTest<BankDetailsBloc, BankDetailsState>(
    'LoadBankDetailsEvent emits loaded with only provider accounts',
    build: () {
      when(
        () => repo.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer(
        (_) async => [
          _account(dataType: DataType.provider, id: 'p-1'),
          _account(dataType: DataType.user, id: 'u-1'),
          _account(dataType: DataType.provider, id: 'p-2'),
        ],
      );
      return build();
    },
    act: (b) => b.add(LoadBankDetailsEvent()),
    expect: () => [
      isA<BankDetailsState>().having(
        (s) => s.status,
        'status',
        BankDetailsStatus.loading,
      ),
      isA<BankDetailsState>()
          .having((s) => s.status, 'status', BankDetailsStatus.loaded)
          .having((s) => s.accounts.length, 'accounts', 2)
          .having(
            (s) => s.accounts.every((a) => a.dataType == DataType.provider),
            'all provider',
            isTrue,
          ),
    ],
  );

  blocTest<BankDetailsBloc, BankDetailsState>(
    'AddBankDetailsEvent adds a provider account then reloads',
    build: () {
      when(() => repo.add(data: any(named: 'data')))
          .thenAnswer((i) async => i.namedArguments[#data] as BankDetails);
      when(
        () => repo.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer(
        (_) async => [_account(dataType: DataType.provider, id: 'p-1')],
      );
      return build();
    },
    act: (b) => b.add(
      AddBankDetailsEvent(
        bankName: 'BDO',
        accountName: 'Acme Corp',
        accountNumber: '9999',
      ),
    ),
    expect: () => [
      isA<BankDetailsState>().having(
        (s) => s.status,
        'status',
        BankDetailsStatus.saving,
      ),
      isA<BankDetailsState>().having(
        (s) => s.status,
        'status',
        BankDetailsStatus.loaded,
      ),
    ],
    verify: (_) {
      final added = verify(() => repo.add(data: captureAny(named: 'data')))
          .captured
          .single as BankDetails;
      expect(added.dataType, DataType.provider);
      expect(added.dataId, 'co-1');
      expect(added.bankName, 'BDO');
      expect(added.accountName, 'Acme Corp');
      expect(added.accountNumber, '9999');
      verify(
        () => repo.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).called(1);
    },
  );

  blocTest<BankDetailsBloc, BankDetailsState>(
    'DeleteBankDetailsEvent deletes the given account then reloads',
    build: () {
      when(() => repo.delete(data: any(named: 'data')))
          .thenAnswer((i) async => i.namedArguments[#data] as BankDetails);
      when(
        () => repo.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).thenAnswer((_) async => <BankDetails>[]);
      return build();
    },
    act: (b) => b.add(
      DeleteBankDetailsEvent(
        bankDetails: _account(dataType: DataType.provider, id: 'p-1'),
      ),
    ),
    expect: () => [
      isA<BankDetailsState>().having(
        (s) => s.status,
        'status',
        BankDetailsStatus.saving,
      ),
      isA<BankDetailsState>().having(
        (s) => s.status,
        'status',
        BankDetailsStatus.loaded,
      ),
    ],
    verify: (_) {
      final deleted =
          verify(() => repo.delete(data: captureAny(named: 'data')))
              .captured
              .single as BankDetails;
      expect(deleted.id, 'p-1');
      verify(
        () => repo.load(
          statements: any(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        ),
      ).called(1);
    },
  );
}
