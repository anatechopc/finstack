import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:user_repository/user_repository.dart';

class BorrowerSearchWidget extends StatelessWidget {
  const BorrowerSearchWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final companyId = AuthenticationService.instance.company.id;

    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.black,
          selectionColor: AppColors.green1,
          selectionHandleColor: AppColors.green1_6,
        ),
      ),
      child: FormBuilderTypeAhead<User>(
        name: 'borrower_search',
        suggestionsCallback: (query) {
          return context
              .read<UserBloc>()
              .getCustomersByCompany(companyId, query: query);
        },
        onSelected: (user) {
          context
              .read<PaymentCenterBloc>()
              .add(SelectBorrowerEvent(borrower: user));
        },
        itemBuilder: (context, user) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.green1,
              child: Text(
                user.initials,
                style: const TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(user.completeNameEasternOrder),
            subtitle: Text(user.mobileNumber),
          );
        },
        selectionToTextTransformer: (user) => user.completeNameEasternOrder,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(16),
          hintText: 'Type borrower name...',
          prefixIcon: const Icon(Icons.search),
          label: const Text('Search borrower'),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: OutlineInputBorder(
            borderRadius: defaultBorderRadius,
            borderSide: BorderSide(
              color: AppColors.black.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: defaultBorderRadius,
            borderSide: const BorderSide(
              color: AppColors.black,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: defaultBorderRadius,
            borderSide: const BorderSide(color: AppColors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: defaultBorderRadius,
            borderSide: const BorderSide(color: AppColors.red),
          ),
        ),
      ),
    );
  }
}
