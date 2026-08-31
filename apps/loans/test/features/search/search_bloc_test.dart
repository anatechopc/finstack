import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:user_repository/user_repository.dart';

class _MockSearchIndex extends Mock implements SearchIndex {}

class _MockAuthenticationService extends Mock
    implements AuthenticationService {}

class _FakeSearchRequest extends Fake implements SearchRequest {}

/// A real `User`, not a mock: only `user_role` is read, and the concrete
/// object keeps the fixture honest about the field the resolver branches on.
User _user({String id = 'user-1', UserRole userRole = UserRole.admin}) => User()
  ..id = id
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  ..userRole = userRole;

SearchResults _clients(String id) => SearchResults(
      items: [ClientResultItem(user: _user(id: id), matchedField: 'name')],
      scope: SearchScope.clients,
    );

String _singleClientId(SearchState state) =>
    (state.results.items.single as ClientResultItem).user.id;

void main() {
  late _MockSearchIndex index;
  late _MockAuthenticationService auth;

  /// Responses handed out in call order, so a test can decide which query
  /// resolves first independently of which was issued first.
  late List<Completer<SearchResults>> pending;

  setUpAll(() => registerFallbackValue(_FakeSearchRequest()));

  setUp(() {
    index = _MockSearchIndex();
    auth = _MockAuthenticationService();
    pending = [Completer<SearchResults>(), Completer<SearchResults>()];
    when(() => auth.user).thenReturn(_user());
  });

  void answerInCallOrder() {
    var call = 0;
    when(() => index.query(any())).thenAnswer((_) => pending[call++].future);
  }

  /// Never `AuthenticationService.instance`: `apps/loans/CLAUDE.md` forbids it
  /// in blocs, and a fresh test isolate's singleton throws `Please login` from
  /// `user`.
  SearchBloc buildBloc({UserRole role = UserRole.admin}) {
    when(() => auth.user).thenReturn(_user(userRole: role));

    return SearchBloc.withDependencies(searchIndex: index, authService: auth);
  }

  blocTest<SearchBloc, SearchState>(
    'a one-character query is reported as too short and never queries',
    build: buildBloc,
    act: (bloc) => bloc.add(const QueryChangedEvent('d', location: '/users')),
    expect: () => [
      isA<SearchState>()
          .having((s) => s.status, 'status', SearchStatus.tooShort)
          .having((s) => s.term, 'term', 'd'),
    ],
    verify: (_) => verifyNever(() => index.query(any())),
  );

  blocTest<SearchBloc, SearchState>(
    'a matched query emits loading then results',
    build: () {
      when(() => index.query(any())).thenAnswer((_) async => _clients('hit'));

      return buildBloc();
    },
    act: (bloc) =>
        bloc.add(const QueryChangedEvent('dela', location: '/users')),
    expect: () => [
      isA<SearchState>()
          .having((s) => s.status, 'status', SearchStatus.loading)
          .having((s) => s.scope, 'scope', SearchScope.clients)
          .having((s) => s.term, 'term', 'dela'),
      isA<SearchState>()
          .having((s) => s.status, 'status', SearchStatus.results)
          .having(_singleClientId, 'result id', 'hit'),
    ],
  );

  blocTest<SearchBloc, SearchState>(
    'a query with no matches lands in empty, not results',
    build: () {
      when(() => index.query(any()))
          .thenAnswer((_) async => SearchResults.empty);

      return buildBloc();
    },
    act: (bloc) =>
        bloc.add(const QueryChangedEvent('dela', location: '/users')),
    expect: () => [
      isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
      isA<SearchState>().having((s) => s.status, 'status', SearchStatus.empty),
    ],
  );

  blocTest<SearchBloc, SearchState>(
    'a failing index emits error and keeps the term',
    build: () {
      when(() => index.query(any())).thenThrow(Exception('firestore is down'));

      return buildBloc();
    },
    act: (bloc) =>
        bloc.add(const QueryChangedEvent('dela', location: '/users')),
    expect: () => [
      isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
      isA<SearchState>()
          .having((s) => s.status, 'status', SearchStatus.error)
          .having((s) => s.term, 'term', 'dela'),
    ],
  );

  // B6: `AuthenticationService.company` throws for BOTH of these roles, so a
  // bloc that reads it — as the plan's Task 4 did — puts the borrower's only
  // scope in a permanent, silent error state. The company is resolved inside
  // `FirestoreSearchIndex`; the bloc must never touch it.
  group('roles whose session has no company', () {
    for (final role in [UserRole.customer, UserRole.appAdmin]) {
      blocTest<SearchBloc, SearchState>(
        'a ${role.name} query reaches the index and never errors',
        build: () {
          when(() => index.query(any()))
              .thenAnswer((_) async => _clients('hit'));

          return buildBloc(role: role);
        },
        act: (bloc) =>
            bloc.add(const QueryChangedEvent('acme', location: '/users')),
        expect: () => [
          isA<SearchState>()
              .having((s) => s.status, 'status', SearchStatus.loading),
          isA<SearchState>()
              .having((s) => s.status, 'status', SearchStatus.results),
        ],
        verify: (_) {
          verify(() => index.query(any())).called(1);
          verifyNever(() => auth.company);
        },
      );
    }
  });

  // M6: the plan had `_onFiltersChanged` re-dispatch `QueryChangedEvent`.
  // `ParsedQuery.term` is prefix-STRIPPED, so re-resolving 'acme' at '/users'
  // would silently flip the scope from offers back to clients and carry
  // `OfferFilters` into a clients query. The scope and term on the state are
  // the ones to re-query with.
  blocTest<SearchBloc, SearchState>(
    'a filters change re-queries the pinned scope, not the re-resolved one',
    build: () {
      when(() => index.query(any())).thenAnswer((_) async => _clients('hit'));

      return buildBloc();
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('products: acme', location: '/users'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const FiltersChangedEvent(OfferFilters(term: '30d')));
      await Future<void>.delayed(Duration.zero);
    },
    verify: (bloc) {
      final requests =
          verify(() => index.query(captureAny())).captured.cast<SearchRequest>();

      expect(requests.length, 2);
      expect(requests.first.scope, SearchScope.offers);
      expect(requests.first.filters.term, isNull);
      expect(requests.last.scope, SearchScope.offers);
      expect(requests.last.term, 'acme');
      expect(requests.last.filters.term, '30d');
      expect(bloc.state.filters.term, '30d');
    },
  );

  // The guard this bloc exists for. Ordered by Completer, not by racing
  // durations: the SECOND query resolves first, then the first one lands.
  blocTest<SearchBloc, SearchState>(
    'a stale response landing after a newer one does not overwrite it',
    build: () {
      answerInCallOrder();

      return buildBloc();
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('de', location: '/users'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const QueryChangedEvent('dela cruz', location: '/users'));
      await Future<void>.delayed(Duration.zero);

      pending[1].complete(_clients('fresh'));
      await Future<void>.delayed(Duration.zero);
      pending[0].complete(_clients('stale'));
      await Future<void>.delayed(Duration.zero);
    },
    verify: (bloc) {
      expect(_singleClientId(bloc.state), 'fresh');
      expect(bloc.state.status, SearchStatus.results);
      expect(bloc.state.term, 'dela cruz');
    },
  );

  // Same guard, the erase direction: shortening the query below `minPrefix`
  // must also invalidate whatever is in flight, or the results for a query the
  // user has deleted land on top of the tooShort state.
  blocTest<SearchBloc, SearchState>(
    'a response landing after the query is erased is dropped',
    build: () {
      answerInCallOrder();

      return buildBloc();
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('dela', location: '/users'));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const QueryChangedEvent('d', location: '/users'));
      await Future<void>.delayed(Duration.zero);

      pending[0].complete(_clients('stale'));
      await Future<void>.delayed(Duration.zero);
    },
    verify: (bloc) {
      expect(bloc.state.status, SearchStatus.tooShort);
      expect(bloc.state.term, 'd');
    },
  );
}
