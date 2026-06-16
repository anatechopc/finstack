import 'dart:typed_data';

import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/payments/bloc/payment_submission_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Shows the borrower submit-payment dialog. The caller passes the exact
/// payable [schedules] (one for "Pay now", all remaining unpaid for
/// "Pay in full"), the REAL [loanId] (runtime open-term schedules carry a
/// placeholder loanId), the lender [companyId] (to look up where to pay), and
/// the total [amount] being submitted.
Future<void> showSubmitPaymentDialog(
  BuildContext context, {
  required List<LoanSchedule> schedules,
  required String loanId,
  required String companyId,
  required double amount,
  PaymentSubmissionBloc Function(BuildContext)? createBloc,
}) {
  final bankDetailsRepository = context.read<BaseRepository<BankDetails>>();
  // Capture the caller's messenger BEFORE the dialog is shown/popped so we can
  // still surface SnackBars after the dialog route is gone.
  final messenger = ScaffoldMessenger.of(context);

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      // Fresh bloc per dialog so stale success/error state from a previous
      // submission never leaks into a newly-opened dialog. [createBloc] is a
      // test seam; production omits it and gets a real bloc.
      return BlocProvider(
        create: createBloc ?? PaymentSubmissionBloc.new,
        child: BlocListener<PaymentSubmissionBloc, PaymentSubmissionState>(
          listener: (listenerCtx, state) {
            if (state.status == PaymentSubmissionStatus.success) {
              Navigator.of(dialogCtx, rootNavigator: true).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Payment submitted for review')),
              );
            } else if (state.status == PaymentSubmissionStatus.error) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(state.message ?? 'Submit failed'),
                ),
              );
            }
          },
          child: _SubmitPaymentDialogBody(
            schedules: schedules,
            loanId: loanId,
            companyId: companyId,
            amount: amount,
            bankDetailsRepository: bankDetailsRepository,
          ),
        ),
      );
    },
  );
}

class _SubmitPaymentDialogBody extends StatefulWidget {
  const _SubmitPaymentDialogBody({
    required this.schedules,
    required this.loanId,
    required this.companyId,
    required this.amount,
    required this.bankDetailsRepository,
  });

  final List<LoanSchedule> schedules;
  final String loanId;
  final String companyId;
  final double amount;
  final BaseRepository<BankDetails> bankDetailsRepository;

  @override
  State<_SubmitPaymentDialogBody> createState() =>
      _SubmitPaymentDialogBodyState();
}

class _SubmitPaymentDialogBodyState extends State<_SubmitPaymentDialogBody> {
  bool _loadingBankDetails = true;
  BankDetails? _bankDetails;
  String? _fileName;
  Uint8List? _fileBytes;

  @override
  void initState() {
    super.initState();
    _loadBankDetails();
  }

  Future<void> _loadBankDetails() async {
    try {
      final results = await widget.bankDetailsRepository.load(
        statements: [
          QueryStatement(field: 'data_id', isEqualTo: widget.companyId),
        ],
      );
      final company = results
          .where((b) => b.dataType == DataType.provider)
          .toList();
      if (!mounted) return;
      setState(() {
        _bankDetails = company.isNotEmpty ? company.first : null;
        _loadingBankDetails = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bankDetails = null;
        _loadingBankDetails = false;
      });
    }
  }

  Future<void> _chooseFile() async {
    final fileData = await AppWidgets.defaultMediaChooserDialog(context);
    if (!mounted) return;
    if (fileData == null) return;
    setState(() {
      _fileName = fileData['name'] as String;
      _fileBytes = fileData['bytes'] as Uint8List;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bankDetails = _bankDetails;
    final hasBankDetails = bankDetails != null;
    final hasFile = _fileBytes != null && _fileName != null;

    return AlertDialog(
      title: const Text(
        'Submit payment',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 500,
        child: BlocBuilder<PaymentSubmissionBloc, PaymentSubmissionState>(
          builder: (context, state) {
            final submitting =
                state.status == PaymentSubmissionStatus.submitting;

            if (_loadingBankDetails) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasBankDetails)
                  const Text(
                    "The lender hasn't set up bank details yet — "
                    'contact them.',
                    style: TextStyle(color: Colors.black),
                  )
                else ...[
                  const Text(
                    'Pay to:',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'Bank: ${bankDetails.bankName}',
                    style: const TextStyle(color: Colors.black),
                  ),
                  Text(
                    'Account name: ${bankDetails.accountName}',
                    style: const TextStyle(color: Colors.black),
                  ),
                  Text(
                    'Account number: ${bankDetails.accountNumber}',
                    style: const TextStyle(color: Colors.black),
                  ),
                ],
                const Gap(16),
                Text(
                  'Amount to pay: ${widget.amount.toCurrency()}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(16),
                AppWidgets.defaultOutlinedButton(
                  onPressed: submitting ? null : _chooseFile,
                  child: const Text('Choose screenshot'),
                ),
                if (hasFile) ...[
                  const Gap(8),
                  Text(
                    'Attached: $_fileName',
                    style: const TextStyle(color: Colors.black),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        BlocBuilder<PaymentSubmissionBloc, PaymentSubmissionState>(
          builder: (context, state) {
            final submitting =
                state.status == PaymentSubmissionStatus.submitting;
            final canSend = hasBankDetails && hasFile && !submitting;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: AppWidgets.defaultFilledButton(
                    onPressed: canSend
                        ? () {
                            context.read<PaymentSubmissionBloc>().add(
                                  SubmitPaymentEvent(
                                    schedules: widget.schedules,
                                    loanId: widget.loanId,
                                    fileBytes: _fileBytes!,
                                    fileName: _fileName!,
                                  ),
                                );
                          }
                        : null,
                    child: submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AppWidgets.defaultOutlinedButton(
                    onPressed: submitting
                        ? null
                        : () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
