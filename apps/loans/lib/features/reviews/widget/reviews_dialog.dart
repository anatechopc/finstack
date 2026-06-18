import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/products/widget/loan_offer_detail/loan_offer_reviews_section.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/features/reviews/widget/review_response_dialog.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:review_repository/review_repository.dart';

/// Header sentence summarising the company's standing, derived from its
/// aggregate rating (image 4 of issue #47). Kept pure so the dialog stays
/// testable without the [AuthenticationService] singleton.
String reviewsSummary(Company company) {
  if (company.reviewCount == 0) {
    return 'You have no reviews yet. They will appear here once borrowers '
        'leave one.';
  }
  final avg = company.totalRating / company.reviewCount;
  return 'As of the moment, you have a ${avg.toStringAsFixed(1)} star rating '
      'across ${company.reviewCount} review(s). Congratulations!';
}

/// Admin modal listing every review left for the logged-in company, each with a
/// Respond (or Edit) action. Loads via [ReviewsBloc] on open. Opened from the
/// Reviews score card on the Reports dashboard.
Future<void> showReviewsDialog(BuildContext context) {
  final bloc = context.read<ReviewsBloc>()..add(LoadCompanyReviewsEvent());
  final summary = reviewsSummary(AuthenticationService.instance.company);
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: ReviewsDialog(summary: summary),
    ),
  );
}

class ReviewsDialog extends StatelessWidget {
  const ReviewsDialog({required this.summary, super.key});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Reviews',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary,
              style: const TextStyle(fontSize: 12),
            ),
            const Gap(16),
            Flexible(
              child: BlocBuilder<ReviewsBloc, ReviewsState>(
                builder: (context, state) {
                  if (state.status == ReviewsStatus.loading &&
                      state.reviews.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (state.reviews.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No reviews to show.',
                        style: TextStyle(fontSize: 12, color: AppColors.black),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.reviews.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      return _AdminReviewRow(review: state.reviews[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: AppWidgets.defaultOutlinedButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ),
      ],
    );
  }
}

/// A single review in the admin list: the borrower review (reusing
/// [LoanOfferReviewItem], which also renders an existing response) plus the
/// Respond / Edit action.
class _AdminReviewRow extends StatelessWidget {
  const _AdminReviewRow({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoanOfferReviewItem(review: review),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: AppWidgets.defaultOutlinedButton(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            onPressed: () => showReviewResponseDialog(context, review: review),
            child: Text(review.hasResponse ? 'Edit response' : 'Respond'),
          ),
        ),
      ],
    );
  }
}
