import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/widget/search_overlay.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

User _user(int n) => User()
  ..id = 'user-$n'
  ..firstName = 'Juan$n'
  ..lastName = 'Dela Cruz'
  ..emailAddress = 'juan$n@gmail.com'
  ..mobileNumber = '0917555014$n';

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

SearchResults _clients(int count, {bool hasMore = false}) => SearchResults(
      items: [
        for (var i = 0; i < count; i++)
          ClientResultItem(user: _user(i), matchedField: 'name'),
      ],
      scope: SearchScope.clients,
      hasMore: hasMore,
    );

void main() {
  late SearchBloc bloc;

  setUpAll(
    () => registerFallbackValue(const QueryChangedEvent('', location: '')),
  );

  setUp(() {
    bloc = _MockSearchBloc();
    when(() => bloc.state).thenReturn(const SearchState());
  });

  Widget subject({VoidCallback? onDismiss, SearchBloc? withBloc}) =>
      BlocProvider<SearchBloc>.value(
        value: withBloc ?? bloc,
        child: Scaffold(
          body: SearchOverlay(onDismiss: onDismiss ?? () {}),
        ),
      );

  void seed(SearchState state) => when(() => bloc.state).thenReturn(state);

  /// A FRESH mock per state. `BlocBuilder` reads `bloc.state` once at init and
  /// then follows the stream, so re-stubbing `state` on a bloc already mounted
  /// changes nothing on the next pump.
  SearchBloc blocSeeded(SearchState state) {
    final fresh = _MockSearchBloc();
    when(() => fresh.state).thenReturn(state);

    return fresh;
  }

  group('the cap', () {
    testWidgets('renders at most maxItems rows however many came back',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          term: 'dela',
          results: _clients(9),
        ),
      );

      await tester.pumpApp(subject());

      expect(
        find.byType(SearchResultTile),
        findsNWidgets(SearchOverlay.maxItems),
      );
    });

    // I10: `SearchResults` carries no total, so a count would be the survivors
    // of refinement among the first page — "See all 14 results" for 300
    // matches. The row says there is more, and nothing about how much.
    testWidgets('offers See all when it is showing fewer than it has',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          term: 'dela',
          results: _clients(7),
        ),
      );

      await tester.pumpApp(subject());

      expect(find.text('See all results'), findsOneWidget);
      expect(find.textContaining('7 results'), findsNothing);
    });

    // `hasMore` is set from the RAW page, before refinement. Two refined rows
    // out of a full page still means more matches exist.
    testWidgets('offers See all when the raw page came back full',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          term: 'dela',
          results: _clients(2, hasMore: true),
        ),
      );

      await tester.pumpApp(subject());

      expect(find.text('See all results'), findsOneWidget);
    });

    testWidgets('offers no See all when every match is on screen',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          term: 'dela',
          results: _clients(2),
        ),
      );

      await tester.pumpApp(subject());

      expect(find.text('See all results'), findsNothing);
    });

    testWidgets('See all carries the term and the resolved scope to /search',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          scope: SearchScope.offers,
          // Prefix-STRIPPED, as the bloc stores it. Carrying the raw
          // 'products: salary' would make `/search` re-resolve a scope the
          // overlay had already decided.
          term: 'salary',
          results: SearchResults(
            items: [
              for (var i = 0; i < 7; i++)
                OfferResultItem(
                  productView: _productView(),
                  matchedField: 'loan_type',
                ),
            ],
            scope: SearchScope.offers,
          ),
        ),
      );

      final router = GoRouter(
        initialLocation: Paths.index,
        routes: [
          GoRoute(path: Paths.index, builder: (_, __) => subject()),
          GoRoute(
            path: Paths.search,
            builder: (_, __) => const Scaffold(body: Text('search page')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('See all results'));
      await tester.pumpAndSettle();

      expect(router.location, '/search?q=salary&scope=offers');
    });

    testWidgets('tapping a client opens that borrower, not the clients list',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.results,
          term: 'juan',
          results: SearchResults(
            items: [
              ClientResultItem(user: _user(7), matchedField: 'name'),
            ],
            scope: SearchScope.clients,
          ),
        ),
      );

      final router = GoRouter(
        initialLocation: Paths.index,
        routes: [
          GoRoute(path: Paths.index, builder: (_, __) => subject()),
          GoRoute(
            path: Paths.borrowersAction,
            builder: (_, __) => const Scaffold(body: Text('borrower page')),
          ),
          GoRoute(
            path: Paths.clientsAction,
            builder: (_, __) => const Scaffold(body: Text('clients list')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('Dela Cruz, Juan7'));
      await tester.pumpAndSettle();

      // The reported bug: this landed on the clients list, so the user had to
      // find again by hand the client they had just searched for.
      expect(router.location, '/borrowers/user-7');
    });
  });

  group('states', () {
    testWidgets('idle draws nothing at all', (tester) async {
      await tester.pumpApp(subject());

      // Not `find.byType(Material)`: the Scaffold hosting it is one.
      expect(
        find.descendant(
          of: find.byType(SearchOverlay),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('too short asks for more characters', (tester) async {
      seed(const SearchState(status: SearchStatus.tooShort, term: 'd'));

      await tester.pumpApp(subject());

      expect(find.textContaining('2 characters'), findsOneWidget);
    });

    // The bloc clears results on `tooShort`, but the overlay branches on
    // status rather than trusting it: a status-blind body would render the
    // results of a query the user has just erased.
    testWidgets('too short renders no stale rows', (tester) async {
      seed(
        SearchState(
          status: SearchStatus.tooShort,
          term: 'd',
          results: _clients(3),
        ),
      );

      await tester.pumpApp(subject());

      expect(find.byType(SearchResultTile), findsNothing);
      expect(find.text('See all results'), findsNothing);
    });

    testWidgets('loading shows placeholder rows and no results',
        (tester) async {
      seed(
        SearchState(
          status: SearchStatus.loading,
          term: 'dela',
          results: _clients(3),
        ),
      );

      await tester.pumpApp(subject());

      expect(find.byType(SearchResultTile), findsNothing);
      expect(find.byType(ListTile), findsWidgets);
    });

    // I15: only `users` documents carry phone tokens, and a customer can never
    // reach the clients scope — the mobile-number hint is unactionable for the
    // entire borrower population.
    testWidgets('the empty copy is scope-aware', (tester) async {
      await tester.pumpApp(
        subject(
          withBloc: blocSeeded(
            const SearchState(
              status: SearchStatus.empty,
              scope: SearchScope.offers,
              term: 'acme',
            ),
          ),
        ),
      );

      expect(find.textContaining('Try a shorter term'), findsOneWidget);
      expect(find.textContaining('loan type'), findsOneWidget);
      expect(find.textContaining('mobile number'), findsNothing);

      await tester.pumpApp(
        subject(
          withBloc: blocSeeded(
            const SearchState(status: SearchStatus.empty, term: 'dela'),
          ),
        ),
      );

      expect(find.textContaining('Try a shorter term'), findsOneWidget);
      expect(find.textContaining('mobile number'), findsOneWidget);
      expect(find.textContaining('loan type'), findsNothing);
    });

    testWidgets('an error offers a retry that re-runs the same query',
        (tester) async {
      seed(
        const SearchState(
          status: SearchStatus.error,
          scope: SearchScope.offers,
          term: 'salary',
        ),
      );

      await tester.pumpApp(subject());
      expect(find.textContaining('went wrong'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      final retries = verify(() => bloc.add(captureAny()))
          .captured
          .whereType<QueryChangedEvent>()
          .toList();

      expect(retries, hasLength(1));
      // The term is kept, and the scope is pinned: re-resolving a stripped
      // term at the current location would silently flip `products: salary`
      // back to the clients scope.
      expect(retries.single.query, 'salary');
      expect(retries.single.pinnedScope, SearchScope.offers);
    });
  });

  testWidgets('renders both arms of the result sum type', (tester) async {
    seed(
      SearchState(
        status: SearchStatus.results,
        term: 'acme',
        results: SearchResults(
          items: [
            ClientResultItem(user: _user(1), matchedField: 'name'),
            OfferResultItem(
              productView: _productView(),
              matchedField: 'company_name',
            ),
          ],
          scope: SearchScope.clients,
        ),
      ),
    );

    await tester.pumpApp(subject());

    expect(find.byType(SearchResultTile), findsNWidgets(2));
    expect(find.text('Dela Cruz, Juan1'), findsOneWidget);
    expect(find.text('Salary Loan'), findsOneWidget);
  });

  testWidgets('tapping a row dismisses the overlay', (tester) async {
    seed(
      SearchState(
        status: SearchStatus.results,
        term: 'dela',
        results: _clients(1),
      ),
    );

    var dismissed = false;
    await tester.pumpApp(subject(onDismiss: () => dismissed = true));
    await tester.tap(find.byType(SearchResultTile));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
