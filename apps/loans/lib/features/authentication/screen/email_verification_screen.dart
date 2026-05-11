import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_repository/user_repository.dart';

/// Dedicated email-verification screen. Sends the verification email
/// via FirebaseAuth, then offers a refresh button that reloads the user
/// and routes back to the hub once the email is verified.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _linkSent = false;
  bool _sending = false;
  bool _refreshing = false;

  Future<void> _sendEmail() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    setState(() => _sending = true);
    try {
      await firebaseUser.sendEmailVerification();
      if (!mounted) return;
      setState(() => _linkSent = true);
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
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;
    setState(() => _refreshing = true);
    try {
      await firebaseUser.reload();
      if (!mounted) return;
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verified. Thanks!')),
        );
        // Smart routing: if mobile is already verified too, send the user
        // straight to the app. Otherwise return to the hub so they can
        // start the mobile flow.
        final mobileVerified = (AuthenticationService.instance.user
                    .verificationStatus &
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email is not verified yet. Open the link in your inbox.',
            ),
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh: $err')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isBusy = _sending || _refreshing;
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Verify email'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => GoRouter.of(context).go(Paths.verify),
            ),
          ),
          body: AppWidgets.rootConstraints(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Email',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Gap(4),
                  Text(firebaseUser?.email ?? '—'),
                  const Gap(24),
                  if (_linkSent)
                    const Text(
                      'We sent a verification link to your email. Open it, '
                      "click the link, then tap \"I verified my email\" "
                      'below.',
                    )
                  else
                    const Text(
                      'Verify your email so we can keep your account secure.',
                    ),
                  const Gap(16),
                  AppWidgets.defaultFilledButton(
                    onPressed: isBusy ? null : _sendEmail,
                    child: Text(
                      _linkSent
                          ? 'Resend verification email'
                          : 'Send verification email',
                    ),
                  ),
                  if (_linkSent) ...[
                    const Gap(8),
                    AppWidgets.defaultFilledButton(
                      onPressed: isBusy ? null : _refresh,
                      child: const Text('I verified my email'),
                    ),
                  ],
                  const Gap(24),
                  Center(
                    child: TextButton(
                      onPressed: isBusy
                          ? null
                          : () =>
                              context.read<AuthenticationBloc>().sigOut(),
                      child: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isBusy)
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
  }
}
