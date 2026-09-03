import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/screen/search_screen.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/offer_filter_bar.dart';
import 'package:loooans/features/search/widget/search_field.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _MockSearchIndex extends Mock implements SearchIndex {}

class _MockAuthenticationService extends Mock
    implements AuthenticationService {}

class _FakeSearchRequest extends Fake implements SearchRequest {}

const _wide = Size(1280, 800);

User _user({UserRole userRole = UserRole.admin}) => User()
  ..id = 'user-1'
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  ..emailAddress = 'juan.cruz@gmail.com'
  ..mobileNumber = '09175550142'
  ..userRole = userRole;

ProductView _productView() => ProductView.create(
      companyId: 'company-1',
      companyName: 'Acme Lending',
      productId: 'product-1',
      loanType: 'Salary Loan',
      term: '1m',
      interestRate: 5,
      maxLoanableAmount: 50000,
      maxPeriod: 6,
      reviewRatingAvg: 4.5,
      reviewCount: 12,
      allowAddOns: true,
    );

SearchResults _offerResults({bool hasMore = false}) => SearchResults(
      items: [
        OfferResultItem(
          productView: _productView(),
          matchedField: 'company_name',
        ),
      ],
      hasMore: hasMore,
    );

void main() {
  late _MockSearchIndex index;
  late _MockAuthenticationService auth;

  setUpAll(() {
    registerFallbackValue(_FakeSearchRequest());
    registerFallbackValue(const QueryChangedEvent('', location: ''));
  });

  setUp(() {
    index = _MockSearchIndex();
    auth = _MockAuthenticationService();
  });

  Widget subject({
    required SearchBloc bloc,
    String query = 'acme',
    String? scopeParam,
    OfferFilters filters = const OfferFilters(),
    Size size = _wide,
  }) =>
      MediaQuery(
        data: MediaQueryData(size: size),
        child: BlocProvider<SearchBloc>.value(
          value: bloc,
          child: SearchScreen(
            initialQuery: query,
            initialScopeParam: scopeParam,
            initialFilters: filters,
          ),
        ),
      );

  /// A REAL bloc, so the scope a deep link asks for is decided by
  /// `SearchScopeResolver` and not by the assertion's own arithmetic. A mocked
  /// bloc could only prove which event the screen dispatched, which is exactly
  /// the thing that must not be trusted.
  ///
  /// The screen reads the role off `AuthenticationService.instance`, as every
  /// other widget does; the bloc gets the injected mock, as `CLAUDE.md`
  /// requires of blocs. Both are seeded with the same user.
  SearchBloc realBloc(UserRole role) {
    AuthenticationService.instance.user = _user(userRole: role);
    when(() => auth.user).thenReturn(_user(userRole: role));
    when(() => index.query(any())).thenAnswer((_) async => SearchResults.empty);

    return SearchBloc.withDependencies(searchIndex: index, authService: auth);
  }

  SearchBloc mockBloc(SearchState state, {UserRole role = UserRole.admin}) {
    AuthenticationService.instance.user = _user(userRole: role);
    final bloc = _MockSearchBloc();
    when(() => bloc.state).thenReturn(state);

    return bloc;
  }

  List<SearchRequest> issued() =>
      verify(() => index.query(captureAny())).captured.cast<SearchRequest>();

  /// Two pumps: one to build and dispatch from `initState`, one to let the
  /// bloc drain its event stream. `pumpAndSettle` would hang on the loading
  /// spinner.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('the ?scope= deep link is a request, not a decision', () {
    // B11: the plan minted a `SearchScope` in `router.dart`, which has no role
    // gate anywhere in its 383 lines. This is the assertion that bites.
    testWidgets('a customer deep-linking ?scope=clients gets no clients search',
        (tester) async {
      final bloc = realBloc(UserRole.customer);
      addTearDown(bloc.close);

      await tester.pumpApp(subject(bloc: bloc, scopeParam: 'clients'));
      await settle(tester);

      // `verify` consumes the calls it matches, so capture once.
      final requests = issued();
      expect(requests, isNotEmpty);
      expect(requests.map((r) => r.scope), everyElement(SearchScope.offers));
    });

    // The other half of B11 step 5: the pin must actually work for a role that
    // holds the scope, or "the resolver decides" is just a way of ignoring it.
    testWidgets('a staff user deep-linking ?scope=offers gets an offers search',
        (tester) async {
      final bloc = realBloc(UserRole.admin);
      addTearDown(bloc.close);

      await tester.pumpApp(subject(bloc: bloc, scopeParam: 'offers'));
      await settle(tester);

      expect(issued().last.scope, SearchScope.offers);
    });

    // `products` is an alias a user may type before a colon, never a
    // deep-link spelling: `?scope=` matches `SearchScope.name` only.
    testWidgets('an unrecognised ?scope= falls back to the role default',
        (tester) async {
      final bloc = realBloc(UserRole.admin);
      addTearDown(bloc.close);

      await tester.pumpApp(subject(bloc: bloc, scopeParam: 'products'));
      await settle(tester);

      expect(issued().last.scope, SearchScope.clients);
    });

    testWidgets('tapping a scope tab re-queries in that scope', (tester) async {
      final bloc = realBloc(UserRole.admin);
      addTearDown(bloc.close);

      await tester.pumpApp(subject(bloc: bloc));
      await settle(tester);
      expect(issued().last.scope, SearchScope.clients);

      await tester.tap(find.byKey(const Key('search_scope_offers')));
      await settle(tester);

      expect(issued().last.scope, SearchScope.offers);
    });

    testWidgets('a customer is offered no clients tab', (tester) async {
      final bloc = realBloc(UserRole.customer);
      addTearDown(bloc.close);

      await tester.pumpApp(subject(bloc: bloc));
      await settle(tester);

      expect(find.byKey(const Key('search_scope_clients')), findsNothing);
      expect(find.text('Clients'), findsNothing);
    });
  });

  group('no interest-rate facet exists', () {
    // B8: the facet builds an illegal Firestore query and has no index in any
    // environment. Removing only the chip would leave the route param.
    test('the route ignores ?interest=', () {
      final screen = SearchScreen.fromQueryParameters(
        const {
          'q': 'acme',
          'scope': 'offers',
          'company': 'company-1',
          'term': '1m',
          'interest': '5',
        },
      );

      expect(screen.initialQuery, 'acme');
      expect(screen.initialScopeParam, 'offers');
      expect(screen.initialFilters.companyId, 'company-1');
      expect(screen.initialFilters.term, '1m');
    });

    testWidgets('the filter bar offers no interest-rate control',
        (tester) async {
      final bloc = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          scope: SearchScope.offers,
          term: 'acme',
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: bloc));

      expect(find.byType(OfferFilterBar), findsOneWidget);
      expect(find.textContaining('nterest'), findsNothing);
    });
  });

  group('the company facet', () {
    Future<void> pumpBar(WidgetTester tester, UserRole role) async {
      final bloc = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          scope: SearchScope.offers,
          term: 'acme',
          filters: OfferFilters(companyId: 'company-1'),
        ),
        role: role,
      );

      await tester.pumpApp(
        subject(bloc: bloc, filters: const OfferFilters(companyId: 'c')),
      );
    }

    // I11: `FirestoreSearchIndex` injects a staff member's own company on the
    // offers scope, so the facet cannot change what they see. A control that
    // does nothing is worse than no control.
    for (final role in UserRole.companyManagedRoles) {
      testWidgets('is hidden for ${role.name}', (tester) async {
        await pumpBar(tester, role);

        expect(find.byKey(const Key('filter_chip_company')), findsNothing);
      });
    }

    for (final role in [UserRole.customer, UserRole.appAdmin]) {
      testWidgets('is offered to ${role.name}', (tester) async {
        await pumpBar(tester, role);

        expect(find.byKey(const Key('filter_chip_company')), findsOneWidget);
      });
    }

    testWidgets('removing it clears only that facet', (tester) async {
      final bloc = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          scope: SearchScope.offers,
          term: 'acme',
          filters: OfferFilters(companyId: 'company-1', term: '1m'),
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: bloc));
      await tester.tap(find.byKey(const Key('filter_chip_company_remove')));
      await tester.pump();

      final changes = verify(() => bloc.add(captureAny()))
          .captured
          .whereType<FiltersChangedEvent>()
          .toList();

      expect(changes.last.filters.companyId, isNull);
      expect(changes.last.filters.term, '1m');
    });
  });

  group('the term facet', () {
    // Two values is the whole vocabulary a product can be created with
    // (`LoanTermSection`'s term options), so the chip pair IS the picker.
    SearchBloc offersBloc({String? term}) => mockBloc(
          SearchState(
            status: SearchStatus.empty,
            scope: SearchScope.offers,
            term: 'acme',
            filters: OfferFilters(term: term),
          ),
          role: UserRole.customer,
        );

    List<OfferFilters> changes(SearchBloc bloc) =>
        verify(() => bloc.add(captureAny()))
            .captured
            .whereType<FiltersChangedEvent>()
            .map((event) => event.filters)
            .toList();

    testWidgets('selecting a term sets it', (tester) async {
      final bloc = offersBloc();

      await tester.pumpApp(subject(bloc: bloc));
      await tester.tap(find.byKey(const Key('filter_chip_term_15d')));
      await tester.pump();

      expect(changes(bloc).last.term, '15d');
    });

    // Toggling the selected chip off is the remove affordance — a second
    // delete icon on a two-state chip would be a second way to do one thing.
    testWidgets('unselecting the active term clears it', (tester) async {
      final bloc = offersBloc(term: '1m');

      await tester.pumpApp(subject(bloc: bloc));
      await tester.tap(find.byKey(const Key('filter_chip_term_1m')));
      await tester.pump();

      expect(changes(bloc).last.term, isNull);
    });
  });

  group('the route drives the screen', () {
    /// `/search` behind a one-route router, built exactly as `router.dart`
    /// builds it.
    GoRouter searchRouter(SearchBloc bloc, String initialLocation) {
      final router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: Paths.search,
            builder: (_, state) => BlocProvider<SearchBloc>.value(
              value: bloc,
              child: SearchScreen.fromQueryParameters(
                state.uri.queryParameters,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      return router;
    }

    List<SearchEvent> events(SearchBloc bloc) =>
        verify(() => bloc.add(captureAny())).captured.cast<SearchEvent>();

    // A `FiltersChangedEvent` dispatched ahead of the query re-ran the
    // PREVIOUS term with the new facets: a billed read and a flash of the
    // wrong results. The facets ride on the query instead.
    testWidgets('deep-linked filters ride on the one query', (tester) async {
      final bloc = mockBloc(const SearchState());

      await tester.pumpApp(
        subject(bloc: bloc, filters: const OfferFilters(term: '1m')),
      );

      final dispatched = events(bloc);
      expect(dispatched, hasLength(1));
      final query = dispatched.single as QueryChangedEvent;
      expect(query.query, 'acme');
      expect(query.filters, const OfferFilters(term: '1m'));
    });

    // go_router keys the page by path, so a second "See all", `Ctrl K` from
    // the app bar or browser Back reaches a mounted screen as new props. The
    // field, the pin and the facets all used to keep showing the first link.
    testWidgets('a change of query parameters re-syncs field, pin and facets',
        (tester) async {
      final bloc = mockBloc(const SearchState());
      final router = searchRouter(bloc, '/search?q=juan');

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'juan'), findsOneWidget);
      expect((events(bloc).single as QueryChangedEvent).query, 'juan');

      router.go('/search?q=maria&scope=offers&term=1m');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'maria'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'juan'), findsNothing);
      // The field is the same one; `/search` was not remounted.
      expect(
        tester.widget<SearchField>(find.byType(SearchField)).pinnedScope,
        SearchScope.offers,
      );

      final dispatched = events(bloc);
      expect(dispatched, hasLength(1), reason: 'exactly one event, no facet');
      final query = dispatched.single as QueryChangedEvent;
      expect(query.query, 'maria');
      expect(query.pinnedScope, SearchScope.offers);
      expect(query.filters, const OfferFilters(term: '1m'));
    });

    testWidgets('the same parameters again dispatch nothing', (tester) async {
      final bloc = mockBloc(const SearchState());
      final router = searchRouter(bloc, '/search?q=juan');

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      events(bloc);

      router.go('/search?q=juan');
      await tester.pumpAndSettle();

      verifyNever(() => bloc.add(any()));
    });
  });

  group('the typed query', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 300));
    }

    QueryChangedEvent lastQuery(SearchBloc bloc) =>
        verify(() => bloc.add(captureAny()))
            .captured
            .whereType<QueryChangedEvent>()
            .last;

    // The bloc holds the chips; every typed query carries them, so a facet
    // never has to be re-sent ahead of the term it narrows.
    testWidgets('carries the chips the bloc holds', (tester) async {
      final bloc = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          scope: SearchScope.offers,
          term: 'acme',
          filters: OfferFilters(term: '15d'),
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: bloc));
      await type(tester, 'acme lending');

      final query = lastQuery(bloc);
      expect(query.query, 'acme lending');
      expect(query.filters, const OfferFilters(term: '15d'));
    });

    testWidgets('carries the active tab as the pin', (tester) async {
      final bloc = mockBloc(const SearchState());

      await tester.pumpApp(subject(bloc: bloc));
      await tester.tap(find.byKey(const Key('search_scope_offers')));
      await tester.pump();
      await type(tester, 'salary');

      expect(lastQuery(bloc).pinnedScope, SearchScope.offers);
    });

    // The page shows every row; only the app-bar panel trims the page.
    testWidgets('asks for the full candidate page', (tester) async {
      final bloc = mockBloc(const SearchState());

      await tester.pumpApp(subject(bloc: bloc));
      await type(tester, 'dela');

      expect(lastQuery(bloc).candidateLimit, isNull);
    });
  });

  group('states', () {
    testWidgets('too short asks for more characters', (tester) async {
      final bloc = mockBloc(
        const SearchState(status: SearchStatus.tooShort, term: 'd'),
      );

      await tester.pumpApp(subject(bloc: bloc));

      expect(find.textContaining('at least 2 characters'), findsOneWidget);
    });

    // `SearchStatus.tooShort` does NOT clear `state.results`, so the screen
    // branches on status. Rendering the list would show results for a query the
    // user has just erased.
    testWidgets('too short renders no stale results', (tester) async {
      final bloc = mockBloc(
        SearchState(
          status: SearchStatus.tooShort,
          scope: SearchScope.offers,
          term: 'd',
          results: _offerResults(),
        ),
      );

      await tester.pumpApp(subject(bloc: bloc));

      expect(find.byType(SearchResultTile), findsNothing);
    });

    // I14: filters narrow a token search, they never issue one. The chips stay
    // visible so a deep-linked facet can be removed.
    testWidgets('too short with filters says the term is what is missing',
        (tester) async {
      final bloc = mockBloc(
        const SearchState(
          status: SearchStatus.tooShort,
          scope: SearchScope.offers,
          filters: OfferFilters(term: '1m'),
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(
        subject(bloc: bloc, query: '', filters: const OfferFilters(term: '1m')),
      );

      expect(find.text('Add a search term to apply these filters.'),
          findsOneWidget,);
      expect(find.byType(OfferFilterBar), findsOneWidget);
    });

    // I15: only `users` documents carry phone tokens, and a customer can never
    // reach the clients scope — the mobile-number hint is unactionable for the
    // entire borrower population.
    testWidgets('the empty copy is scope-aware', (tester) async {
      final offers = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          scope: SearchScope.offers,
          term: 'acme',
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: offers));

      expect(find.textContaining('loan type'), findsOneWidget);
      expect(find.textContaining('mobile number'), findsNothing);

      final clients = mockBloc(
        const SearchState(
          status: SearchStatus.empty,
          term: 'dela',
        ),
      );

      await tester.pumpApp(subject(bloc: clients));

      expect(find.textContaining('mobile number'), findsOneWidget);
      expect(find.textContaining('loan type'), findsNothing);
    });

    testWidgets('results render one tile per item', (tester) async {
      final bloc = mockBloc(
        SearchState(
          status: SearchStatus.results,
          scope: SearchScope.offers,
          term: 'acme',
          results: _offerResults(),
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: bloc));

      expect(find.byType(SearchResultTile), findsOneWidget);
      expect(find.text('Salary Loan'), findsOneWidget);
    });

    // I10: `SearchResults` carries no total — only `hasMore`, set from the raw
    // page before refinement. v1 caps both surfaces; there is no "See all N".
    testWidgets('hasMore says so without inventing a count', (tester) async {
      final bloc = mockBloc(
        SearchState(
          status: SearchStatus.results,
          scope: SearchScope.offers,
          term: 'acme',
          results: _offerResults(hasMore: true),
        ),
        role: UserRole.customer,
      );

      await tester.pumpApp(subject(bloc: bloc));

      expect(find.textContaining('narrow your search'), findsOneWidget);
    });

    testWidgets('an error says so and keeps the field', (tester) async {
      final bloc = mockBloc(
        const SearchState(status: SearchStatus.error, term: 'dela'),
      );

      await tester.pumpApp(subject(bloc: bloc, query: 'dela'));

      expect(find.textContaining('went wrong'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'dela'), findsOneWidget);
    });
  });
}
