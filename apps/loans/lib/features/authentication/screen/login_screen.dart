import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/true_false_cubit.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/logo_widget.dart';

class LoginScreen extends StatelessWidget {
  LoginScreen({super.key});

  final _formKey = GlobalKey<FormBuilderState>();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthenticationBloc, AuthenticationState>(
      listener: (context, state) {
        if (state.status == AuthenticationStateStatus.verify) {
          // Send to the verification hub — it shows both email and mobile
          // status and routes to the appropriate leaf when the user taps
          // a card.
          GoRouter.of(context).go(Paths.verify);
        } else if (state.status == AuthenticationStateStatus.success) {
          if (!SettingsService.instance.appUseClassicUI) {
            GoRouter.of(context).go(Paths.index);
          } else {
            GoRouter.of(context).go(Paths.dashboard);
          }
        } else if (state.status == AuthenticationStateStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message ?? 'Login failed'),
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state.status == AuthenticationStateStatus.loading &&
            state.isLoading;
        return Stack(
          children: [
            Scaffold(
              appBar: AppWidgets.defaultAppBar(
                context,
                showLogin: false,
              ),
              body: AppWidgets.rootConstraints(
                child: _mainBody(context),
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

  Widget _mainBody(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;
    final isMedium = getScreenSize(context: context) == ScreenSize.medium;
    final signUpText = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 341),
      child: const LogoWidget(),
    );

    final fields = Container(
      margin: !isCompact ? const EdgeInsets.all(32) : null,
      padding: EdgeInsets.all(isCompact ? 16 : 56),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: !isCompact
            ? defaultBorderRadius
            : const BorderRadius.only(
          topLeft: defaultRadius,
          topRight: defaultRadius,
        ),
      ),
      child: _loginForm(context),
    );

    if (isCompact || isMedium) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: signUpText,
          ),
          const Gap(16),
          if (isCompact)
            Expanded(
              child: fields,
            )
          else
            fields,
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

  Widget _loginForm(BuildContext context) {
    const email = String.fromEnvironment('ENVIRONMENT') == 'development'
        ? 'dafduldulao@gmail.com'
        : null;

    const password = String.fromEnvironment('ENVIRONMENT') ==
        'development'
        ? 'Password1!'
        : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 483),
      child: SingleChildScrollView(
        child: FormBuilder(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppWidgets.defaultFormBuilderTextField(
                name: 'email_address',
                label: 'Email Address',
                initialValue: email,
                borderColor: AppColors.green2,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                  FormBuilderValidators.email(),
                ]),
                keyboardType: TextInputType.emailAddress,
              ),
              const Gap(16),
              BlocProvider(
                create: (context) => TrueFalseCubit(),
                child: BlocBuilder<TrueFalseCubit, bool>(
                  builder: (context, state) {
                    return AppWidgets.defaultFormBuilderTextField(
                      name: 'password',
                      label: 'Password',
                      initialValue: password,
                      borderColor: AppColors.green2,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                      ]),
                      obscureText: !state,
                      suffix: IconButton(
                        onPressed: () {
                          context.read<TrueFalseCubit>().trigger();
                        },
                        icon: Icon(
                          !state
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Gap(32),
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultFilledButton(
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    if (_formKey.currentState?.saveAndValidate() ?? false) {
                      final fields = _formKey.currentState!.value;
                      context.read<AuthenticationBloc>().login(
                        email: fields['email_address'] as String,
                        password: fields['password'] as String,
                      );
                    }
                  },
                  backgroundColor: AppColors.blue,
                  foregroundColor: AppColors.black,
                ),
              ),
              const Gap(16),
              RichText(
                text: TextSpan(
                  text: 'Forgot password',
                  style: const TextStyle(
                    color: AppColors.blue,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      debugPrint('Forgot password');
                      // context.read<AuthenticationBloc>().requestOtp();
                    },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
