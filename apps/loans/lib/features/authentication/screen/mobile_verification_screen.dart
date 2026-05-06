import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/widgets/app_widgets.dart';

class MobileVerificationScreen extends StatefulWidget {
  const MobileVerificationScreen({super.key});

  @override
  State<MobileVerificationScreen> createState() =>
      _MobileVerificationScreenState();
}

class _MobileVerificationScreenState extends State<MobileVerificationScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthenticationBloc>().requestOtp();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime canResendAt) {
    _ticker?.cancel();
    void tick() {
      if (!mounted) return;
      final now = DateTime.now();
      final remaining = canResendAt.difference(now);
      setState(() {
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      });
      if (_remaining == Duration.zero) {
        _ticker?.cancel();
      }
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        if (state.status == AuthenticationStateStatus.loading) {
          if (mounted) {
            setState(() => _isLoading = state.isLoading);
          }
        } else if (state.status == AuthenticationStateStatus.requestOtp &&
            state.canResendAt != null) {
          _startCountdown(state.canResendAt!);
        } else if (state.status == AuthenticationStateStatus.success) {
          GoRouter.of(context).go(
            SettingsService.instance.appUseClassicUI
                ? Paths.dashboard
                : Paths.index,
          );
        } else if (state.status == AuthenticationStateStatus.logout) {
          GoRouter.of(context).go(Paths.index);
        } else if (state.status == AuthenticationStateStatus.error) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message ?? 'Something went wrong')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Verify mobile number')),
        body: AppWidgets.rootConstraints(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: FormBuilder(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile: ${AuthenticationService.instance.user.mobileNumber}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const Gap(24),
                      AppWidgets.defaultFormBuilderTextField(
                        name: 'otp',
                        label: 'One-time pin',
                        enabled: !_isLoading,
                        keyboardType: TextInputType.number,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(),
                          FormBuilderValidators.minLength(6),
                        ]),
                      ),
                      const Gap(16),
                      SizedBox(
                        width: double.infinity,
                        child: AppWidgets.defaultFilledButton(
                          onPressed:
                              _isLoading || _remaining > Duration.zero
                                  ? null
                                  : () => context
                                      .read<AuthenticationBloc>()
                                      .requestOtp(),
                          child: Text(
                            _remaining > Duration.zero
                                ? 'Resend in ${_formatRemaining(_remaining)}'
                                : 'Send OTP',
                          ),
                        ),
                      ),
                      const Gap(16),
                      SizedBox(
                        width: double.infinity,
                        child: AppWidgets.defaultFilledButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_formKey.currentState?.saveAndValidate() ??
                                      false) {
                                    final otp = _formKey.currentState!
                                        .value['otp'] as String;
                                    context
                                        .read<AuthenticationBloc>()
                                        .verifyOtp(otp);
                                  }
                                },
                          child: const Text('Verify'),
                        ),
                      ),
                      const Gap(16),
                      Center(
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => context
                                  .read<AuthenticationBloc>()
                                  .sigOut(),
                          child: const Text('Log out'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x99000000),
                    child: Center(
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
