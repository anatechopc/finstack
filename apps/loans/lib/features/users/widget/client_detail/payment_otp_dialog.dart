import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/countdown_text.dart';

/// Shows the payment OTP verification dialog.
/// Returns a map with {'verified': true, 'token': token} on success,
/// or null if dismissed.
Future<Map<String, dynamic>?> showPaymentOtpDialog(
  BuildContext context, {
  required String borrowerUserId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: context.read<PaymentBloc>(),
        child: _PaymentOtpDialog(borrowerUserId: borrowerUserId),
      );
    },
  );
}

class _PaymentOtpDialog extends StatefulWidget {
  const _PaymentOtpDialog({required this.borrowerUserId});
  final String borrowerUserId;

  @override
  State<_PaymentOtpDialog> createState() => _PaymentOtpDialogState();
}

class _PaymentOtpDialogState extends State<_PaymentOtpDialog> {
  final _otpController = TextEditingController();
  String? _token;
  int? _expireAt;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentBloc>().add(
            RequestPaymentOtpEvent(borrowerUserId: widget.borrowerUserId),
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
    context.read<PaymentBloc>().add(
          RequestPaymentOtpEvent(borrowerUserId: widget.borrowerUserId),
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
    context.read<PaymentBloc>().add(
          VerifyPaymentOtpEvent(token: _token!, otp: _otpController.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentBloc, PaymentState>(
      listener: (context, state) {
        if (state.status == PaymentStatus.otpRequested) {
          setState(() {
            _token = state.token;
            _expireAt = state.expireAt;
            _isExpired = false;
          });
        } else if (state.status == PaymentStatus.otpVerified) {
          Navigator.of(context, rootNavigator: true).pop(
            {'verified': true, 'token': _token},
          );
        } else if (state.status == PaymentStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message ?? 'OTP verification failed')),
          );
        }
      },
      child: BlocBuilder<PaymentBloc, PaymentState>(
        builder: (context, state) {
          final isLoading =
              state.status == PaymentStatus.loading && state.isLoading;

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
                      "An OTP has been sent to the borrower's mobile number. "
                      'Please ask the borrower to provide the code.',
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
