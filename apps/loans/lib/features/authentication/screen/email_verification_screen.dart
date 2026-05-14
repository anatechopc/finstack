import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_repository/user_repository.dart';

/// Email verification leaf — symmetric with [MobileVerificationScreen].
///
/// Flow: on mount, requests an OTP via the email channel (backend writes the
/// OTP to RTDB and sends a branded email via Microsoft Graph). The user types
/// the 6-digit code from their inbox; on Verify, the backend marks the
/// FirebaseAuth user's emailVerified flag via Admin SDK. The bloc reloads
/// FirebaseUser so the local cache picks up the new flag, then the screen
/// smart-routes to dashboard (if mobile is also verified) or back to the hub.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthenticationBloc>().requestOtp(purpose: 'email');
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

  bool _isBusy(AuthenticationState state) {
    return state.status == AuthenticationStateStatus.loading && state.isLoading;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        if (state.status == AuthenticationStateStatus.requestOtp &&
            state.canResendAt != null) {
          _startCountdown(state.canResendAt!);
        } else if (state.status == AuthenticationStateStatus.success) {
          // Smart routing: bloc already reloaded the FirebaseUser so
          // emailVerified is fresh. If mobile is also verified, go
          // straight to the app; otherwise return to the hub.
          final user = AuthenticationService.instance.user;
          final mobileVerified = (user.verificationStatus &
                  UserVerificationStatus.mobileNumberVerified.value) !=
              0;
          if (mobileVerified) {
            GoRouter.of(context).go(
              SettingsService.instance.appUseClassicUI
                  ? Paths.dashboard
                  : Paths.index,
            );
          } else {
            GoRouter.of(context).go(Paths.verify);
          }
        } else if (state.status == AuthenticationStateStatus.logout) {
          GoRouter.of(context).go(Paths.index);
        } else if (state.status == AuthenticationStateStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message ?? 'Something went wrong')),
          );
        }
      },
      builder: (context, state) {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final isLoading = _isBusy(state);
        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text('Verify email'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: isLoading
                      ? null
                      : () => GoRouter.of(context).go(Paths.verify),
                ),
              ),
              body: AppWidgets.rootConstraints(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: FormBuilder(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Gap(4),
                        Text(firebaseUser?.email ?? '—'),
                        const Gap(24),
                        AppWidgets.defaultFormBuilderTextField(
                          name: 'otp',
                          label: 'One-time pin',
                          enabled: !isLoading,
                          keyboardType: TextInputType.number,
                          validator: FormBuilderValidators.compose([
                            FormBuilderValidators.required(),
                            FormBuilderValidators.minLength(6),
                          ]),
                        ),
                        const Gap(12),
                        AppWidgets.defaultFilledButton(
                          onPressed: isLoading || _remaining > Duration.zero
                              ? null
                              : () => context
                                  .read<AuthenticationBloc>()
                                  .requestOtp(purpose: 'email'),
                          child: Text(
                            _remaining > Duration.zero
                                ? 'Resend in ${_formatRemaining(_remaining)}'
                                : 'Send code',
                          ),
                        ),
                        const Gap(8),
                        AppWidgets.defaultFilledButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  if (_formKey.currentState
                                          ?.saveAndValidate() ??
                                      false) {
                                    final otp = _formKey
                                        .currentState!.value['otp'] as String;
                                    context
                                        .read<AuthenticationBloc>()
                                        .verifyOtp(otp);
                                  }
                                },
                          child: const Text('Verify'),
                        ),
                        const Gap(24),
                        Center(
                          child: TextButton(
                            onPressed: isLoading
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
              ),
            ),
            if (isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x99000000),
                  child: Center(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        color: AppColors.green1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
