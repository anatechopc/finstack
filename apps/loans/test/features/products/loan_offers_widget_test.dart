import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/loan_offer_item.dart';
import 'package:loooans/features/products/screen/loan_offers_widget.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class _MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

ProductView _view(String productId, {String loanType = 'Salary Loan'}) =>
    ProductView.create(
      companyId: 'company-1',
      companyName: 'Acme Lending',
      productId: productId,
      loanType: loanType,
      term: '30d',
      interestRate: 5,
      maxLoanableAmount: 50000,
      maxPeriod: 6,
      reviewRatingAvg: 4.5,
      reviewCount: 12,
      allowAddOns: true,
    );

/// The offers section on the `/` page, as `MainScreen` mounts it: the URL's
/// `&id=` handed in as `initialProductId`. The reported gap was that a search
/// result opened an offer without the address bar ever learning which one,
/// while a borrower opened as `/?sec=borrowers&id=`; the offers section now
/// follows the same rule — the URL owns the selection.
void main() {
  late _MockProductBloc products;
  late GoRouter router;

  setUp(() {
    SettingsService.initialize();
    SettingsService.instance.setClassicUIForTest(enabled: false);

    // A customer: the wide layout then renders the detail panel beside the
    // grid on selection rather than the admin edit dialog.
    AuthenticationService.instance.user = User()
      ..id = 'user-1'
      ..firstName = 'Juan'
      ..lastName = 'Dela Cruz'
      ..profilePhotoUrl = null
      ..userRole = UserRole.customer;

    products = _MockProductBloc();
    when(() => products.state).thenReturn(const ProductState());
    when(() => products.products).thenAnswer(
      (_) => Stream.value([_view('p1'), _view('p2', loanType: 'Business')]),
    );
    when(() => products.selectedProduct).thenReturn(null);
    // `initState` awaits nothing but the return must be a Future.
    when(
      () => products.loadNext(
        limit: any(named: 'limit'),
        allowAddOns: any(named: 'allowAddOns'),
      ),
    ).thenAnswer((_) async {});
  });

  void resize(WidgetTester tester, Size logical) {
    // `tester.view`, not `setSurfaceSize`: `MediaQuery.sizeOf` — which
    // `getScreenSize` reads — keeps reporting the 800px default otherwise.
    tester.view
      ..physicalSize = logical
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(
    WidgetTester tester, {
    required String initialLocation,
    List<GoRoute> extraRoutes = const [],
  }) {
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: Paths.index,
          builder: (_, state) => Scaffold(
            body: LoanOffersWidget(
              initialProductId: state.uri.queryParameters['id'],
            ),
          ),
        ),
        ...extraRoutes,
      ],
    );
    addTearDown(router.dispose);

    // The offer card overflows its 258px grid cell under the test font, whose
    // every glyph is a full-width box: "₱50,000.00" and "5% per 30 days" are
    // wider than the real font makes them, and nothing in the card changed
    // here. Layout is not what these tests assert, so overflow reports are
    // dropped; every other error still fails the test.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    return tester.pumpWidget(
      BlocProvider<ProductBloc>.value(
        value: products,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  group('wide screen: the URL owns the selection', () {
    testWidgets('/?sec=offers&id= selects that offer (a pasted deep link)',
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers&id=p1');
      await tester.pumpAndSettle();

      // By id alone: the grid had not rendered when the URL arrived, so the
      // bloc loads the view itself — the path a dynamic link already took.
      verify(() => products.selectProduct('p1')).called(1);
    });

    testWidgets(
        'a card tap is a URL change, and the URL selects — with the view '
        'the grid already has', (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers');
      await tester.pumpAndSettle();
      verifyNever(
        () => products.selectProduct(
          any(),
          productView: any(named: 'productView'),
        ),
      );

      await tester.tap(find.byType(LoanOfferItem).first);
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=offers&id=p1');
      verify(
        () => products.selectProduct(
          'p1',
          productView: any(named: 'productView', that: isA<ProductView>()),
        ),
      ).called(1);
    });

    testWidgets('keeps what else the URL carries (the apply-loan filter)',
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers&maxLoanable=100000');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LoanOfferItem).first);
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=offers&maxLoanable=100000&id=p1');
    });

    testWidgets('tapping the open offer again drops the id', (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LoanOfferItem).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LoanOfferItem).first);
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=offers');
    });

    testWidgets('the id leaving the URL (browser Back) unselects',
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers&id=p1');
      await tester.pumpAndSettle();
      when(() => products.selectedProduct).thenReturn(Product()..id = 'p1');

      router.go('/?sec=offers');
      await tester.pumpAndSettle();

      verify(() => products.unselectProduct()).called(1);
    });

    testWidgets('closing the offer from inside drops the id from the URL',
        (tester) async {
      // The panel's X calls `unselectProduct`; the URL said an offer was
      // open, so it must stop saying so — and that is also what makes
      // tapping the same card again a URL change.
      final states = StreamController<ProductState>();
      addTearDown(states.close);
      whenListen(products, states.stream, initialState: const ProductState());
      resize(tester, const Size(1600, 900));

      await pump(tester, initialLocation: '/?sec=offers&id=p1');
      await tester.pumpAndSettle();

      states.add(const ProductState.unselected());
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=offers');
    });
  });

  group('compact and medium: the selection drives the navigation', () {
    testWidgets('a card tap selects directly; this URL never carries the id',
        (tester) async {
      // 700px is `medium`. The listener sends the selection to the
      // full-screen route, whose own URL is the deep link.
      resize(tester, const Size(700, 800));

      await pump(tester, initialLocation: '/?sec=offers');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LoanOfferItem).first);
      await tester.pumpAndSettle();

      expect(router.location, '/?sec=offers');
      verify(
        () => products.selectProduct(
          'p1',
          productView: any(named: 'productView', that: isA<ProductView>()),
        ),
      ).called(1);
    });
  });

  group('openOffer — what a search result does', () {
    GoRoute opener(ProductView view) => GoRoute(
          path: Paths.search,
          builder: (_, __) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => LoanOffersWidget.openOffer(context, view),
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('wide: writes the URL, and the offers page selects from it',
        (tester) async {
      resize(tester, const Size(1600, 900));

      await pump(
        tester,
        initialLocation: Paths.search,
        extraRoutes: [opener(_view('p2'))],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));

      // Same tick: the URL is the deep link. Nothing is selected here —
      // the page that renders the selection does that, once mounted.
      expect(router.location, '/?sec=offers&id=p2');
      verifyNever(
        () => products.selectProduct(
          any(),
          productView: any(named: 'productView'),
        ),
      );

      await tester.pumpAndSettle();
      verify(() => products.selectProduct('p2')).called(1);
    });

    testWidgets('medium: navigates first, then selects a frame later',
        (tester) async {
      // `LoanDetails` listens to `ProductBloc` and pushes a loading dialog
      // on `loading`; selecting in the same tick as the navigation reached
      // it still mounted. The listener on the offers page then routes the
      // selection to the full-screen detail.
      resize(tester, const Size(700, 800));
      final view = _view('p2');

      await pump(
        tester,
        initialLocation: Paths.search,
        extraRoutes: [opener(view)],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));

      expect(router.location, '/?sec=offers');
      verifyNever(
        () => products.selectProduct(
          any(),
          productView: any(named: 'productView'),
        ),
      );

      await tester.pumpAndSettle();
      verify(() => products.selectProduct('p2', productView: view)).called(1);
    });
  });
}
