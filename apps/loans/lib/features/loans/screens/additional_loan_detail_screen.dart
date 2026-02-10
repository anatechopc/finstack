import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';

class AdditionalLoanDetailScreen extends StatelessWidget {
  const AdditionalLoanDetailScreen({
    required this.additionalLoanId,
    super.key,
    this.isDialog = false,
  });

  final bool isDialog;
  final String additionalLoanId;

  @override
  Widget build(BuildContext context) {
    return isDialog
        ? _blocListenerWrapper(context, _body(context))
        : _blocListenerWrapper(
            context,
            Scaffold(
              appBar: AppBar(
                title: const Text('Additional Loan Detail'),
              ),
              body: _body(context),
            ),
          );
  }

  Widget _blocListenerWrapper(BuildContext context, Widget child) {
    return BlocListener<AdditionalLoanBloc, AdditionalLoanState>(
      listener: (context, state) {
        if (state.status == AdditionalLoanStatus.success) {
          Navigator.of(context, rootNavigator: true).pop();
        } else if (state.status == AdditionalLoanStatus.loading) {
          if (state.isLoading) {
            AppWidgets.showDefaultLoadingDialog(context);
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } else if (state.status == AdditionalLoanStatus.error) {
          final message = state.message;
          if (message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        }
      },
      child: child,
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      children: [
        if (isDialog) ...[
          Text(
            'Additional Loan Detail',
            style: GoogleFonts.urbanist(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(16),
        ],
        _submittedFiles(context),
        const Spacer(),
        _actionButtons(context),
      ],
    );
  }

  Widget _submittedFiles(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final selectedLoan = context.read<LoansBloc>().selectedLoan;
        final additionalLoan = selectedLoan.additionalLoanAmounts
            .firstWhereOrNull((loan) => loan.id == additionalLoanId);

        if (additionalLoan == null) {
          return Container();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'Submitted files',
                    maxLines: 2,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Gap(8),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          content: SizedBox(
                            width: 1000,
                            height: 800,
                            child: FileViewerWidget(
                              photosUrls: [
                                additionalLoan.selfiePhotoUrl,
                                additionalLoan.signatureUrl,
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  child: const Icon(Icons.visibility_rounded),
                ),
              ],
            ),
            const Gap(16),
            ...additionalLoan.uploadedFilesUrls
                .groupListsBy((req) => req.name)
                .keys
                .map((key) => AppWidgets.legendItem(title: key)),
            AppWidgets.legendItem(title: additionalLoan.signatureUrl.name),
            AppWidgets.legendItem(title: additionalLoan.selfiePhotoUrl.name),
          ],
        );
      },
    );
  }

  Widget _actionButtons(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      builder: (context, state) {
        final loan = context.read<LoansBloc>().selectedLoan;
        final additionalLoan = loan.additionalLoanAmounts
            .firstWhereOrNull((loan) => loan.id == additionalLoanId);

        if (additionalLoan == null) {
          return Container();
        }
        return Row(
          children: [
            Expanded(
              child: AppWidgets.defaultFilledButton(
                foregroundColor: AppColors.green2,
                child: const Text('Approve'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Are you sure?'),
                        content: const Text(
                          'Warning: You are about to approve the additional loan amount.\nPlease make sure this is your desired action.\nYou cannot undo this action.',
                        ),
                        actions: [
                          AppWidgets.defaultFilledButton(
                            backgroundColor: AppColors.green1,
                            foregroundColor: AppColors.black,
                            child: const Text('Approve'),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .pop(true);
                            },
                          ),
                          AppWidgets.defaultFilledButton(
                            child: const Text('Cancel'),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .pop(false);
                            },
                          ),
                        ],
                      );
                    },
                  );

                  if (ok ?? false) {
                    if (context.mounted) {
                      context.read<AdditionalLoanBloc>().updateAdditionalLoanAmount(
                            loanId: loan.id,
                            additionalLoanAmountId: additionalLoan.id,
                            status: LoanStatus.approved,
                          );
                    }
                  }
                },
              ),
            ),
            const Gap(16),
            Expanded(
              child: AppWidgets.defaultFilledButton(
                foregroundColor: AppColors.red,
                child: const Text('Decline'),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Are you sure?'),
                        content: const Text(
                          'Warning: You are about to decline the additional loan amount.\nPlease make sure this is your desired action.\nYou cannot undo this action.',
                        ),
                        actions: [
                          AppWidgets.defaultFilledButton(
                            backgroundColor: AppColors.red,
                            foregroundColor: AppColors.black,
                            child: const Text('Decline'),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .pop(true);
                            },
                          ),
                          AppWidgets.defaultFilledButton(
                            child: const Text('Cancel'),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .pop(false);
                            },
                          ),
                        ],
                      );
                    },
                  );

                  if (ok ?? false) {
                    if (context.mounted) {
                      context.read<AdditionalLoanBloc>().updateAdditionalLoanAmount(
                            loanId: loan.id,
                            additionalLoanAmountId: additionalLoan.id,
                            status: LoanStatus.declined,
                          );
                    }
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
