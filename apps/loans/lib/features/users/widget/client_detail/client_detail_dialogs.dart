import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/loans/screens/statement_of_account_screen.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// Shows the settle account dialog with the statement of account screen.
Future<void> showSettleAccountDialog(
  BuildContext context, {
  required String loanId,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.green1,
        content: SizedBox(
          width: 1100,
          height: 800,
          child: StatementOfAccountScreen(
            loanId: loanId,
          ),
        ),
      );
    },
  );
}

/// Shows the signature capture dialog and returns the signature bytes.
Future<Uint8List?> showSignatureDialog(
  BuildContext context,
) {
  final key = GlobalKey<FormBuilderState>(
    debugLabel: 'client_detail_signature_dialog',
  );

  return showDialog<Uint8List>(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: FormBuilder(
          key: key,
          child: Container(
            width: 500,
            height: 270,
            padding: const EdgeInsets.only(top: 14),
            child: FormBuilderSignaturePad(
              name: 'signature',
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.all(16),
                focusedBorder: OutlineInputBorder(
                  borderRadius: defaultBorderRadius,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: defaultBorderRadius,
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: defaultBorderRadius,
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: defaultBorderRadius,
                  borderSide: const BorderSide(
                    color: AppColors.red,
                  ),
                ),
                errorStyle: const TextStyle(
                  color: AppColors.red,
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: defaultBorderRadius,
                  borderSide: const BorderSide(
                    color: AppColors.red,
                  ),
                ),
                label: Text(
                  'Sign here',
                  style: GoogleFonts.urbanist(
                    color: AppColors.black,
                  ),
                ),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: const Text('Confirm signature'),
              onPressed: () {
                if (key.currentState!.saveAndValidate()) {
                  Navigator.of(context, rootNavigator: true).pop(
                    key.currentState!.value['signature'] as Uint8List,
                  );
                }
              },
            ),
          ),
        ],
      );
    },
  );
}

/// Shows the make payment dialog for a loan schedule.
Future<void> showMakePaymentDialog(
  BuildContext context, {
  required LoanSchedule schedule,
  required String userId,
}) {
  String? selectedPaymentOption;

  return showDialog(
    context: context,
    builder: (context) {
      final key = GlobalKey<FormBuilderState>(
        debugLabel: 'make_payment_dialog',
      );
      return AlertDialog(
        title: Text('Payment for ${schedule.dueAt.toDefaultDateFormat()}'),
        backgroundColor: AppColors.green1,
        content: FormBuilder(
          key: key,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              maxWidth: 500,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder(
                  stream: context
                      .read<CashPoolBloc>()
                      .loadCashPoolList2(userId),
                  builder: (context, snapshot) {
                    return BlocBuilder<CashPoolBloc, CashPoolState>(
                      builder: (context, state) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.black,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: BlocBuilder<CashPoolBloc, CashPoolState>(
                            builder: (context, state) {
                              final display = context
                                  .read<CashPoolBloc>()
                                  .cashPoolDisplay;

                              return Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cash pool balance',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                      color: AppColors.white,
                                    ),
                                  ),
                                  const Gap(8),
                                  const Spacer(),
                                  Text(
                                    display.balance.toCurrency(),
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
                const Gap(24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppWidgets.defaultFormBuilderTextField(
                        enabled: schedule.isOpenTerm,
                        initialValue: (schedule.isOpenTerm
                                ? schedule.amortization
                                : schedule.interestPayment)
                            .toStringAsFixed(2),
                        name: 'interest_payment',
                        label: 'Interest payment',
                        helperText: schedule.isOpenTerm
                            ? 'You can make a larger payment'
                            : null,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          (value) {
                            if (value == null) {
                              return null;
                            }

                            final tempParsed = double.parse(value);

                            if (tempParsed <= 0) {
                              return 'Amount should be greater than 0';
                            }

                            return null;
                          },
                        ]),
                        inputFormatters: [
                          AppWidgets.defaultCurrencyInputFormatter(),
                        ],
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: AppWidgets.defaultFormBuilderTextField(
                        initialValue:
                            schedule.principalPayment.toStringAsFixed(2),
                        name: 'principal_payment',
                        label: 'Principal payment',
                        helperText: 'You can make a larger payment',
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                        ]),
                        inputFormatters: [
                          AppWidgets.defaultCurrencyInputFormatter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              options: [
                ButtonOption(label: 'with Signature', value: 'signature'),
                // TODO(deibeeed): uncomment when mobile otp is enabled. https://github.com/anatechopc/loooans/issues/68
                // ButtonOptions(label: 'thru Mobile OTP', value: 'mobile-otp'),
                if (SettingsService.instance.forcePaymentConfirmation)
                  ButtonOption(label: 'forcefully', value: 'force'),
              ],
              onOptionSelected: (option) {
                selectedPaymentOption = option.value;
              },
              child: const Text('Confirm payment'),
              childText: 'Confirm payment',
              onPressed: () async {
                if (key.currentState?.saveAndValidate() ?? false) {
                  if (selectedPaymentOption == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a payment option'),
                      ),
                    );
                    return;
                  }

                  final interestPayment = double.parse(
                    key.currentState!.value['interest_payment'] as String,
                  );
                  final payment = double.parse(
                    key.currentState!.value['principal_payment'] as String,
                  );
                  final totalPayment = interestPayment + payment;

                  if (payment >= schedule.outstandingBalance) {
                    final settleAccountConfirmation =
                        await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text(
                            'Planning to settle your account?',
                          ),
                          content: const Text(
                            'The principal payment amount exceeds the outstanding balance.\nDo you wish to settle your account instead?',
                          ),
                          actions: [
                            AppWidgets.defaultFilledButton(
                              child: const Text('Settle account'),
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

                    if (settleAccountConfirmation ?? false) {
                      Navigator.of(context, rootNavigator: true).pop();
                      unawaited(
                        showSettleAccountDialog(
                          context,
                          loanId:
                              context.read<LoansBloc>().selectedLoan.id,
                        ),
                      );
                    }

                    return;
                  }

                  if (selectedPaymentOption == 'signature') {
                    final fileData =
                        await AppWidgets.defaultMediaChooserDialog(
                      context,
                      allowGallery: false,
                    );
                    if (fileData != null) {
                      try {
                        final fileName = fileData['name'] as String;
                        final fileBytes = fileData['bytes'] as Uint8List;
                        final signatureBytes =
                            await showSignatureDialog(context);
                        if (signatureBytes != null) {
                          final cashPoolDisplay =
                              context.read<CashPoolBloc>().cashPoolDisplay;
                          var reminderMessage = '';

                          if (totalPayment > cashPoolDisplay.balance) {
                            reminderMessage = '''
This payment exceeds the remaining balance in the cash pool. Please ensure that the excess amount is collected from the client.

By clicking 'Proceed,' you acknowledge that the excess payment will be received.''';
                          } else if (totalPayment ==
                              cashPoolDisplay.balance) {
                            reminderMessage = '''
The payment amount is equal to the remaining balance in the cash pool. The full payment will be deducted from the balance.

By clicking 'Proceed,' you acknowledge that the payment will be covered by the cash pool.''';
                          } else if (totalPayment <
                              cashPoolDisplay.balance) {
                            reminderMessage = '''
The payment amount is less than the remaining balance in the cash pool. The full payment will be deducted from the balance.

By clicking 'Proceed,' you acknowledge that the payment will be covered by the cash pool.''';
                          }

                          final answer = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: const Text(
                                  'Cash pool reminder',
                                ),
                                content: Text(reminderMessage),
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

                          if (answer ?? false) {
                            context.read<PaymentBloc>().makePayment(
                                  loan: context
                                      .read<LoansBloc>()
                                      .selectedLoan,
                                  schedule: schedule,
                                  interestPayment: key.currentState!
                                          .value['interest_payment']
                                      as String,
                                  payment: key.currentState!
                                      .value['principal_payment'] as String,
                                  fileBytes: fileBytes,
                                  fileName: fileName,
                                  signatureBytes: signatureBytes,
                                );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Please provide a signature'),
                            ),
                          );
                        }
                      } catch (err) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err.toString())),
                        );
                      }
                    }
                  } else if (selectedPaymentOption == 'mobile-otp') {
                    // something for mobile otp here
                  } else if (selectedPaymentOption == 'force') {
                    final answer = await showDialog<bool>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title:
                              const Text('High Risk Action: Read first!'),
                          content: const Text(
                            'You are about to forcefully make a payment. This action is irreversible and may cause discrepancies in the system. Please make sure that this is intended and the borrower has consent.\n\nNote: This action will not require a signature.',
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

                    if (answer ?? false) {
                      context.read<PaymentBloc>().makePayment(
                            loan: context
                                .read<LoansBloc>()
                                .selectedLoan,
                            schedule: schedule,
                            interestPayment: key.currentState!
                                .value['interest_payment'] as String,
                            payment: key.currentState!
                                .value['principal_payment'] as String,
                            force: true,
                          );
                    }
                  }

                  Navigator.of(context, rootNavigator: true).pop();
                }
              },
            ),
          ),
        ],
      );
    },
  );
}
