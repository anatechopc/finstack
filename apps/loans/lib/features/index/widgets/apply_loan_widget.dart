import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ApplyLoanWidget extends StatefulWidget {
  const ApplyLoanWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ApplyLoanWidgetState();
  }
}

class _ApplyLoanWidgetState extends State<ApplyLoanWidget> {
  final _formKey = GlobalKey<FormBuilderState>();

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 48),
      constraints: const BoxConstraints(
        maxWidth: 402,
      ),
      decoration: BoxDecoration(
        borderRadius: defaultBorderRadius,
        color: AppColors.black,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FormBuilder(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apply for a loan',
                  style: GoogleFonts.urbanist(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green1,
                  ),
                ),
                const Gap(24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppWidgets.defaultFormBuilderTextField(
                        name: 'amount',
                        label: 'Amount',
                        borderColor: AppColors.green2,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('^[0-9]*[.]?[0-9]*'),
                          ),
                        ],
                        validator: FormBuilderValidators.required(),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: AppWidgets.defaultFormBuilderTextField(
                        name: 'period',
                        label: 'Period',
                        helperText: 'In months',
                        borderColor: AppColors.green2,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(24),
                SizedBox(
                  width: double.infinity,
                  // height: 49,
                  child: AppWidgets.defaultOutlinedButton(
                    child: Text(
                      'Search providers',
                      style: GoogleFonts.urbanist(
                          fontSize: 16, fontWeight: FontWeight.w400,),
                    ),
                    padding: isCompact
                        ? defaultCompactButtonPadding
                        : defaultButtonPadding,
                    foregroundColor: AppColors.green1,
                    onPressed: () {
                      if (!(_formKey.currentState?.validate() ?? false)) {
                        return;
                      }

                      var location =
                          '/?sec=offers&${Paths.paramMaxLoanable}=${_formKey.currentState!.simplifiedFields()['amount']}';
                      final period =
                          _formKey.currentState!.simplifiedFields()['period'];
                      if (period != null) {
                        location += '&${Paths.paramMaxPeriod}=$period';
                      }

                      GoRouter.of(context).go(
                        location,
                        extra: {
                          Paths.extraAllowUnauthenticated: true,
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
