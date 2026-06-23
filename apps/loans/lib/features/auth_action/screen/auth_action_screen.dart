import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/true_false_cubit.dart';
import 'package:loooans/features/auth_action/cubit/auth_action_cubit.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/string_helpers.dart';

/// Branded replacement for Firebase's default `/__/auth/action` page.
///
/// A user clicking the "Complete my sign-up" / reset link lands here, sets a
/// password and is auto-signed-in by reusing the existing login flow — so a new
/// borrower flows into the email + mobile OTP verify step and an existing user
/// lands in the app.
class AuthActionScreen extends StatefulWidget {
  const AuthActionScreen({
    required this.mode,
    required this.oobCode,
    super.key,
  });

  final String? mode;
  final String? oobCode;

  @override
  State<AuthActionScreen> createState() => _AuthActionScreenState();
}

class _AuthActionScreenState extends State<AuthActionScreen> {
  final _formKey = GlobalKey<FormBuilderState>();

  /// Captured right before `cubit.submit` so the auto-sign-in listener can
  /// reuse it once the cubit reports `done`. Intentionally nullable — it stays
  /// null until the user submits the form, so `late` would be incorrect here.
  // ignore: use_late_for_private_fields_and_variables
  String? _submittedPassword;

  bool get _isSupported =>
      widget.mode == 'resetPassword' && widget.oobCode != null;

  @override
  void initState() {
    super.initState();
    if (_isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AuthActionCubit>().verify(widget.oobCode!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) {
      return _shell(
        child: _invalidCard(
          context,
          message: "This link isn't valid.",
        ),
      );
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<AuthActionCubit, AuthActionState>(
          listenWhen: (prev, curr) => curr.status == AuthActionStatus.done,
          listener: (context, state) {
            // Reuse the existing login flow for sign-in (session loading,
            // verify-gate, etc.) instead of reimplementing it.
            context.read<AuthenticationBloc>().login(
                  email: state.email!,
                  password: _submittedPassword!,
                );
          },
        ),
        BlocListener<AuthenticationBloc, AuthenticationState>(
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
        ),
      ],
      child: BlocBuilder<AuthenticationBloc, AuthenticationState>(
        builder: (context, authState) {
          final isAuthLoading =
              authState.status == AuthenticationStateStatus.loading &&
                  authState.isLoading;
          return Stack(
            children: [
              _shell(
                child: BlocBuilder<AuthActionCubit, AuthActionState>(
                  builder: (context, state) {
                    switch (state.status) {
                      case AuthActionStatus.verifying:
                        return _loading(context, 'Checking your link…');
                      case AuthActionStatus.invalid:
                        return _invalidCard(
                          context,
                          message: state.errorMessage ??
                              'This link is no longer valid.',
                        );
                      case AuthActionStatus.ready:
                      case AuthActionStatus.submitting:
                      case AuthActionStatus.error:
                        return _passwordCard(context, state);
                      case AuthActionStatus.done:
                        // Sign-in handed off to the AuthenticationBloc.
                        return _loading(context, 'Signing you in…');
                    }
                  },
                ),
              ),
              if (isAuthLoading)
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
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Scaffold(
      appBar: AppWidgets.defaultAppBar(
        context,
        showLogin: false,
      ),
      body: AppWidgets.rootConstraints(
        child: Center(child: child),
      ),
    );
  }

  Widget _loading(BuildContext context, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(color: AppColors.green1),
        ),
        const Gap(16),
        Text(
          message,
          style: const TextStyle(
            color: AppColors.black,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 483),
      child: Container(
        margin: !isCompact ? const EdgeInsets.all(32) : const EdgeInsets.all(16),
        padding: EdgeInsets.all(isCompact ? 16 : 56),
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: defaultBorderRadius,
        ),
        child: child,
      ),
    );
  }

  Widget _invalidCard(BuildContext context, {required String message}) {
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link expired or invalid',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(12),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 15,
            ),
          ),
          const Gap(32),
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              onPressed: () => GoRouter.of(context).go(Paths.login),
              backgroundColor: AppColors.blue,
              foregroundColor: AppColors.black,
              child: const Text(
                'Go to sign in',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordCard(BuildContext context, AuthActionState state) {
    final isSubmitting = state.status == AuthActionStatus.submitting;
    return _card(
      child: SingleChildScrollView(
        child: FormBuilder(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set your password',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(8),
              const Text(
                'Choose a password to finish signing in.',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                ),
              ),
              const Gap(24),
              BlocProvider(
                create: (context) => TrueFalseCubit(),
                child: BlocBuilder<TrueFalseCubit, bool>(
                  builder: (context, visible) {
                    return AppWidgets.defaultFormBuilderTextField(
                      name: 'password',
                      label: 'Password',
                      helperText:
                          'Min 8 Characters, combination of uppercase, '
                          'lowercase, number and special character',
                      borderColor: AppColors.green2,
                      obscureText: !visible,
                      enabled: !isSubmitting,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                        FormBuilderValidators.minLength(8),
                        (value) {
                          if (value != null) {
                            if (!value.isPasswordValidFormat()) {
                              return 'Password format must have a combination '
                                  'of uppercase, lowercase, number and special '
                                  'character';
                            }
                          }

                          return null;
                        }
                      ]),
                      suffix: IconButton(
                        onPressed: () {
                          context.read<TrueFalseCubit>().trigger();
                        },
                        icon: Icon(
                          !visible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Gap(16),
              BlocProvider(
                create: (context) => TrueFalseCubit(),
                child: BlocBuilder<TrueFalseCubit, bool>(
                  builder: (context, visible) {
                    return AppWidgets.defaultFormBuilderTextField(
                      name: 'confirm_password',
                      label: 'Confirm password',
                      borderColor: AppColors.green2,
                      obscureText: !visible,
                      enabled: !isSubmitting,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                        (value) {
                          final password =
                              _formKey.currentState?.fields['password']?.value
                                  as String?;
                          if (value != password) {
                            return 'Passwords do not match';
                          }

                          return null;
                        }
                      ]),
                      suffix: IconButton(
                        onPressed: () {
                          context.read<TrueFalseCubit>().trigger();
                        },
                        icon: Icon(
                          !visible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (state.status == AuthActionStatus.error) ...[
                const Gap(16),
                Text(
                  state.errorMessage ?? 'Could not set password',
                  style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 14,
                  ),
                ),
              ],
              const Gap(32),
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultFilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          if (_formKey.currentState?.saveAndValidate() ??
                              false) {
                            final fields = _formKey.currentState!.value;
                            _submittedPassword = fields['password'] as String;
                            context.read<AuthActionCubit>().submit(
                                  oobCode: widget.oobCode!,
                                  newPassword: _submittedPassword!,
                                );
                          }
                        },
                  backgroundColor: AppColors.blue,
                  foregroundColor: AppColors.black,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.black,
                          ),
                        )
                      : const Text(
                          'Set password & continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
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
