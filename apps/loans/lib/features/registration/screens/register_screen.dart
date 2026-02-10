import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/features/registration/widgets/register_screen_form_providers_widget.dart';
import 'package:loooans/features/registration/widgets/register_screen_form_users_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.registerAs,
  });

  final String? registerAs;

  @override
  State<StatefulWidget> createState() {
    return _RegisterScreenState();
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<RegistrationBloc, RegistrationState>(
      listener: (context, state) {
        if (state is RegistrationLoadingState) {
          if (state.isLoading) {
            AppWidgets.showDefaultLoadingDialog(context);
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } else if (state is RegistrationSuccessState) {
          GoRouter.of(context).go(
              '${Paths.registerComplete}?initial=true&as=${widget.registerAs}',);
        } else if (state is RegistrationErrorState) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        appBar: AppWidgets.defaultAppBar(
          context,
          showSignUp: false,
        ),
        body: AppWidgets.rootConstraints(
          child: _mainBody(context),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    debugPrint('register init');
  }

  Widget _mainBody(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 986;
    final signUpText = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 341),
      child: Text(
        'Sign up${widget.registerAs != null ? ' as Loooans! ${widget.registerAs}' : ''}',
        style: const TextStyle(
          fontSize: 48,
        ),
        textAlign: TextAlign.center,
      ),
    );

    Widget getFields(String registerAs) {
      return switch (registerAs) {
        'user' => _formUser(),
        'provider' => _formProvider(),
        _ => const Text('Cannot register as something else'),
      };
    }

    final fields = Container(
      margin: !isCompact ? const EdgeInsets.all(32) : null,
      padding: EdgeInsets.symmetric(
        vertical: widget.registerAs == null ? 56 : 24,
        horizontal: 24,
      ),
      width: isCompact ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: !isCompact
            ? defaultBorderRadius
            : const BorderRadius.only(
                topLeft: defaultRadius,
                topRight: defaultRadius,
              ),
      ),
      child: widget.registerAs == null
          ? _choices()
          : getFields(widget.registerAs!),
    );

    if (isCompact) {
      return Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: signUpText,
          ),
          const Gap(16),
          Expanded(
            child: fields,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        signUpText,
        fields,
      ],
    );
  }

  Widget _choices() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Register as',
          style: TextStyle(
            fontSize: 32,
            color: AppColors.white,
          ),
        ),
        const Gap(32),
        _registerAsButtons(
          description:
              'Applying for loans but is not decided which provider to apply? We can help you look for loan providers that works best for you!',
          registerAs: 'user',
          onTap: () {
            GoRouter.of(context).goSafe('${Paths.register}?as=user');
          },
        ),
        const Gap(16),
        _registerAsButtons(
          description:
              'We’ll help you manage your financial business. Join us in providing a better future for our community.',
          registerAs: 'provider',
          onTap: () {
            GoRouter.of(context).goSafe('${Paths.register}?as=provider');
          },
        ),
      ],
    );
  }

  Widget _registerAsButtons({
    required String description,
    required String registerAs,
    VoidCallback? onTap,
  }) {
    return InkWell(
      radius: 16,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 451),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: defaultBorderRadius,
          border: Border.all(
            color: AppColors.green2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              description,
              style: GoogleFonts.urbanist(
                color: AppColors.white,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              'Loooans! $registerAs',
              style: GoogleFonts.urbanist(
                color: AppColors.green2,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formUser() {
    return RegisterScreenFormUsersWidget();
  }

  Widget _formProvider() {
    return RegisterScreenFormProvidersWidget();
  }
}
