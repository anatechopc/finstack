import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/countdown_text.dart';

class VerifyWidget extends StatelessWidget {
  VerifyWidget({
    required this.expireAt, super.key,
  });

  final int expireAt;

  final _formKey = GlobalKey<FormBuilderState>();

  @override
  Widget build(BuildContext context) {
    final isExpanded = getScreenSize(context: context) == ScreenSize.expanded;

    return Padding(
      padding: EdgeInsets.all(isExpanded ? 24 : 16),
      child: FormBuilder(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'An OTP is sent to your mobile number. Please enter OTP before remaining time expires',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
            const Gap(16),
            CountdownText(
                expireAt: DateTime.fromMillisecondsSinceEpoch(expireAt),),
            const Gap(16),
            AppWidgets.defaultFormBuilderTextField(
              name: 'otp',
              label: 'One-time Pin',
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(errorText: 'Please enter OTP'),
              ]),
            ),
            const Gap(32),
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text(
                  'Verify',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),
                onPressed: () {
                  if (_formKey.currentState?.validate() ?? false) {
                    context.read<AuthenticationBloc>().verifyOtp(
                          _formKey.currentState!.value['otp'] as String,
                        );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
