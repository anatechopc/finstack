import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/widget/search_result_tile.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

import '../../helpers/helpers.dart';

User _user() => User()
  ..id = 'user-1'
  ..firstName = 'Juan'
  ..lastName = 'Dela Cruz'
  ..emailAddress = 'juan.cruz@gmail.com'
  ..mobileNumber = '09175550142';

/// Built through `ProductView.create`, which mirrors what the projection
/// writes. Note it is NOT given an `id` — the offer row must render without
/// one (`product_view_projection.go:48-59`: legacy view ids are meaningless).
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
  });
}
