import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/users/screens/borrowers_screen.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

/// One result row, shared by the overlay and `/search`.
///
/// Switches on the sum type rather than on an `id`: an offer row has no usable
/// document id (legacy `product_views` carry auto-generated ids and every
/// consumer selects by `product_id` — see `HandleProductWrittenCore` in the
/// Go projection), so the two scopes share no key to render from.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.item,
    required this.onTap,
    super.key,
  });

  final SearchResultItem item;
  final VoidCallback onTap;

  /// Where a row goes when it is tapped — shared by the overlay and `/search`,
  /// because "where does this result live" is a property of the row and not of
  /// the surface that happens to be showing it.
  ///
  /// Navigates to the surface that renders the row *before* selecting into it:
  /// `ProductState.selected` is only rendered by `loan_offers_widget.dart`, so
  /// selecting first would select a product with nothing mounted to show it.
  static void open(BuildContext context, SearchResultItem item) {
    final router = GoRouter.maybeOf(context);

    switch (item) {
      case OfferResultItem(:final productView):
        // Read before navigating: `go` deactivates this element on the same
        // frame and a deactivated context cannot `read`.
        final products = context.read<ProductBloc>();
        router?.go('${Paths.index}?sec=offers');
        // Deferred a frame. `LoanDetails` listens to `ProductBloc` and pushes
        // a loading dialog on `loading`; selecting in the same tick as the
        // navigation reached a still-mounted listener, which pushed a dialog
        // that nothing on the offers page ever popped.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => products.selectProduct(
            productView.productId,
            productView: productView,
          ),
        );
      case ClientResultItem(:final user):
        // The same entry point a Borrowers row uses, so a result opens exactly
        // as a row does and the UI mode is decided in ONE place. A URL written
        // here as well drifted immediately: the non-classic branch was added
        // to openBorrower and this path kept sending non-classic users to the
        // home page with an id in the address bar.
        BorrowerScreen.openBorrower(context, user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      ClientResultItem(:final user) => _clientTile(user),
      OfferResultItem(:final productView) => _offerTile(context, productView),
    };
  }

  Widget _clientTile(User user) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.green1,
        child: Text(
          user.initials,
          style: const TextStyle(
            color: AppColors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(user.completeNameEasternOrder),
      // The row has to explain why it matched: an email hit whose subtitle is
      // a phone number reads as a wrong result.
      subtitle: Text(
        item.matchedField == 'email' ? user.emailAddress : user.mobileNumber,
      ),
    );
  }

  Widget _offerTile(BuildContext context, ProductView view) {
    // `ImageUrl.url` throws when thumbnail and original are both null, so the
    // photo is null-checked, not defaulted.
    final photo = view.companyProfilePhotoUrl;

    // A tag-line match is otherwise invisible — company name and loan type
    // would both be shown without either containing the term.
    final subtitle = item.matchedField == 'tag_line' && view.tagLine != null
        ? view.tagLine!
        : view.companyName;

    return ListTile(
      onTap: onTap,
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: AppColors.green1,
        backgroundImage:
            photo == null ? null : CachedNetworkImageProvider(photo.url),
        child: photo == null
            ? Text(
                view.companyName.initials(limit: 2),
                style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(view.loanType),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              // `completeTerm`, as `loan_offer_item.dart` renders it: the raw
              // `term` is the stored code (`1m`, `15d`), not a label.
              Text(
                '${view.interestRate}% · '
                '${view.maxLoanableAmount.toCurrency()} · ${view.completeTerm}',
                style: _meta,
              ),
              Text(_rating(view), style: _meta),
            ],
          ),
        ],
      ),
    );
  }

  /// `review_rating_avg` is seeded to `0.0` whenever `review_count` is `0`
  /// (`projectedProductFields` in the Go projection), so a raw average would
  /// render an honest-looking zero-star rating for a lender nobody has
  /// reviewed.
  static const _meta = TextStyle(fontSize: AppTypography.bodySmall);

  String _rating(ProductView view) => view.reviewCount == 0
      ? 'No reviews yet'
      : '${view.reviewRatingAvg.toStringAsFixed(1)} (${view.reviewCount})';
}
