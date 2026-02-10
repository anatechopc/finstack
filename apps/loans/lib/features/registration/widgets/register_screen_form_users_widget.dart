import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/app/true_false_cubit.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans_helpers/string_helpers.dart';
import 'package:user_repository/user_repository.dart';

class RegisterScreenFormUsersWidget extends StatelessWidget {
  RegisterScreenFormUsersWidget({
    super.key,
    this.disableWidthConstraints = false,
    this.showTermsAndConditions = true,
    this.defaultInputColor = AppColors.green2,
    this.isUserCompanyManaged = false,
    this.showAsDialog = false,
  });

  final bool disableWidthConstraints;
  final bool showTermsAndConditions;
  final bool isUserCompanyManaged;
  final bool showAsDialog;

  final _formKey = GlobalKey<FormBuilderState>();

  final Color defaultInputColor;

  @override
  Widget build(BuildContext context) {
    return _body(context);
  }

  Widget _body(BuildContext context) {
    return FormBuilder(
      key: _formKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: !disableWidthConstraints ? 533 : double.infinity,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Gap(8),
              _userInputFields(context),
              const Gap(32),
              _addressInputFields(context),
              const Gap(32),
              _employmentDetailsInputFields(context),
              if (showTermsAndConditions) ...[
                const Gap(32),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    text: 'By clicking “Register”, you agree to Loooans ',
                    style: GoogleFonts.urbanist(
                      color: defaultInputColor == AppColors.green2
                          ? AppColors.green1
                          : AppColors.black,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: 'Terms of service',
                        style: GoogleFonts.urbanist(
                          color: AppColors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            debugPrint('terms of service tapped');
                          },
                      ),
                      const TextSpan(text: ' and acknowledge Loooans '),
                      TextSpan(
                        text: 'Privacy policy',
                        style: GoogleFonts.urbanist(
                          color: AppColors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            debugPrint('privacy policy tapped');
                          },
                      ),
                    ],
                  ),
                ),
                const Gap(16),
              ],
              SizedBox(
                width: double.infinity,
                child: AppWidgets.defaultFilledButton(
                  child: Text(
                    'Register',
                    style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: AppColors.black,
                    ),
                  ),
                  backgroundColor: AppColors.blue,
                  onPressed: () {
                    if (_formKey.currentState?.saveAndValidate() ?? false) {
                      if (!isUserCompanyManaged) {
                        context.read<RegistrationBloc>().registerUser(
                              _formKey.currentState!.value,
                            );
                      } else {
                        context.read<RegistrationBloc>().registerManagedUser(
                              _formKey.currentState!.value,
                            );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userInputFieldsCol1(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppWidgets.defaultFormBuilderTextField(
          name: 'last_name',
          label: 'Last name',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'first_name',
          label: 'First name',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'middle_name',
          label: 'Middle name(optional)',
          borderColor: defaultInputColor,
        ),
        AppWidgets.defaultFormBuilderDatePicker(
          name: 'birth_date',
          label: 'Birth date',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.required(),
          lastDate: Jiffy.now().subtract(years: 18).dateTime,
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'mobile_number',
          label: 'Mobile number',
          borderColor: defaultInputColor,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          keyboardType: TextInputType.number,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
            FormBuilderValidators.maxLength(10),
          ]),
          prefix: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '+63',
              style: TextStyle(
                color: defaultInputColor,
              ),
            ),
          ),
        ),
        AppWidgets.defaultFormBuilderDropdown(
          name: 'sex',
          label: 'Sex',
          items: Sex.values.map((sex) {
            return DropdownMenuItem(
              value: sex,
              child: Text(sex.label),
            );
          }).toList(),
          validator: FormBuilderValidators.required(),
          borderColor: defaultInputColor,
          dropdownColor: defaultInputColor == AppColors.black
              ? AppColors.white
              : defaultInputColor,
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'business_name',
          label: 'Business name(optional)',
          borderColor: defaultInputColor,
          helperText: 'Optional but highly encouraged to fill up',
        ),
      ]
          .mapIndexed((index, widget) {
            return [
              if (index != 0) const Gap(16),
              widget,
            ];
          })
          .flattened
          .toList(),
    );
  }

  Widget _userInputFieldsCol2(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppWidgets.defaultFormBuilderTextField(
          name: 'email_address',
          label: 'Email address',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            if (!isUserCompanyManaged)
              FormBuilderValidators.email(
                errorText: 'Please enter a valid email address',
              ),
            // for managed, require and check validity only if not empty
            (val) {
              if (val != null && val.isNotEmpty) {
                if (!val.isEmailValid()) {
                  return 'Please enter a valid email address';
                }
              }

              return null;
            }
          ]),
        ),
        if (!isUserCompanyManaged) ...[
          BlocProvider(
            create: (context) => TrueFalseCubit(),
            lazy: false,
            child: BlocBuilder<TrueFalseCubit, bool>(
              builder: (context, state) {
                return AppWidgets.defaultFormBuilderTextField(
                  name: 'password',
                  label: 'Password',
                  helperText:
                      'Min 8 Characters, combination of uppercase, lowercase, number and special character',
                  borderColor: defaultInputColor,
                  obscureText: !state,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.minLength(8),
                    (value) {
                      if (value != null) {
                        if (!value.isPasswordValidFormat()) {
                          return 'Password format must have a combination of uppercase, lowercase, number and special character';
                        }
                      }

                      return null;
                    }
                  ]),
                  suffix: IconButton(
                    onPressed: () {
                      context.read<TrueFalseCubit>().trigger();
                    },
                    icon: !state
                        ? const Icon(Icons.visibility_rounded)
                        : const Icon(Icons.visibility_off_rounded),
                  ),
                );
              },
            ),
          ),
          AppWidgets.defaultFormBuilderTextField(
            name: 'facebook_profile',
            label: 'Facebook profile',
            borderColor: defaultInputColor,
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(),
            ]),
          ),
        ],
        AppWidgets.defaultIconButtonMediaChooser(
          context,
          name: 'profile_picture',
          label: 'Profile picture',
          svgLogoPath: 'svg/profile_picture_upload.svg',
          validator:
              !isUserCompanyManaged ? FormBuilderValidators.required() : null,
          color: defaultInputColor,
        ),
        if (!isUserCompanyManaged)
          AppWidgets.defaultButtonMediaChooser(
            context,
            name: 'selfie_valid_id',
            label: 'Upload selfie with valid ID',
            color: defaultInputColor,
            validator: FormBuilderValidators.compose([
              FormBuilderValidators.required(),
            ]),
            allowGallery: false,
          ),
      ]
          .mapIndexed((index, widget) {
            return [if (index != 0) const Gap(16), widget];
          })
          .flattened
          .toList(),
    );
  }

  Widget _userInputFields(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    if (isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _userInputFieldsCol1(context),
          const Gap(16),
          _userInputFieldsCol2(context),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _userInputFieldsCol1(context),
        ),
        const Gap(24),
        Expanded(
          child: _userInputFieldsCol2(context),
        ),
      ],
    );
  }

  Widget _addressInputFieldsCol1() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_1',
          label: 'Address line 1',
          helperText: 'E.g house no., Street, Unit no.',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'line_2',
          label: 'Address line 2',
          helperText: 'E.g Subdivision, building',
          borderColor: defaultInputColor,
          // validator: FormBuilderValidators.compose([
          //   FormBuilderValidators.required(),
          // ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'barangay',
          label: 'Barangay',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'city',
          label: 'City/Municipality',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
      ]
          .mapIndexed((index, widget) {
            return [
              if (index != 0) const Gap(16),
              widget,
            ];
          })
          .flattened
          .toList(),
    );
  }

  Widget _addressInputFieldsCol2() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppWidgets.defaultFormBuilderTextField(
          name: 'province',
          label: 'Province',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'country',
          label: 'Country',
          enabled: false,
          initialValue: 'Philippines',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'zip',
          label: 'Zip code',
          borderColor: defaultInputColor,
          validator: FormBuilderValidators.compose([
            FormBuilderValidators.required(),
          ]),
        ),
      ]
          .mapIndexed((index, widget) {
            return [if (index != 0) const Gap(16), widget];
          })
          .flattened
          .toList(),
    );
  }

  Widget _addressInputFields(BuildContext context) {
    final text = Text(
      'Address',
      style: TextStyle(
        color: defaultInputColor,
        fontSize: 16,
      ),
    );

    if (getScreenSize(context: context) == ScreenSize.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          text,
          const Gap(16),
          _addressInputFieldsCol1(),
          const Gap(16),
          _addressInputFieldsCol2(),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text,
        const Gap(16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _addressInputFieldsCol1(),
            ),
            const Gap(24),
            Expanded(
              child: _addressInputFieldsCol2(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _employmentDetailsInputFields(BuildContext context) {
    final text = Text(
      'Employment details',
      style: TextStyle(
        color: defaultInputColor,
        fontSize: 16,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        text,
        AppWidgets.defaultFormBuilderDropdown(
          name: 'employment_status',
          label: 'Employment status',
          items: EmploymentStatus.values.map((status) {
            return DropdownMenuItem(
              value: status,
              child: Text(status.label),
            );
          }).toList(),
          validator: FormBuilderValidators.required(),
          borderColor: defaultInputColor,
          dropdownColor: defaultInputColor == AppColors.black
              ? AppColors.white
              : defaultInputColor,
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'employer_name',
          label: 'Employer name',
          borderColor: defaultInputColor,
        ),
        AppWidgets.defaultFormBuilderTextField(
          name: 'salary_days',
          label: 'Salary days',
          helperText:
              'Days which you receive salary. (e.g. 15,30 means every 15th and 30th of the month)',
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp('^[0-9]*[,]*[0-9]*'),
            ),
          ],
          borderColor: defaultInputColor,
        ),
      ]
          .mapIndexed((index, widget) {
            return [
              if (index != 0) const Gap(16),
              widget,
            ];
          })
          .flattened
          .toList(),
    );
  }
}
