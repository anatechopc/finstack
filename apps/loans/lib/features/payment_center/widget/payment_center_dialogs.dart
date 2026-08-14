import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_dialogs.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/countdown_text.dart';

/// Shows the make payment dialog for the Payment Center.
/// Takes [Loan] directly instead of reading from LoansBloc.
Future<void> showPaymentCenterPaymentDialog(
  BuildContext context, {
  required Loan loan,
  required LoanSchedule schedule,
  required String userId,
}) {
  String? selectedPaymentOption;

  return showDialog(
    context: context,
    builder: (dialogContext) {
      final key = GlobalKey<FormBuilderState>(
        debugLabel: 'payment_center_payment_dialog',
      );
      return BlocProvider.value(
        value: context.read<PaymentCenterBloc>(),
        child: BlocProvider.value(
          value: context.read<CashPoolBloc>(),
          child: Builder(
            builder: (innerContext) {
              return AlertDialog(
                title: Text(
                  'Payment for ${schedule.dueAt.toDefaultDateFormat()}',
                ),
                backgroundColor: AppColors.green1,
                content: FormBuilder(
                  key: key,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder(
                          stream: innerContext
                              .read<CashPoolBloc>()
                              .loadCashPoolList2(userId),
                          builder: (context, snapshot) {
                            return BlocBuilder<CashPoolBloc, CashPoolState>(
                              builder: (context, state) {
                                final display = context
                                    .read<CashPoolBloc>()
                                    .cashPoolDisplay;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.black,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
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
                              child:
                                  AppWidgets.defaultFormBuilderTextField(
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
                                validator:
                                    FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  (value) {
                                    if (value == null) return null;
                                    final parsed = double.parse(value);
                                    if (parsed <= 0) {
                                      return 'Amount should be greater than 0';
                                    }
                                    return null;
                                  },
                                ]),
                                inputFormatters: [
                                  AppWidgets
                                      .defaultCurrencyInputFormatter(),
                                ],
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child:
                                  AppWidgets.defaultFormBuilderTextField(
                                initialValue: schedule.principalPayment
                                    .toStringAsFixed(2),
                                name: 'principal_payment',
                                label: 'Principal payment',
                                helperText: 'You can make a larger payment',
                                validator:
                                    FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                ]),
                                inputFormatters: [
                                  AppWidgets
                                      .defaultCurrencyInputFormatter(),
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
                        ButtonOption(
                          label: 'with Signature',
                          value: 'signature',
                        ),
                        ButtonOption(
                          label: 'thru Mobile OTP',
                          value: 'mobile-otp',
                        ),
                        if (SettingsService
                            .instance.forcePaymentConfirmation)
                          ButtonOption(
                            label: 'forcefully',
                            value: 'force',
                          ),
                      ],
                      onOptionSelected: (option) {
                        selectedPaymentOption = option.value;
                      },
                      child: const Text('Confirm payment'),
                      childText: 'Confirm payment',
                      onPressed: () async {
                        if (key.currentState?.saveAndValidate() ??
                            false) {
                          if (selectedPaymentOption == null) {
                            ScaffoldMessenger.of(innerContext)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select a payment option',
                                ),
                              ),
                            );
                            return;
                          }

                          await _handlePaymentOption(
                            innerContext,
                            key: key,
                            loan: loan,
                            schedule: schedule,
                            userId: userId,
                            selectedOption: selectedPaymentOption!,
                          );
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// Shows the overdue payment dialog for consolidated overdue schedules.
/// Pre-fills with summed interest/principal from all overdue schedules.
Future<void> showOverduePaymentDialog(
  BuildContext context, {
  required Loan loan,
  required List<LoanSchedule> overdueSchedules,
  required String userId,
}) {
  final isOpenTerm = overdueSchedules.first.isOpenTerm;
  final totalInterest = overdueSchedules.fold<double>(
    0,
    (sum, s) => sum + s.interestCharge,
  );
  final totalPrincipal = isOpenTerm
      ? 0.0
      : overdueSchedules.fold<double>(
          0,
          (sum, s) => sum + s.principalPayment,
        );

  String? selectedPaymentOption;

  return showDialog(
    context: context,
    builder: (dialogContext) {
      final key = GlobalKey<FormBuilderState>(
        debugLabel: 'overdue_payment_dialog',
      );
      return BlocProvider.value(
        value: context.read<PaymentCenterBloc>(),
        child: BlocProvider.value(
          value: context.read<CashPoolBloc>(),
          child: Builder(
            builder: (innerContext) {
              return AlertDialog(
                title: Text(
                  'Overdue Payment — '
                  '${overdueSchedules.length} '
                  '${overdueSchedules.length == 1 ? 'schedule' : 'schedules'}',
                ),
                backgroundColor: AppColors.green1,
                content: FormBuilder(
                  key: key,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder(
                          stream: innerContext
                              .read<CashPoolBloc>()
                              .loadCashPoolList2(userId),
                          builder: (context, snapshot) {
                            return BlocBuilder<CashPoolBloc, CashPoolState>(
                              builder: (context, state) {
                                final display = context
                                    .read<CashPoolBloc>()
                                    .cashPoolDisplay;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.black,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
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
                              child:
                                  AppWidgets.defaultFormBuilderTextField(
                                enabled: isOpenTerm,
                                initialValue:
                                    totalInterest.toStringAsFixed(2),
                                name: 'interest_payment',
                                label: 'Total interest',
                                helperText: isOpenTerm
                                    ? 'You can make a larger payment'
                                    : null,
                                validator:
                                    FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                  (value) {
                                    if (value == null) return null;
                                    final parsed = double.parse(value);
                                    if (parsed <= 0) {
                                      return 'Amount should be greater than 0';
                                    }
                                    return null;
                                  },
                                ]),
                                inputFormatters: [
                                  AppWidgets
                                      .defaultCurrencyInputFormatter(),
                                ],
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child:
                                  AppWidgets.defaultFormBuilderTextField(
                                initialValue:
                                    totalPrincipal.toStringAsFixed(2),
                                name: 'principal_payment',
                                label: 'Total principal',
                                helperText: 'You can make a larger payment',
                                validator:
                                    FormBuilderValidators.compose([
                                  FormBuilderValidators.required(),
                                ]),
                                inputFormatters: [
                                  AppWidgets
                                      .defaultCurrencyInputFormatter(),
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
                        ButtonOption(
                          label: 'with Signature',
                          value: 'signature',
                        ),
                        ButtonOption(
                          label: 'thru Mobile OTP',
                          value: 'mobile-otp',
                        ),
                        if (SettingsService
                            .instance.forcePaymentConfirmation)
                          ButtonOption(
                            label: 'forcefully',
                            value: 'force',
                          ),
                      ],
                      onOptionSelected: (option) {
                        selectedPaymentOption = option.value;
                      },
                      child: const Text('Confirm payment'),
                      childText: 'Confirm payment',
                      onPressed: () async {
                        if (key.currentState?.saveAndValidate() ??
                            false) {
                          if (selectedPaymentOption == null) {
                            ScaffoldMessenger.of(innerContext)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select a payment option',
                                ),
                              ),
                            );
                            return;
                          }

                          await _handleOverduePaymentOption(
                            innerContext,
                            key: key,
                            loan: loan,
                            overdueSchedules: overdueSchedules,
                            userId: userId,
                            selectedOption: selectedPaymentOption!,
                          );
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> _handleOverduePaymentOption(
  BuildContext context, {
  required GlobalKey<FormBuilderState> key,
  required Loan loan,
  required List<LoanSchedule> overdueSchedules,
  required String userId,
  required String selectedOption,
}) async {
  final interestPayment = double.parse(
    key.currentState!.value['interest_payment'] as String,
  );
  final principalPayment = double.parse(
    key.currentState!.value['principal_payment'] as String,
  );
  final totalPayment = interestPayment + principalPayment;

  if (selectedOption == 'signature') {
    final fileData = await AppWidgets.defaultMediaChooserDialog(
      context,
      allowGallery: false,
    );
    if (fileData == null) return;

    try {
      final fileName = fileData['name'] as String;
      final fileBytes = fileData['bytes'] as Uint8List;
      final signatureBytes = await showSignatureDialog(context);
      if (signatureBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please provide a signature')),
        );
        return;
      }

      final proceed = await _showCashPoolReminder(context, totalPayment);
      if (proceed != true) return;

      context.read<PaymentCenterBloc>().makeOverduePayment(
            loan: loan,
            schedules: overdueSchedules,
            totalInterestPayment:
                key.currentState!.value['interest_payment'] as String,
            totalPrincipalPayment:
                key.currentState!.value['principal_payment'] as String,
            fileBytes: fileBytes,
            fileName: fileName,
            signatureBytes: signatureBytes,
          );
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  } else if (selectedOption == 'mobile-otp') {
    final result = await showPaymentCenterOtpDialog(
      context,
      borrowerUserId: userId,
    );
    if (result == null || result['verified'] != true) return;

    final proceed = await _showCashPoolReminder(context, totalPayment);
    if (proceed != true) return;

    context.read<PaymentCenterBloc>().makeOverduePayment(
          loan: loan,
          schedules: overdueSchedules,
          totalInterestPayment:
              key.currentState!.value['interest_payment'] as String,
          totalPrincipalPayment:
              key.currentState!.value['principal_payment'] as String,
          otpVerified: true,
        );
  } else if (selectedOption == 'force') {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('High Risk Action: Read first!'),
          content: const Text(
            'You are about to forcefully make a payment for all overdue '
            'schedules. This action is irreversible and may cause '
            'discrepancies in the system. Please make sure that this is '
            'intended and the borrower has consent.\n\n'
            'Note: This action will not require a signature.',
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

    if (answer != true) return;

    context.read<PaymentCenterBloc>().makeOverduePayment(
          loan: loan,
          schedules: overdueSchedules,
          totalInterestPayment:
              key.currentState!.value['interest_payment'] as String,
          totalPrincipalPayment:
              key.currentState!.value['principal_payment'] as String,
          force: true,
        );
  }

  Navigator.of(context, rootNavigator: true).pop();
}

Future<void> _handlePaymentOption(
  BuildContext context, {
  required GlobalKey<FormBuilderState> key,
  required Loan loan,
  required LoanSchedule schedule,
  required String userId,
  required String selectedOption,
}) async {
  final interestPayment = double.parse(
    key.currentState!.value['interest_payment'] as String,
  );
  final payment = double.parse(
    key.currentState!.value['principal_payment'] as String,
  );
  final totalPayment = interestPayment + payment;

  // Check if settling account
  if (payment >= schedule.outstandingBalance) {
    final settleAccountConfirmation = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Planning to settle your account?'),
          content: const Text(
            'The principal payment amount exceeds the outstanding balance.\n'
            'Do you wish to settle your account instead?',
          ),
          actions: [
            AppWidgets.defaultFilledButton(
              child: const Text('Settle account'),
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

    if (settleAccountConfirmation ?? false) {
      Navigator.of(context, rootNavigator: true).pop();
      unawaited(showSettleAccountDialog(context, loanId: loan.id));
    }
    return;
  }

  if (selectedOption == 'signature') {
    await _handleSignaturePayment(
      context,
      key: key,
      loan: loan,
      schedule: schedule,
      totalPayment: totalPayment,
    );
  } else if (selectedOption == 'mobile-otp') {
    await _handleOtpPayment(
      context,
      key: key,
      loan: loan,
      schedule: schedule,
      userId: userId,
      totalPayment: totalPayment,
    );
  } else if (selectedOption == 'force') {
    await _handleForcePayment(
      context,
      key: key,
      loan: loan,
      schedule: schedule,
    );
  }

  Navigator.of(context, rootNavigator: true).pop();
}

Future<void> _handleSignaturePayment(
  BuildContext context, {
  required GlobalKey<FormBuilderState> key,
  required Loan loan,
  required LoanSchedule schedule,
  required double totalPayment,
}) async {
  final fileData = await AppWidgets.defaultMediaChooserDialog(
    context,
    allowGallery: false,
  );

  if (fileData == null) return;

  try {
    final fileName = fileData['name'] as String;
    final fileBytes = fileData['bytes'] as Uint8List;
    final signatureBytes = await showSignatureDialog(context);

    if (signatureBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a signature')),
      );
      return;
    }

    final proceed = await _showCashPoolReminder(context, totalPayment);
    if (proceed != true) return;

    context.read<PaymentCenterBloc>().makePayment(
          loan: loan,
          schedule: schedule,
          interestPayment:
              key.currentState!.value['interest_payment'] as String,
          payment:
              key.currentState!.value['principal_payment'] as String,
          fileBytes: fileBytes,
          fileName: fileName,
          signatureBytes: signatureBytes,
        );
  } catch (err) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err.toString())),
    );
  }
}

Future<void> _handleOtpPayment(
  BuildContext context, {
  required GlobalKey<FormBuilderState> key,
  required Loan loan,
  required LoanSchedule schedule,
  required String userId,
  required double totalPayment,
}) async {
  final result = await showPaymentCenterOtpDialog(
    context,
    borrowerUserId: userId,
  );

  if (result == null || result['verified'] != true) return;

  final proceed = await _showCashPoolReminder(context, totalPayment);
  if (proceed != true) return;

  context.read<PaymentCenterBloc>().makePayment(
        loan: loan,
        schedule: schedule,
        interestPayment:
            key.currentState!.value['interest_payment'] as String,
        payment:
            key.currentState!.value['principal_payment'] as String,
        otpVerified: true,
      );
}

Future<void> _handleForcePayment(
  BuildContext context, {
  required GlobalKey<FormBuilderState> key,
  required Loan loan,
  required LoanSchedule schedule,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('High Risk Action: Read first!'),
        content: const Text(
          'You are about to forcefully make a payment. This action is '
          'irreversible and may cause discrepancies in the system. Please '
          'make sure that this is intended and the borrower has consent.\n\n'
          'Note: This action will not require a signature.',
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

  if (answer != true) return;

  context.read<PaymentCenterBloc>().makePayment(
        loan: loan,
        schedule: schedule,
        interestPayment:
            key.currentState!.value['interest_payment'] as String,
        payment:
            key.currentState!.value['principal_payment'] as String,
        force: true,
      );
}

Future<bool?> _showCashPoolReminder(
  BuildContext context,
  double totalPayment,
) async {
  final cashPoolDisplay = context.read<CashPoolBloc>().cashPoolDisplay;
  var reminderMessage = '';

  if (totalPayment > cashPoolDisplay.balance) {
    reminderMessage = 'This payment exceeds the remaining balance in the '
        'cash pool. Please ensure that the excess amount is collected '
        "from the client.\n\nBy clicking 'Proceed,' you acknowledge "
        'that the excess payment will be received.';
  } else if (totalPayment == cashPoolDisplay.balance) {
    reminderMessage = 'The payment amount is equal to the remaining '
        'balance in the cash pool. The full payment will be deducted '
        "from the balance.\n\nBy clicking 'Proceed,' you acknowledge "
        'that the payment will be covered by the cash pool.';
  } else {
    reminderMessage = 'The payment amount is less than the remaining '
        'balance in the cash pool. The full payment will be deducted '
        "from the balance.\n\nBy clicking 'Proceed,' you acknowledge "
        'that the payment will be covered by the cash pool.';
  }

  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Cash pool reminder'),
        content: Text(reminderMessage),
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
}

/// Shows the OTP dialog for Payment Center.
/// Uses PaymentCenterBloc instead of PaymentBloc.
Future<Map<String, dynamic>?> showPaymentCenterOtpDialog(
  BuildContext context, {
  required String borrowerUserId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: context.read<PaymentCenterBloc>(),
        child: _PaymentCenterOtpDialog(borrowerUserId: borrowerUserId),
      );
    },
  );
}

class _PaymentCenterOtpDialog extends StatefulWidget {
  const _PaymentCenterOtpDialog({required this.borrowerUserId});
  final String borrowerUserId;

  @override
  State<_PaymentCenterOtpDialog> createState() =>
      _PaymentCenterOtpDialogState();
}

class _PaymentCenterOtpDialogState
    extends State<_PaymentCenterOtpDialog> {
  final _otpController = TextEditingController();
  String? _token;
  int? _expireAt;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentCenterBloc>().add(
            RequestOtpEvent(borrowerUserId: widget.borrowerUserId),
          );
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _onResend() {
    setState(() {
      _isExpired = false;
    });
    context.read<PaymentCenterBloc>().add(
          RequestOtpEvent(borrowerUserId: widget.borrowerUserId),
        );
  }

  void _onVerify() {
    if (_otpController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 6-digit OTP')),
      );
      return;
    }
    if (_token == null) return;
    context.read<PaymentCenterBloc>().add(
          VerifyOtpEvent(token: _token!, otp: _otpController.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentCenterBloc, PaymentCenterState>(
      listener: (context, state) {
        if (state.status == PaymentCenterStatus.otpRequested) {
          setState(() {
            _token = state.otpToken;
            _expireAt = state.otpExpireAt;
            _isExpired = false;
          });
        } else if (state.status == PaymentCenterStatus.otpVerified) {
          Navigator.of(context, rootNavigator: true).pop(
            {'verified': true, 'token': _token},
          );
        } else if (state.status == PaymentCenterStatus.otpError) {
          // otpError, not error: the screen-level listener pops the topmost
          // root route on error, which here is this dialog. Recoverable OTP
          // failures must leave the dialog open so the user can resend or
          // retype the code.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.message ?? 'OTP verification failed',
              ),
            ),
          );
        }
      },
      child: BlocBuilder<PaymentCenterBloc, PaymentCenterState>(
        builder: (context, state) {
          final isLoading = state.status ==
                  PaymentCenterStatus.otpLoading &&
              state.isLoading;

          return AlertDialog(
            title: const Text('Payment OTP Verification'),
            backgroundColor: AppColors.green1,
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading && _token == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          Gap(16),
                          Text('Sending OTP to borrower...'),
                        ],
                      ),
                    )
                  else if (_token != null) ...[
                    const Text(
                      "An OTP has been sent to the borrower's mobile "
                      'number. Please ask the borrower to provide '
                      'the code.',
                    ),
                    const Gap(16),
                    if (_expireAt != null)
                      CountdownText(
                        expireAt: DateTime.fromMillisecondsSinceEpoch(
                          _expireAt!,
                        ),
                      ),
                    const Gap(16),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 8,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        hintText: '000000',
                        counterText: '',
                      ),
                    ),
                    const Gap(16),
                    if (_isExpired)
                      TextButton(
                        onPressed: _onResend,
                        child: const Text('Resend OTP'),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              if (_token != null && !isLoading)
                SizedBox(
                  width: double.infinity,
                  child: AppWidgets.defaultFilledButton(
                    onPressed: _onVerify,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text('Verify OTP'),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultOutlinedButton(
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
