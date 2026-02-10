import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/add_user/co_makers_section.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_repository/user_repository.dart';

class BorrowerDetailsSection extends StatelessWidget {
  const BorrowerDetailsSection({
    required this.enableUserForm,
    this.allowAddOns,
    super.key,
  });

  final bool enableUserForm;
  final bool? allowAddOns;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserBloc, UserState>(
      buildWhen: (prev, next) {
        return next.status == UserStatus.refresh;
      },
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Borrower details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(4),
            AppWidgets.defaultFormBuilderTextFieldDropdown<User>(
              name: 'last_name',
              enabled: allowAddOns ?? true,
              suggestionsCallback: (query) {
                return context.read<UserBloc>().getCustomersByCompany(
                      AuthenticationService.instance.company.id,
                      query: query,
                    );
              },
              onSelected: (user) {
                context.read<UserBloc>().setUser(user);
              },
              itemBuilder: (context, user) {
                var text = Text(user.completeNameEasternOrder);

                if (user.isPlaceholder) {
                  text = Text.rich(
                    TextSpan(
                      text: 'New user: ',
                      style: const TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: user.lastName,
                          style: const TextStyle(
                            color: AppColors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListTile(
                  title: text,
                );
              },
              selectionToTextTransformer: (user) {
                return user.lastName;
              },
              label: 'Last name',
            ),
            AppWidgets.defaultFormBuilderTextField(
              name: 'first_name',
              label: 'First name',
              enabled: enableUserForm,
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
              ]),
            ),
            AppWidgets.defaultFormBuilderTextField(
              name: 'middle_name',
              label: 'Middle name(optional)',
              enabled: enableUserForm,
            ),
            AppWidgets.defaultFormBuilderDatePicker(
              name: 'birth_date',
              label: 'Birth date',
              enabled: enableUserForm,
              validator: FormBuilderValidators.required(),
              lastDate: Jiffy.now().subtract(years: 18).dateTime,
            ),
            AppWidgets.defaultFormBuilderTextField(
              name: 'mobile_number',
              label: 'Mobile number',
              enabled: enableUserForm,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              keyboardType: TextInputType.number,
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                FormBuilderValidators.maxLength(10),
              ]),
              prefix: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '+63',
                  style: TextStyle(
                    color: AppColors.black,
                  ),
                ),
              ),
            ),
            AppWidgets.defaultFormBuilderTextField(
              name: 'email_address',
              label: 'Email address',
              enabled: enableUserForm,
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                FormBuilderValidators.email(),
              ]),
            ),
            const CoMakersSection(),
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
      },
    );
  }
}
