import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

/// One result row, shared by the overlay and `/search`.
///
/// Switches on the sum type rather than on an `id`: an offer row has no usable
/// document id (`product_view_projection.go:48-59` — legacy views carry
/// auto-generated ids and every consumer selects by `product_id`), so the two
/// scopes share no key to render from.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.item,
    required this.onTap,
    super.key,
  });

  final SearchResultItem item;
  final VoidCallback onTap;

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
    // `ImageUrl.url` throws when thumbnail and original are both null
    // (`image_url.dart:27-37`), so the photo is null-checked, not defaulted.
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
              Text(
                '${view.interestRate}% · '
                '${view.maxLoanableAmount.toCurrency()} · ${view.term}',
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
  /// (`product_view_projection.go:145-151`), so a raw average would render an
  /// honest-looking zero-star rating for a lender nobody has reviewed.
  static const _meta = TextStyle(fontSize: AppTypography.bodySmall);

  String _rating(ProductView view) => view.reviewCount == 0
      ? 'No reviews yet'
      : '${view.reviewRatingAvg.toStringAsFixed(1)} (${view.reviewCount})';
}
