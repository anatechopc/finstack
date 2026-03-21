import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/features/payment_center/widget/borrower_loan_section.dart';
import 'package:loooans/features/payment_center/widget/borrower_search_widget.dart';
import 'package:loooans/features/payment_center/widget/co_maker_loan_section.dart';
import 'package:loooans/features/payment_center/widget/payment_center_dialogs.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_dialogs.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_repository/product_repository.dart';

class PaymentCenterScreen extends StatelessWidget {
  const PaymentCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentCenterBloc, PaymentCenterState>(
      listener: (context, state) {
        if (state.status == PaymentCenterStatus.paymentLoading &&
            state.isLoading) {
          AppWidgets.showDefaultLoadingDialog(context);
        } else if (state.status == PaymentCenterStatus.paymentSuccess) {
          // Dismiss loading if shown
          Navigator.of(context, rootNavigator: true).maybePop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message ?? 'Payment successful'),
              backgroundColor: AppColors.green1_6,
            ),
          );
        } else if (state.status == PaymentCenterStatus.error &&
            state.message != null) {
          // Dismiss loading if shown
          Navigator.of(context, rootNavigator: true).maybePop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message!)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment Center'),
          backgroundColor: AppColors.green1,
          centerTitle: false,
        ),
        body: FormBuilder(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const BorrowerSearchWidget(),
                const Gap(16),
                Expanded(
                  child: BlocBuilder<PaymentCenterBloc, PaymentCenterState>(
                    builder: (context, state) {
                      if (state.isLoading &&
                          state.selectedBorrower == null) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              Gap(16),
                              Text(
                                'Loading borrower data...',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (state.selectedBorrower == null) {
                        return const Center(
                          child: Text(
                            'Search for a borrower to view their loans',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        );
                      }

                      return _BorrowerContent(state: state);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BorrowerContent extends StatelessWidget {
  const _BorrowerContent({required this.state});

  final PaymentCenterState state;

  @override
  Widget build(BuildContext context) {
    final borrower = state.selectedBorrower!;
    final isLoadingLoans = state.isLoading &&
        (state.status == PaymentCenterStatus.loading ||
            state.status == PaymentCenterStatus.borrowerSelected);

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Borrower info header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.green1.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.green1,
                  radius: 24,
                  child: Text(
                    borrower.initials,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        borrower.completeNameEasternOrder,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        borrower.mobileNumber,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    context
                        .read<PaymentCenterBloc>()
                        .add(const ClearBorrowerEvent());
                  },
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Clear selection',
                ),
              ],
            ),
          ),
          const Gap(24),

          // Section A: Borrower's Loans
          BorrowerLoanSection(
            loans: state.borrowerLoans,
            onPay: (group, schedule) {
              showPaymentCenterPaymentDialog(
                context,
                loan: group.loan,
                schedule: schedule,
                userId: borrower.id,
              );
            },
            onPayOverdue: (group, overdueSchedules) {
              showOverduePaymentDialog(
                context,
                loan: group.loan,
                overdueSchedules: overdueSchedules,
                userId: borrower.id,
              );
            },
            onNewLoan: () {
              context.read<UserBloc>().setUser(borrower);
              context.go(
                Paths.loansAction.replaceFirst(':action', Paths.actionCreate),
                extra: {'amount': 0.0, 'period': 0},
              );
            },
            onAddSpecialLoan: (group) {
              context.read<UserBloc>().setUser(borrower);
              AppWidgets.showAddUserWidget(
                context,
                withLoanApplication: true,
                allowAddOns: false,
              );
            },
            onAddAmount: (group) {
              // Select the loan in LoansBloc so AdditionalLoanBloc can use it
              context.read<LoansBloc>().selectLoan(group.loan.id);
              _showAdditionalAmountDialog(context, loan: group.loan);
            },
          ),
          const Gap(32),

          // Section B: Co-maker Loans
          CoMakerLoanSection(loans: state.coMakerLoans),
          const Gap(24),
        ],
      ),
    ),
    if (isLoadingLoans)
      Container(
        color: AppColors.black.withValues(alpha: 0.5),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.white),
              Gap(16),
              Text(
                'Loading loans...',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    );
  }
}

Future<void> _showAdditionalAmountDialog(
  BuildContext context, {
  required Loan loan,
}) async {
  // Fetch product for charge info
  Product? product;
  try {
    product = await context.read<ProductRepository>().get(id: loan.productId);
  } catch (_) {}

  if (!context.mounted) return;

  final confirmResult = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm Additional Loan'),
        content: const Text(
          'Are you sure you want to add an additional loan amount? '
          'This operation is irreversible. Please make sure that this '
          'is intended and the borrower has consent.\n\n'
          'Note: Adding an amount to the existing Open term loan will '
          'increase the principal borrowed by the borrower, which '
          'increases its interest as well.',
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            child: const Text('Proceed'),
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(true);
            },
          ),
          AppWidgets.defaultOutlinedButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop(false);
            },
          ),
        ],
      );
    },
  );

  if (confirmResult != true || !context.mounted) return;

  final formKey = GlobalKey<FormBuilderState>(
    debugLabel: 'payment_center_add_amount_dialog',
  );

  final result = await showDialog<dynamic>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Add loan amount'),
        content: FormBuilder(
          key: formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 350),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppWidgets.defaultFormBuilderTextField(
                  name: 'amount',
                  label: 'Add amount',
                  validator: FormBuilderValidators.required(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^[0-9]*[.]?[0-9]*'),
                    ),
                  ],
                ),
                if (product != null) ...[
                  const Gap(16),
                  for (final charge in product.additionalCharges)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add: ${charge.description}:'),
                        Text(
                          charge.isPercentage
                              ? '${charge.amount}%'
                              : '${charge.amount}',
                        ),
                      ],
                    ),
                  for (final charge in product.deductions)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Less: ${charge.description}:'),
                        Text(
                          charge.isPercentage
                              ? '${charge.amount}%'
                              : '${charge.amount}',
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            child: const Text('Add'),
            onPressed: () async {
              if (formKey.currentState?.saveAndValidate() ?? false) {
                // Capture selfie + signature
                final captureResult = await showDialog<dynamic>(
                  context: dialogContext,
                  builder: (captureContext) {
                    return AlertDialog(
                      title: const Text('Capture Required Information'),
                      content: const Text(
                        'Please capture a selfie and signature to '
                        'proceed with the additional loan.',
                      ),
                      actions: [
                        AppWidgets.defaultFilledButton(
                          child: const Text('Proceed'),
                          onPressed: () async {
                            final fileData =
                                await AppWidgets.defaultMediaChooserDialog(
                              captureContext,
                              allowGallery: false,
                            );
                            if (fileData != null) {
                              final fileName = fileData['name'] as String;
                              final fileBytes =
                                  fileData['bytes'] as Uint8List;
                              final signatureBytes =
                                  await showSignatureDialog(captureContext);
                              if (signatureBytes != null) {
                                Navigator.of(
                                  captureContext,
                                  rootNavigator: true,
                                ).pop({
                                  'selfie': SimpleFileData(
                                    fileName,
                                    fileBytes,
                                  ),
                                  'signature': signatureBytes,
                                });
                              }
                            }
                          },
                        ),
                        AppWidgets.defaultOutlinedButton(
                          child: const Text('Cancel'),
                          onPressed: () {
                            Navigator.of(
                              captureContext,
                              rootNavigator: true,
                            ).pop();
                          },
                        ),
                      ],
                    );
                  },
                );

                Navigator.of(dialogContext, rootNavigator: true)
                    .pop(captureResult);
              }
            },
          ),
          AppWidgets.defaultOutlinedButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
            },
          ),
        ],
      );
    },
  );

  if (result != null && context.mounted) {
    context.read<AdditionalLoanBloc>().addLoanAmount(
          loan.id,
          formKey.currentState!.value['amount'] as String,
          additionalCharges: product?.additionalCharges ?? [],
          deductions: product?.deductions ?? [],
          selfiePhoto: result['selfie'] as SimpleFileData,
          signatureBytes: result['signature'] as Uint8List,
        );
  }
}
