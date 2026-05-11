import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_repository/user_repository.dart';

/// Hub screen for account verification. Shows the status of both email
/// and mobile-number verification. Tapping a card routes to the dedicated
/// verification flow for that identity.
class VerificationHubScreen extends StatelessWidget {
  const VerificationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;
    return BlocBuilder<AuthenticationBloc, AuthenticationState>(
      builder: (context, state) {
        final user = AuthenticationService.instance.user;
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final emailVerified = firebaseUser?.emailVerified ?? false;
        final mobileVerified = (user.verificationStatus &
                UserVerificationStatus.mobileNumberVerified.value) !=
            0;
        final emailCard = _VerificationCard(
          label: 'Email',
          value: firebaseUser?.email ?? '—',
          verified: emailVerified,
          onVerify: () => GoRouter.of(context).go(Paths.verifyEmail),
        );
        final mobileCard = _VerificationCard(
          label: 'Mobile number',
          value: user.mobileNumber,
          verified: mobileVerified,
          onVerify: () => GoRouter.of(context).go(Paths.mobileVerification),
        );
        final cards = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [emailCard, const Gap(16), mobileCard],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: emailCard),
                    const Gap(16),
                    Expanded(child: mobileCard),
                  ],
                ),
              );
        return Scaffold(
          appBar: AppBar(title: const Text('Verify your account')),
          body: AppWidgets.rootConstraints(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Please verify both your email and mobile number to '
                    'continue.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const Gap(24),
                  cards,
                  const Gap(24),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          context.read<AuthenticationBloc>().sigOut(),
                      child: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.label,
    required this.value,
    required this.verified,
    required this.onVerify,
  });

  final String label;
  final String value;
  final bool verified;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
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
            Text(value),
            if (!verified) ...[
              const Gap(12),
              AppWidgets.defaultFilledButton(
                onPressed: onVerify,
                child: const Text('Verify'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
