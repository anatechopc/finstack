import 'dart:async';

import 'package:chat_repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/chat/chat_participants.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/requirement_temp_container.dart';
import 'package:loooans/features/users/screens/additional_loan_docs_dialog.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_dialogs.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_repository/user_repository.dart';

class ClientDetailActionButtons extends StatelessWidget {
  const ClientDetailActionButtons({
    required this.userId,
    super.key,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final loan = context.read<LoansBloc>().selectedLoan;
        final product = context.read<ProductBloc>().selectedProduct;

        return Row(
          children: [
            if (loan.status == LoanStatus.pending &&
                [
                  UserRole.loanOfficer,
                  UserRole.admin,
                ].contains(
                  AuthenticationService.instance.user.userRole,
                )) ...[
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
                            'Warning: You are about to approve the loan.\nPlease make sure this is your desired action.\nYou cannot undo this action.',
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
                        context.read<LoansBloc>().updateLoanStatus(
                              status: LoanStatus.approved,
                              loan: loan,
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
                            'Warning: You are about to decline the loan.\nPlease make sure this is your desired action.\nYou cannot undo this action.',
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
                      context.read<LoansBloc>().updateLoanStatus(
                            status: LoanStatus.declined,
                            loan: loan,
                          );
                    }
                  },
                ),
              ),
            ] else ...[
              Expanded(
                child: AppWidgets.defaultOutlinedButton(
                  child: const Text('Message borrower'),
                  onPressed: () => _openBorrowerChat(context),
                ),
              ),
              const Gap(16),
              if (AuthenticationService.instance.allowAddClients &&
                  loan.dueAt == null &&
                  (AuthenticationService.instance.user.isTeller() ||
                      AuthenticationService.instance.user.isAdmin())) ...[
                if (SettingsService.instance.enableProductAddOns) ...[
                  Expanded(
                    child: AppWidgets.defaultOutlinedButton(
                      child: const Text('Add special loan'),
                      onPressed: () {
                        AppWidgets.showAddUserWidget(
                          context,
                          withLoanApplication: true,
                          allowAddOns: false,
                        );
                      },
                    ),
                  ),
                  const Gap(16),
                ],
                Expanded(
                  child: AppWidgets.defaultOutlinedButton(
                    child: const Text('Additional loan'),
                    onPressed: () async {
                      await _handleAdditionalLoan(
                        context,
                        loan: loan,
                        product: product,
                      );
                    },
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: AppWidgets.defaultOutlinedButton(
                    child: const Text(
                      'Settle now',
                    ),
                    onPressed: () {
                      showSettleAccountDialog(
                        context,
                        loanId: context.read<LoansBloc>().selectedLoan.id,
                      );
                    },
                  ),
                ),
                const Gap(16),
              ],
              Expanded(
                child: AppWidgets.defaultFilledButton(
                  foregroundColor: AppColors.green1,
                  child: const Text('Close'),
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openBorrowerChat(BuildContext context) async {
    final me = AuthenticationService.instance;
    final loansBloc = context.read<LoansBloc>();
    final loan = loansBloc.selectedLoan;
    final seed = ChatParticipants.staffToBorrower(
      companyId: me.company.id,
      companyName: me.company.name,
      companyPhotoUrl: me.company.companyProfilePhotoUrl?.url,
      borrowerId: userId,
      borrowerName: loansBloc.selectedUserLoanView?.userFullName ?? '',
      borrowerPhotoUrl: null,
      contextType: 'loan',
      contextId: loan.id,
      contextLabel: loansBloc.selectedUserLoanView?.loanType,
    );
    final room = await context.read<ChatRoomRepository>().findOrCreate(
          participants: seed.participants,
          createdBy: me.user.id,
          contextType: seed.contextType,
          contextId: seed.contextId,
          contextLabel: seed.contextLabel,
        );
    if (!context.mounted) return;
    GoRouter.of(context).go(Paths.chatRoom.replaceFirst(':roomId', room.id));
  }

  Future<void> _handleAdditionalLoan(
    BuildContext context, {
    required Loan loan,
    required Product? product,
  }) async {
    // Show confirmation dialog first
    final confirmResult = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Additional Loan'),
          content: const Text(
            'Are you sure you want to add an additional loan amount? This operation is irreversible. Please make sure that this is intended and the borrower has consent.\n\nNote: Adding an amount to the existing Open term loan will increase the principal borrowed by the borrower, which increases its interest as well.',
          ),
          actions: [
            AppWidgets.defaultFilledButton(
              child: const Text('Proceed'),
              onPressed: () {
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pop(true);
              },
            ),
            AppWidgets.defaultOutlinedButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pop(false);
              },
            ),
          ],
        );
      },
    );

    // Only proceed if user confirmed
    if (true == confirmResult) {
      final formKey = GlobalKey<FormBuilderState>(
        debugLabel: 'loan_client_add_amount_dialog',
      );
      final result = await showDialog<dynamic>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Add loan amount'),
            content: FormBuilder(
              key: formKey,
              onChanged: () {
                context.read<ProductBloc>().refresh();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 350),
                child: BlocBuilder<ProductBloc, ProductState>(
                  buildWhen: (prev, next) {
                    return next.status == ProductStatus.refresh;
                  },
                  builder: (context, state) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppWidgets.defaultFormBuilderTextField(
                          name: 'amount',
                          label: 'Add amount',
                          validator: FormBuilderValidators.required(),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(
                                '^[0-9]*[.]?[0-9]*',
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        for (final charge in product!.additionalCharges)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Add: ${charge.description}:',
                                style: const TextStyle(
                                  color: AppColors.black,
                                ),
                              ),
                              Text(
                                "${charge.isPercentage ? '${charge.amount}%' : charge.amount}",
                              ),
                            ],
                          ),
                        for (final charge in product.deductions)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Less: ${charge.description}:',
                                style: const TextStyle(
                                  color: AppColors.black,
                                ),
                              ),
                              Text(
                                "${charge.isPercentage ? '${charge.amount}%' : charge.amount}",
                              ),
                            ],
                          ),
                        const Divider(
                          color: AppColors.black,
                        ),
                        const Gap(8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total:'),
                            Text(
                              context
                                  .read<ProductBloc>()
                                  .computeTotalAdditionalLoanAmount(
                                    product,
                                    formKey.currentState
                                            ?.simplifiedFields()['amount']
                                        as String?,
                                  )
                                  .toCurrency(),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            actions: [
              AppWidgets.defaultFilledButton(
                child: const Text('Add'),
                onPressed: () async {
                  if (formKey.currentState?.saveAndValidate() ?? false) {
                    final result = await showDialog<dynamic>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text(
                            'Capture Required Information',
                          ),
                          content: const Text(
                            'Please capture a selfie and signature to proceed with the additional loan.',
                          ),
                          actions: [
                            AppWidgets.defaultFilledButton(
                              child: const Text('Proceed'),
                              onPressed: () async {
                                final fileData =
                                    await AppWidgets.defaultMediaChooserDialog(
                                  context,
                                  allowGallery: false,
                                );
                                if (fileData != null) {
                                  try {
                                    final fileName = fileData['name'] as String;
                                    final fileBytes =
                                        fileData['bytes'] as Uint8List;
                                    final signatureBytes =
                                        await showSignatureDialog(
                                      context,
                                    );
                                    if (signatureBytes != null) {
                                      Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).pop({
                                        'selfie': SimpleFileData(
                                          fileName,
                                          fileBytes,
                                        ),
                                        'signature': signatureBytes,
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please provide a signature',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (err) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          err.toString(),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            AppWidgets.defaultOutlinedButton(
                              child: const Text('Cancel'),
                              onPressed: () {
                                Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );

                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(result);
                  }
                },
              ),
              AppWidgets.defaultOutlinedButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop();
                },
              ),
            ],
          );
        },
      );

      if (result != null) {
        // process add amount here
        context.read<AdditionalLoanBloc>().addLoanAmount(
              loan.id,
              formKey.currentState!.value['amount'] as String,
              additionalCharges: product?.additionalCharges ?? [],
              deductions: product?.deductions ?? [],
              selfiePhoto: result['selfie'] as SimpleFileData,
              signatureBytes: result['signature'] as Uint8List,
            );

        // Get additional loan documents from the selected product
        if (product != null && product.additionalLoanDocs.isNotEmpty) {
          unawaited(
            showAdditionalLoanDocsDialog(
              context,
              product.additionalLoanDocs,
            ),
          );
        } else {
          // Fallback to mock documents if product is null
          // or has no additional loan docs
          final mockDocuments = [
            FileUrl(
              name: 'Loan Agreement.pdf',
              url: 'https://example.com/loan_agreement.pdf',
            ),
            FileUrl(
              name: 'Terms and Conditions.pdf',
              url: 'https://example.com/terms_and_conditions.pdf',
            ),
            FileUrl(
              name: 'Payment Schedule.pdf',
              url: 'https://example.com/payment_schedule.pdf',
            ),
          ];
          unawaited(
            showAdditionalLoanDocsDialog(
              context,
              mockDocuments,
            ),
          );
        }
      }
    }
  }
}
