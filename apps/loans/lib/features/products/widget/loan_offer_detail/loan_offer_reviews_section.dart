import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:review_repository/review_repository.dart';

class LoanOfferReviewsHeader extends StatelessWidget {
  const LoanOfferReviewsHeader({
    required this.reviews,
    required this.fullScreen,
    super.key,
  });

  /// The actual loaded reviews — the summary (average + count) is derived from
  /// these so it always matches what's displayed, instead of a stored
  /// per-product aggregate that drifts out of sync.
  final List<Review> reviews;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final isMedium = getScreenSize(context: context) == ScreenSize.medium;
    final reviewCount = reviews.length;
    final reviewAvg = reviewCount == 0
        ? 0.0
        : reviews.fold<double>(0, (sum, r) => sum + r.rating) / reviewCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Gap(4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reviews',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (fullScreen && isMedium)
              InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () {
                  context.read<ProductBloc>().unselectProduct();
                  GoRouter.of(context).goSafe('${Paths.index}?sec=offers');
                },
                child: SvgPicture.asset(
                  'svg/close.svg'.assetSafe,
                  colorFilter: const ColorFilter.mode(
                    AppColors.black,
                    BlendMode.srcIn,
                  ),
                ),
              ),
          ],
        ),
        const Gap(4),
        Row(
          children: [
            AbsorbPointer(
              child: AppWidgets.defaultRatingBar(
                  initialRating: reviewAvg,
                  itemSize: 24,
                  onRatingUpdate: (rating) {
                    debugPrint('ratig');
                  },),
            ),
            const Gap(8),
            Text(
              '${reviewAvg.toStringAsFixed(1)}($reviewCount)',
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class LoanOfferReviewItem extends StatelessWidget {
  const LoanOfferReviewItem({
    required this.review,
    super.key,
  });

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.32),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.white,
                    child: Text(
                      review.userFullName.initials(limit: 2),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Gap(4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userFullName,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    AbsorbPointer(
                      child: AppWidgets.defaultRatingBar(
                        onRatingUpdate: (rating) {
                          debugPrint('rating: $rating');
                        },
                        initialRating: review.rating.toDouble(),
                        itemSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: Text(
                review.createdAt.toDefaultDateFormat(),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const Gap(8),
        Text(
          review.message,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
        if (review.hasResponse) ...[
          const Gap(8),
          _ReviewResponseBlock(review: review),
        ],
      ],
    );
  }
}

/// The company's reply rendered beneath a borrower review. Shown only when
/// [Review.hasResponse] is true. Indented with a left accent so it reads as a
/// nested reply rather than a separate review.
class _ReviewResponseBlock extends StatelessWidget {
  const _ReviewResponseBlock({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final respondedAt = review.respondedAt;

    return Container(
      key: const Key('review_response_block'),
      margin: const EdgeInsets.only(left: 16),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: AppColors.black.withValues(alpha: 0.24),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Response from ${review.respondedByName ?? ''}'.trim(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.black,
                  ),
                ),
              ),
              if (respondedAt != null)
                Text(
                  respondedAt.toDefaultDateFormat(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.black,
                  ),
                ),
            ],
          ),
          const Gap(4),
          Text(
            review.response ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown beneath the reviews header when the company has no reviews yet, so the
/// panel reads intentionally instead of looking blank/broken.
class LoanOfferReviewsEmpty extends StatelessWidget {
  const LoanOfferReviewsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('loan_offer_reviews_empty'),
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No reviews yet.',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.black,
        ),
      ),
    );
  }
}
