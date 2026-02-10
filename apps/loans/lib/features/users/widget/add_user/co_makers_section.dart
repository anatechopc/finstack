import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class CoMakersSection extends StatelessWidget {
  const CoMakersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductBloc, ProductState>(
      builder: (context, state) {
        final requiredCoMakerCount = context
                .read<ProductBloc>()
                .selectedProduct
                ?.requiredCoMakerCount ??
            0;

        if (requiredCoMakerCount <= 0) {
          return Container();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Gap(4),
            const Divider(
              color: AppColors.black,
            ),
            const Text(
              'Co-makers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(16),
            BlocBuilder<UserBloc, UserState>(
              builder: (context, state) {
                final coMakers = context.read<UserBloc>().coMakers;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (coMakers.isNotEmpty) ...[
                      for (final (index, coMaker) in coMakers.indexed)
                        ListTile(
                          title: Text.rich(
                            TextSpan(
                              text: 'Co-maker ${index + 1}: ',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${coMaker.completeNameEasternOrder} - ${coMaker.mobileNumber}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: AppColors.red2,
                            ),
                            onPressed: () {
                              context
                                  .read<UserBloc>()
                                  .removeCoMaker(coMaker);
                            },
                          ),
                        ),
                    ] else
                      const Text('No co-makers added'),
                  ],
                );
              },
            ),
            const Gap(16),
            AppWidgets.defaultOutlinedButton(
              child: const Text('Add Co-maker'),
              onPressed: () {
                _showAddCoMakerDialog(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddCoMakerDialog(BuildContext context) {
    final coMakerKey = GlobalKey<FormBuilderState>(
      debugLabel: 'add_comaker_dialog',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Co-maker'),
          content: SizedBox(
            width: 800,
            height: 250,
            child: FormBuilder(
              key: coMakerKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppWidgets.defaultFormBuilderTextFieldDropdown(
                    name: 'comaker_last_name',
                    suggestionsCallback: (query) {
                      return context
                          .read<UserBloc>()
                          .getCustomersByCompany(
                            AuthenticationService.instance.company.id,
                            query: query,
                          );
                    },
                    onSelected: (user) {
                      context.read<UserBloc>().setCoMaker(user);
                    },
                    itemBuilder: (context, user) {
                      var text =
                          Text(user.completeNameEasternOrder);

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
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(),
                    ]),
                  ),
                  const Gap(16),
                  const Text(
                    'Co-maker details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(16),
                  BlocBuilder<UserBloc, UserState>(
                    builder: (context, state) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: 'Name: ',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(
                                  text: state.user
                                          ?.completeNameEasternOrder ??
                                      '',
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Gap(8),
                          Text.rich(
                            TextSpan(
                              text: 'Mobile number: ',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(
                                  text: state.user?.mobileNumber ??
                                      '',
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Gap(8),
                          Text.rich(
                            TextSpan(
                              text: 'Email address: ',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      state.user?.emailAddress ??
                                          '',
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Add'),
                onPressed: () {
                  if (coMakerKey.currentState?.saveAndValidate() ??
                      false) {
                    final user =
                        context.read<UserBloc>().selectedCoMaker;
                    if (user != null) {
                      context.read<UserBloc>().addCoMaker(user);
                      Navigator.of(context).pop();
                    }
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
