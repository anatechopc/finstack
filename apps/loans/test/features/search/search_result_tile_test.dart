import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

class _MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

User _user() => User()
  ..id = 'user-1'
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  ..emailAddress = 'juan.cruz@gmail.com'
  ..mobileNumber = '09175550142';

/// Built through `ProductView.create`, which mirrors what the projection
/// writes. Note it is NOT given an `id` — the offer row must render without
/// one (legacy `product_views` ids are auto-generated and meaningless; every
/// consumer selects by `product_id`).
ProductView _productView({
  String companyName = 'Acme Lending',
  String loanType = 'Salary Loan',
  String? tagLine,
  double reviewRatingAvg = 4.5,
  int reviewCount = 12,
}) =>
    ProductView.create(
      companyId: 'company-1',
      companyName: companyName,
      productId: 'product-1',
      loanType: loanType,
      term: '30d',
      interestRate: 5,
      maxLoanableAmount: 50000,
      maxPeriod: 6,
      reviewRatingAvg: reviewRatingAvg,
      reviewCount: reviewCount,
      allowAddOns: true,
      tagLine: tagLine,
    );

void main() {
  Widget subject(SearchResultItem item, {VoidCallback? onTap}) => Scaffold(
        body: SearchResultTile(item: item, onTap: onTap ?? () {}),
      );

  group('client row', () {
    testWidgets('shows the name and the email when the email matched',
        (tester) async {
      await tester.pumpApp(
        subject(ClientResultItem(user: _user(), matchedField: 'email')),
      );

      expect(find.text('Dela Cruz, Juan'), findsOneWidget);
      expect(find.text('juan.cruz@gmail.com'), findsOneWidget);
    });

    testWidgets('falls back to the mobile number for a name match',
        (tester) async {
      await tester.pumpApp(
        subject(ClientResultItem(user: _user(), matchedField: 'name')),
      );

      expect(find.text('09175550142'), findsOneWidget);
      expect(find.text('juan.cruz@gmail.com'), findsNothing);
    });

    testWidgets('reports taps', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        subject(
          ClientResultItem(user: _user(), matchedField: 'name'),
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.byType(SearchResultTile));
      expect(tapped, isTrue);
    });
  });

  group('offer row', () {
    testWidgets('renders without an id, titled by loan type', (tester) async {
      await tester.pumpApp(
        subject(
          OfferResultItem(
            productView: _productView(),
            matchedField: 'loan_type',
          ),
        ),
      );

      expect(find.text('Salary Loan'), findsOneWidget);
      expect(find.text('Acme Lending'), findsOneWidget);
      expect(find.textContaining('4.5'), findsOneWidget);
    });

    // `term` is the stored code. `loan_offer_item.dart` renders the label,
    // and a result row that reads `30d` beside a formatted amount does not.
    testWidgets('spells the term out', (tester) async {
      await tester.pumpApp(
        subject(
          OfferResultItem(
            productView: _productView(),
            matchedField: 'loan_type',
          ),
        ),
      );

      expect(find.textContaining('30 days'), findsOneWidget);
      expect(find.textContaining('30d'), findsNothing);
    });

    testWidgets('surfaces the tag line when the tag line matched',
        (tester) async {
      await tester.pumpApp(
        subject(
          OfferResultItem(
            productView: _productView(tagLine: 'Fast cash, no collateral'),
            matchedField: 'tag_line',
          ),
        ),
      );

      expect(find.text('Fast cash, no collateral'), findsOneWidget);
    });

    testWidgets('says so when there are no reviews rather than showing 0.0',
        (tester) async {
      await tester.pumpApp(
        subject(
          OfferResultItem(
            productView: _productView(reviewRatingAvg: 0, reviewCount: 0),
            matchedField: 'company_name',
          ),
        ),
      );

      expect(find.text('No reviews yet'), findsOneWidget);
      // …and not the seeded zero average, which would read as a real
      // zero-star rating. (`textContaining` is no good here: the formatted
      // max-loanable amount legitimately ends in `0.00`.)
      expect(find.text('0.0 (0)'), findsNothing);
    });

    testWidgets('reports taps', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        subject(
          OfferResultItem(
            productView: _productView(),
            matchedField: 'company_name',
          ),
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.byType(SearchResultTile));
      expect(tapped, isTrue);
    });

    // `LoanDetails` listens to `ProductBloc` and pushes a loading dialog on
    // `loading`. Selecting in the same tick as the navigation reached a
    // still-mounted listener, which pushed a dialog nothing on the offers
    // page ever popped. The selection is deferred a frame — and still lands.
    testWidgets('opens the offers page first and selects a frame later',
        (tester) async {
      final products = _MockProductBloc();
      when(() => products.state).thenReturn(const ProductState());
      final view = _productView();
      final item = OfferResultItem(productView: view, matchedField: 'loan_type');

      final router = GoRouter(
        initialLocation: Paths.users,
        routes: [
          GoRoute(
            path: Paths.users,
            builder: (_, __) => Scaffold(
              body: Builder(
                builder: (context) => SearchResultTile(
                  item: item,
                  onTap: () => SearchResultTile.open(context, item),
                ),
              ),
            ),
          ),
          GoRoute(
            path: Paths.index,
            builder: (_, __) => const Scaffold(body: Text('offers page')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        BlocProvider<ProductBloc>.value(
          value: products,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.byType(SearchResultTile));

      // Same tick: navigated, not yet selected.
      expect(router.location, '/?sec=offers');
      verifyNever(
        () => products.selectProduct(any(), productView: any(named: 'productView')),
      );

      await tester.pumpAndSettle();

      expect(find.text('offers page'), findsOneWidget);
      verify(() => products.selectProduct('product-1', productView: view))
          .called(1);
    });
  });
}
