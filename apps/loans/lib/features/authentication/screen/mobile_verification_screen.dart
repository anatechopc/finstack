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
  bool _emailLinkSent = false;
  bool _refreshingEmail = false;
  bool _sendingEmailLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only auto-request a mobile OTP if mobile isn't already verified.
      final user = AuthenticationService.instance.user;
      final mobileVerified = (user.verificationStatus &
              UserVerificationStatus.mobileNumberVerified.value) !=
          0;
      if (!mobileVerified) {
        context.read<AuthenticationBloc>().requestOtp();
      }
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

  Future<void> _sendEmailVerification() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    setState(() => _sendingEmailLink = true);
    try {
      await firebaseUser.sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _emailLinkSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification email sent. Check your inbox.'),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send email: $err')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingEmailLink = false);
      }
    }
  }

  Future<void> _refreshEmailStatus() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    setState(() => _refreshingEmail = true);
    try {
      await firebaseUser.reload();
      if (!mounted) return;
      final refreshed = FirebaseAuth.instance.currentUser;
      final verified = refreshed?.emailVerified ?? false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? 'Email verified. Thanks!'
                : 'Email is not verified yet. Make sure you clicked the link.',
          ),
        ),
      );
      // Trigger a rebuild so the section updates.
      setState(() {});
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh: $err')),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingEmail = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        if (state.status == AuthenticationStateStatus.requestOtp &&
            state.canResendAt != null) {
          _startCountdown(state.canResendAt!);
        } else if (state.status == AuthenticationStateStatus.success) {
          // The router redirect re-evaluates and will route to dashboard
          // only if both email and mobile are verified — otherwise it
          // routes back here.
          GoRouter.of(context).go(
            SettingsService.instance.appUseClassicUI
                ? Paths.dashboard
                : Paths.index,
          );
        } else if (state.status == AuthenticationStateStatus.logout) {
          GoRouter.of(context).go(Paths.index);
        } else if (state.status == AuthenticationStateStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message ?? 'Something went wrong')),
          );
        }
      },
      builder: (context, state) {
        final user = AuthenticationService.instance.user;
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final emailVerified = firebaseUser?.emailVerified ?? false;
        final mobileVerified = (user.verificationStatus &
                UserVerificationStatus.mobileNumberVerified.value) !=
            0;
        final isLoading = _isBusy(state);
        debugPrint(
          '[mobile-verify] build: status=${state.status} isLoading=$isLoading '
          'emailVerified=$emailVerified mobileVerified=$mobileVerified',
        );
        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(title: const Text('Verify your account')),
              body: AppWidgets.rootConstraints(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _emailSection(
                        email: firebaseUser?.email ?? '—',
                        verified: emailVerified,
                        isBusy: isLoading,
                      ),
                      const Gap(16),
                      _mobileSection(
                        mobile: user.mobileNumber,
                        verified: mobileVerified,
                        isBusy: isLoading,
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

  Widget _emailSection({
    required String email,
    required bool verified,
    required bool isBusy,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Email',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (verified)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: AppColors.green1),
                      SizedBox(width: 4),
                      Text('Verified',
                          style: TextStyle(color: AppColors.green1)),
                    ],
                  ),
              ],
            ),
            const Gap(4),
            Text(email),
            if (!verified) ...[
              const Gap(12),
              if (_emailLinkSent)
                const Text(
                  'We sent a verification link to your email. Open it, click the link, then tap "I verified my email" below.',
                  style: TextStyle(fontSize: 12),
                )
              else
                const Text(
                  'Verify your email so we can keep your account secure.',
                  style: TextStyle(fontSize: 12),
                ),
              const Gap(12),
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultFilledButton(
                  onPressed: isBusy || _sendingEmailLink || _refreshingEmail
                      ? null
                      : _sendEmailVerification,
                  child: Text(_emailLinkSent
                      ? 'Resend verification email'
                      : 'Send verification email'),
                ),
              ),
              if (_emailLinkSent) ...[
                const Gap(8),
                SizedBox(
                  width: double.infinity,
                  child: AppWidgets.defaultFilledButton(
                    onPressed: isBusy || _refreshingEmail || _sendingEmailLink
                        ? null
                        : _refreshEmailStatus,
                    child: const Text('I verified my email'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _mobileSection({
    required String mobile,
    required bool verified,
    required bool isBusy,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Mobile number',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (verified)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: AppColors.green1),
                      SizedBox(width: 4),
                      Text('Verified',
                          style: TextStyle(color: AppColors.green1)),
                    ],
                  ),
              ],
            ),
            const Gap(4),
            Text(mobile),
            if (!verified) ...[
              const Gap(12),
              FormBuilder(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppWidgets.defaultFormBuilderTextField(
                      name: 'otp',
                      label: 'One-time pin',
                      enabled: !isBusy,
                      keyboardType: TextInputType.number,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                        FormBuilderValidators.minLength(6),
                      ]),
                    ),
                    const Gap(12),
                    AppWidgets.defaultFilledButton(
                      onPressed: isBusy || _remaining > Duration.zero
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
                    const Gap(8),
                    AppWidgets.defaultFilledButton(
                      onPressed: isBusy
                          ? null
                          : () {
                              if (_formKey.currentState?.saveAndValidate() ??
                                  false) {
                                final otp = _formKey.currentState!.value['otp']
                                    as String;
                                context
                                    .read<AuthenticationBloc>()
                                    .verifyOtp(otp);
                              }
                            },
                      child: const Text('Verify'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
