import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/model/pending_submission.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:photo_view/photo_view.dart';

/// Lender-facing list of borrower payment submissions awaiting confirm/reject,
/// for the currently selected borrower. Submissions are grouped per
/// submissionId so a "pay in full" submission (N schedules) acts as one item.
class PendingSubmissionSection extends StatelessWidget {
  const PendingSubmissionSection({required this.state, super.key});

  final PaymentCenterState state;

  @override
  Widget build(BuildContext context) {
    final submissions = state.pendingSubmissions.values
        .expand((list) => list)
        .toList();

    if (submissions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Payment Submissions (${submissions.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const Gap(12),
        ...submissions.map(
          (submission) => _PendingSubmissionCard(submission: submission),
        ),
        const Gap(24),
      ],
    );
  }
}

class _PendingSubmissionCard extends StatelessWidget {
  const _PendingSubmissionCard({required this.submission});

  final PendingSubmission submission;

  @override
  Widget build(BuildContext context) {
    final firstPhoto = submission.payments
        .map((p) => p.transactionPhotoUrl)
        .firstWhere((url) => url?.original != null, orElse: () => null);
    final originalUrl = firstPhoto?.original;
    final displayUrl = firstPhoto?.thumbnail ?? originalUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ubOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long,
                size: 18,
                color: AppColors.ubOrange,
              ),
              const Gap(6),
              Expanded(
                child: Text(
                  submission.payments.length > 1
                      ? '${submission.payments.length} schedules'
                      : '1 schedule',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (submission.totalAmount != null)
                Text(
                  submission.totalAmount!.toCurrency(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          const Gap(8),
          if (originalUrl != null && displayUrl != null)
            GestureDetector(
              onTap: () => _showFullImage(context, originalUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: displayUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    height: 140,
                    color: Colors.grey.withValues(alpha: 0.15),
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'No screenshot provided',
                style: TextStyle(color: Colors.black, fontSize: 12),
              ),
            ),
          const Gap(12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppWidgets.defaultOutlinedButton(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                onPressed: () => _onReject(context),
                child: const Text('Reject'),
              ),
              const Gap(8),
              AppWidgets.defaultFilledButton(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                onPressed: () {
                  context
                      .read<PaymentCenterBloc>()
                      .confirmSubmission(submission.payments);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onReject(BuildContext context) async {
    final bloc = context.read<PaymentCenterBloc>();
    final reason = await _showRejectReasonDialog(context);
    if (reason == null || reason.trim().isEmpty) return;
    bloc.rejectSubmission(submission.payments, reason.trim());
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              SizedBox(
                height: 400,
                width: double.infinity,
                child: PhotoView(
                  imageProvider: CachedNetworkImageProvider(url),
                  backgroundDecoration: const BoxDecoration(
                    color: AppColors.white,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).maybePop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> _showRejectReasonDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Reject submission'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Why is this submission being rejected?',
          ),
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true)
                  .pop(controller.text);
            },
            child: const Text('Reject'),
          ),
          AppWidgets.defaultOutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
