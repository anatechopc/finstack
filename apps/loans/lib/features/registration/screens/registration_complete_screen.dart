import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class RegistrationCompleteScreen extends StatelessWidget {
  const RegistrationCompleteScreen({
    super.key,
    this.isInitial = true,
    this.isProvider = false,
  });

  final bool isInitial;
  final bool isProvider;

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 341),
      child: Text(
        isInitial ? 'Initial registration complete' : 'Registration Complete',
        style: const TextStyle(
          fontSize: 48,
        ),
      ),
    );

    final text2 = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 482),
      child: Text(
        _getMessage(),
      ),
    );

    final button = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 482,
      ),
      child: SizedBox(
        width: double.infinity,
        child: AppWidgets.defaultFilledButton(
          child: Text(isInitial ? 'Home' : 'Login'),
          onPressed: () {
            if (isInitial) {
              context.read<AuthenticationBloc>().sigOut();
              return;
            }

            GoRouter.of(context).go(Paths.login);
          },
        ),
      ),
    );

    return BlocListener<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        if (state.status == AuthenticationStateStatus.logout) {
          GoRouter.of(context).go(Paths.index);
        }
      },
      child: Scaffold(
        body: AppWidgets.rootConstraints(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    const Gap(16),
                    text2,
                    const Gap(16),
                    button,
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    text,
                    Expanded(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text2,
                        const Gap(32),
                        button,
                      ],
                    ),),
                  ],
                ),
        ),),
      ),
    );
  }

  String _getMessage() {
    if (isInitial) {
      if (isProvider) {
        return '''
Ka-Loooans! Thank you for registering, joining us together with other loan providers to help the community have a brighter future.

We welcome you to Loooans! where we empower individuals and micro enterprises alike to leverage their financial capabilities to the best.
 
Our agents will reach you shortly to verify your account. Please follow the instructions on the email to complete your registration.

Once again, thank you for joining us and welcome to the start of your happy and stress-free financial business.


From: Loooans team''';
      }

      return '''
Ka-Loooans! Thank you for registering.

We welcome you to Loooans! where we empower individuals and micro enterprises alike to leverage their financial capabilities to the best.
 
You will receive an email shortly to verify your account. Please follow the 
instructions on the email to complete your registration.

Once again, thank you and welcome to the start of your happy and stress-free financial life.


From: Loooans team''';
    }

    if (isProvider) {
      throw UnimplementedError('Please implement message');
    }

    return '''
Ka-Loooans! Thank you for verifying your identity and completing your registration.

You can now login into the app and start your way for a happy and stress-free financial life.

Once again, we welcome you to Loooans! where we empower individuals and micro enterprises alike to leverage their financial capabilities to the best.


From: Loooans team''';
  }
}
