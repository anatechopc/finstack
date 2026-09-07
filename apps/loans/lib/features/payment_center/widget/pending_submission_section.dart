import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/payment_center/model/pending_submission.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:photo_view/photo_view.dart';

/// Lender-facing list of borrower payment submissions awaiting confirm/reject,
/// for the currently selected borrower. Submissions are grouped per
/// submissionId so a "pay in full" submission (N schedules) acts as one item.
/// Cards collapse to a single row; only one submission is open at a time.
class PendingSubmissionSection extends StatefulWidget {
  const PendingSubmissionSection({required this.state, super.key});

  final PaymentCenterState state;

  @override
  State<PendingSubmissionSection> createState() =>
      _PendingSubmissionSectionState();
}

class _PendingSubmissionSectionState extends State<PendingSubmissionSection> {
  String? _openId;

  @override
  Widget build(BuildContext context) {
    final submissions = widget.state.pendingSubmissions.values
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
          (submission) => _PendingSubmissionCard(
            submission: submission,
            isOpen: submission.submissionId == _openId,
            onToggle: () => setState(() {
              _openId = _openId == submission.submissionId
                  ? null
                  : submission.submissionId;
            }),
          ),
        ),
        const Gap(24),
      ],
    );
  }
}

class _PendingSubmissionCard extends StatefulWidget {
  const _PendingSubmissionCard({
    required this.submission,
    required this.isOpen,
    required this.onToggle,
  });

  final PendingSubmission submission;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  State<_PendingSubmissionCard> createState() =>
      _PendingSubmissionCardState();
}

class _PendingSubmissionCardState extends State<_PendingSubmissionCard> {
  final _formKey = GlobalKey<FormBuilderState>(
    debugLabel: 'pending_submission',
  );

  PendingSubmission get submission => widget.submission;

  @override
  Widget build(BuildContext context) {
    final firstPhoto = submission.payments
        .map((p) => p.transactionPhotoUrl)
        .firstWhere((url) => url?.original != null, orElse: () => null);
    final originalUrl = firstPhoto?.original;
    final displayUrl = firstPhoto?.thumbnail ?? originalUrl;
    final bankDetailsId = submission.payments.first.paidToBankDetailsId;
    final penalty = submission.schedules.fold<double>(
      0,
      (sum, s) =>
          sum + previewPenalty(schedule: s, loan: submission.loan).total,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ubOrange.withValues(alpha: 0.4)),
      ),
      // The checkbox in PaymentPenaltySection is a ListTile, which needs a
      // Material ancestor or it logs a "DecoratedBox with background color"
      // warning; this Container's decoration is exactly that background.
      child: Material(
        type: MaterialType.transparency,
        child: FormBuilder(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCollapsedRow(
                originalUrl,
                displayUrl,
                bankDetailsId,
                penalty,
              ),
              if (widget.isOpen)
                ..._buildExpandedBody(context, originalUrl, displayUrl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedRow(
    String? originalUrl,
    String? displayUrl,
    String? bankDetailsId,
    double penalty,
  ) {
    return Row(
      children: [
        _buildThumbnail(originalUrl, displayUrl),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (bankDetailsId != null && bankDetailsId.isNotEmpty)
                _PaidToLine(bankDetailsId: bankDetailsId),
              Text(
                'submitted '
                '${submission.payments.first.createdAt.toDefaultDateFormatWithDay()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.lightBlack,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Gap(12),
        if (submission.totalAmount != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (submission.totalAmount! + penalty).toCurrency(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (penalty > 0)
                Text(
                  'incl. ${penalty.toCurrency()} late penalty',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.red2,
                  ),
                ),
            ],
          ),
        const Gap(12),
        AppWidgets.defaultOutlinedButton(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          foregroundColor: AppColors.red,
          onPressed: () => _onReject(context),
          child: const Text('Reject'),
        ),
        const Gap(8),
        AppWidgets.defaultFilledButton(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          onPressed: widget.onToggle,
          child: Text(widget.isOpen ? 'Close' : 'Review'),
        ),
      ],
    );
  }

  Widget _buildThumbnail(String? originalUrl, String? displayUrl) {
    if (originalUrl == null || displayUrl == null) {
      return Container(
        width: 64,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    return GestureDetector(
      onTap: () => _showFullImage(context, originalUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: displayUrl,
          width: 64,
          height: 96,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => Container(
            width: 64,
            height: 96,
            alignment: Alignment.center,
            color: Colors.grey.withValues(alpha: 0.15),
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildExpandedBody(
    BuildContext context,
    String? originalUrl,
    String? displayUrl,
  ) {
    return [
      const Gap(12),
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
      PaymentPenaltySection(
        schedules: submission.schedules,
        loan: submission.loan,
        initialCollectedAt: submission.payments.first.createdAt,
      ),
      const Gap(12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppWidgets.defaultFilledButton(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            onPressed: () => _onConfirm(context),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ];
  }

  Future<void> _onReject(BuildContext context) async {
    final bloc = context.read<PaymentCenterBloc>();
    final reason = await _showRejectReasonDialog(context);
    if (reason == null || reason.trim().isEmpty) return;
    bloc.rejectSubmission(submission.payments, reason.trim());
  }

  void _onConfirm(BuildContext context) {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;
    final values = _formKey.currentState!.value;
    context.read<PaymentCenterBloc>().confirmSubmission(
      submission.payments,
      collectedAt: values['collected_at'] as DateTime?,
      waivePenalty: values['waive_penalty'] as bool? ?? false,
      waiveReason: values['waive_reason'] as String?,
    );
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

/// Resolves a submission's payout account once (cached) and renders a small
/// "Paid to" line. Caching the future in `initState` avoids re-fetching on
/// every Payment Center rebuild, and the `hasError` guard keeps a missing /
/// hard-deleted account from crashing the card.
class _PaidToLine extends StatefulWidget {
  const _PaidToLine({required this.bankDetailsId});

  final String bankDetailsId;

  @override
  State<_PaidToLine> createState() => _PaidToLineState();
}

class _PaidToLineState extends State<_PaidToLine> {
  late final Future<BankDetails> _future;

  @override
  void initState() {
    super.initState();
    _future =
        context.read<BaseRepository<BankDetails>>().get(id: widget.bankDetailsId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BankDetails>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final acct = snapshot.data;
        if (acct == null) return const SizedBox.shrink();
        final n = acct.accountNumber;
        final last4 = n.length >= 4 ? n.substring(n.length - 4) : n;
        return Text(
          'Paid to: ${acct.bankName} …$last4',
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
