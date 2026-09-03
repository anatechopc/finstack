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
    );

String _singleClientId(SearchState state) =>
    (state.results.items.single as ClientResultItem).user.id;

/// Lets every handler the previous `add` queued run to completion.
Future<void> _drain() => Future<void>.delayed(Duration.zero);

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

  void answerWithHit() {
    when(() => index.query(any())).thenAnswer((_) async => _clients('hit'));
  }

  List<SearchRequest> issued() =>
      verify(() => index.query(captureAny())).captured.cast<SearchRequest>();

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
      answerWithHit();

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
          answerWithHit();

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

  // The hint the field shows before the first query reads off `state.scope`,
  // so the initial state must already be the role's default: "Search
  // clients…" is a lie to a borrower, who has no clients scope at all.
  group('initial scope', () {
    test('is clients for staff', () {
      expect(buildBloc().state.scope, SearchScope.clients);
      expect(
        buildBloc(role: UserRole.appAdmin).state.scope,
        SearchScope.clients,
      );
    });

    test('is offers for a customer', () {
      expect(
        buildBloc(role: UserRole.customer).state.scope,
        SearchScope.offers,
      );
    });

    // The bloc is mounted above the login route and `SearchClearedEvent` is
    // dispatched on logout, so construction and clearing both happen with
    // nobody signed in.
    test('is offers when nobody is signed in', () {
      when(() => auth.user).thenThrow(Exception('Please login'));

      final bloc =
          SearchBloc.withDependencies(searchIndex: index, authService: auth);
      expect(bloc.state.scope, SearchScope.offers);
    });
  });

  // M6: the plan had `_onFiltersChanged` re-dispatch `QueryChangedEvent`.
  // `ParsedQuery.term` is prefix-STRIPPED, so re-resolving 'acme' at '/users'
  // would silently flip the scope from offers back to clients and carry
  // `OfferFilters` into a clients query. The scope and term on the state are
  // the ones to re-query with.
  blocTest<SearchBloc, SearchState>(
    'a filters change re-queries the pinned scope, not the re-resolved one',
    build: () {
      answerWithHit();

      return buildBloc();
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('products: acme', location: '/users'));
      await _drain();
      bloc.add(const FiltersChangedEvent(OfferFilters(term: '30d')));
      await _drain();
    },
    verify: (bloc) {
      final requests = issued();

      expect(requests.length, 2);
      expect(requests.first.scope, SearchScope.offers);
      expect(requests.first.filters.term, isNull);
      expect(requests.last.scope, SearchScope.offers);
      expect(requests.last.term, 'acme');
      expect(requests.last.filters.term, '30d');
      expect(bloc.state.filters.term, '30d');
    },
  );

  // The bloc lives for the whole app, so facets set on `/search` used to
  // narrow every later query — including the app-bar overlay, which has no
  // filter UI to show or clear them. A query event that carries filters is
  // the whole truth; one that carries none keeps what the state holds.
  group('filters on the query event', () {
    blocTest<SearchBloc, SearchState>(
      'replace the state filters, and an empty OfferFilters clears them',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(
          const QueryChangedEvent(
            'products: acme',
            location: '/search',
            filters: OfferFilters(companyId: 'lender-9', term: '30d'),
          ),
        );
        await _drain();
        bloc.add(
          const QueryChangedEvent(
            'products: salary',
            location: '/',
            filters: OfferFilters(),
          ),
        );
        await _drain();
      },
      verify: (bloc) {
        final requests = issued();

        expect(requests.first.filters.companyId, 'lender-9');
        expect(requests.first.filters.term, '30d');
        expect(requests.last.filters.isEmpty, isTrue);
        expect(bloc.state.filters.isEmpty, isTrue);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'left null keep the state filters',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const FiltersChangedEvent(OfferFilters(term: '30d')));
        await _drain();
        bloc.add(const QueryChangedEvent('products: acme', location: '/'));
        await _drain();
      },
      verify: (bloc) {
        expect(issued().last.filters.term, '30d');
        expect(bloc.state.filters.term, '30d');
      },
    );
  });

  group('candidateLimit on the query event', () {
    blocTest<SearchBloc, SearchState>(
      'is forwarded to the request, and defaults when absent',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(
          const QueryChangedEvent('dela', location: '/', candidateLimit: 10),
        );
        await _drain();
        bloc.add(const QueryChangedEvent('cruz', location: '/'));
        await _drain();
      },
      verify: (_) {
        final requests = issued();
        expect(requests.first.candidateLimit, 10);
        expect(
          requests.last.candidateLimit,
          SearchRequest.defaultCandidateLimit,
        );
      },
    );
  });

  // "See all" and back/forward re-dispatch exactly the query whose results
  // are already on the state. Firestore is billed per document read.
  group('an unchanged query', () {
    blocTest<SearchBloc, SearchState>(
      'is not re-run while its results are on the state',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
        bloc.add(const FiltersChangedEvent(OfferFilters()));
        await _drain();
      },
      verify: (bloc) {
        expect(issued(), hasLength(1));
        expect(bloc.state.status, SearchStatus.results);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'is re-run when it asks for a larger candidate page',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(
          const QueryChangedEvent('dela', location: '/', candidateLimit: 10),
        );
        await _drain();
        bloc.add(
          const QueryChangedEvent('dela', location: '/', candidateLimit: 10),
        );
        await _drain();
        bloc.add(const QueryChangedEvent('dela', location: '/'));
        await _drain();
        // Back to the small page: the larger results still cover it.
        bloc.add(
          const QueryChangedEvent('dela', location: '/', candidateLimit: 10),
        );
        await _drain();
      },
      verify: (_) {
        final limits = issued().map((r) => r.candidateLimit).toList();
        expect(limits, [10, SearchRequest.defaultCandidateLimit]);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'is re-run when its filters changed',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const QueryChangedEvent('products: acme', location: '/'));
        await _drain();
        bloc.add(
          const QueryChangedEvent(
            'products: acme',
            location: '/',
            filters: OfferFilters(term: '30d'),
          ),
        );
        await _drain();
      },
      verify: (_) => expect(issued(), hasLength(2)),
    );

    // Retry after an error is the same event again, and must run.
    blocTest<SearchBloc, SearchState>(
      'is re-run after an error',
      build: () {
        when(() => index.query(any())).thenThrow(Exception('down'));

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
      },
      verify: (_) => expect(issued(), hasLength(2)),
    );
  });

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
      await _drain();
      bloc.add(const QueryChangedEvent('dela cruz', location: '/users'));
      await _drain();

      pending[1].complete(_clients('fresh'));
      await _drain();
      pending[0].complete(_clients('stale'));
      await _drain();
    },
    verify: (bloc) {
      expect(_singleClientId(bloc.state), 'fresh');
      expect(bloc.state.status, SearchStatus.results);
      expect(bloc.state.term, 'dela cruz');
    },
  );

  // Erase means erase. Leaving the last results on the state makes every
  // surface re-implement the same "don't render these" guard — two places to
  // get it wrong for one rule.
  blocTest<SearchBloc, SearchState>(
    'shortening a query below the minimum clears the results it found',
    build: () {
      answerWithHit();

      return buildBloc();
    },
    act: (bloc) async {
      bloc.add(const QueryChangedEvent('dela', location: '/users'));
      await _drain();
      expect(bloc.state.results.items, isNotEmpty);

      bloc.add(const QueryChangedEvent('d', location: '/users'));
      await _drain();
    },
    verify: (bloc) {
      expect(bloc.state.status, SearchStatus.tooShort);
      expect(bloc.state.results.items, isEmpty);
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
      await _drain();
      bloc.add(const QueryChangedEvent('d', location: '/users'));
      await _drain();

      pending[0].complete(_clients('stale'));
      await _drain();
    },
    verify: (bloc) {
      expect(bloc.state.status, SearchStatus.tooShort);
      expect(bloc.state.term, 'd');
    },
  );

  // The bloc outlives the session. Without a reset, the next account to focus
  // the field sees the previous account's client rows — PII across a logout.
  group('SearchClearedEvent', () {
    blocTest<SearchBloc, SearchState>(
      'returns to the initial state and drops an in-flight response',
      build: () {
        answerInCallOrder();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
        bloc.add(const SearchClearedEvent());
        await _drain();

        pending[0].complete(_clients('stale'));
        await _drain();
      },
      verify: (bloc) {
        expect(bloc.state.status, SearchStatus.idle);
        expect(bloc.state.term, '');
        expect(bloc.state.results.items, isEmpty);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'erases the results and facets already on the state',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(
          const QueryChangedEvent(
            'products: acme',
            location: '/',
            filters: OfferFilters(term: '30d'),
          ),
        );
        await _drain();
        expect(bloc.state.results.items, isNotEmpty);
        expect(bloc.state.filters.term, '30d');
        bloc.add(const SearchClearedEvent());
        await _drain();
      },
      verify: (bloc) {
        // Equatable: status idle, term '', empty results, empty filters.
        expect(bloc.state, SearchState(scope: bloc.state.scope));
      },
    );

    // Logout then login as a borrower: the stale admin default would show
    // "Search clients…" to someone who cannot search clients.
    blocTest<SearchBloc, SearchState>(
      're-derives the default scope from whoever is signed in now',
      build: buildBloc,
      act: (bloc) async {
        expect(bloc.state.scope, SearchScope.clients);
        when(() => auth.user).thenReturn(_user(userRole: UserRole.customer));
        bloc.add(const SearchClearedEvent());
        await _drain();
      },
      verify: (bloc) => expect(bloc.state.scope, SearchScope.offers),
    );

    // The same query after a clear must hit the index again: the clear
    // erased the results the dedup would otherwise stand on.
    blocTest<SearchBloc, SearchState>(
      'lets the same query run again afterwards',
      build: () {
        answerWithHit();

        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
        bloc.add(const SearchClearedEvent());
        await _drain();
        bloc.add(const QueryChangedEvent('dela', location: '/users'));
        await _drain();
      },
      verify: (bloc) {
        expect(issued(), hasLength(2));
        expect(bloc.state.status, SearchStatus.results);
      },
    );
  });
}
