import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/companies/bloc/company_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_address.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_company_details.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_portrait_address_fields.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_portrait_header.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_portrait_personal_fields.dart';
import 'package:loooans/features/users/widget/update_profile/update_profile_primary_details.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class UpdateProfileScreen extends StatelessWidget {
  UpdateProfileScreen({
    super.key,
    this.isFullScreen = false,
    this.forCompany = false,
    this.showAddress = true,
  });

  bool isFullScreen;
  bool forCompany;
  bool showAddress;

  final _formKey =
      GlobalKey<FormBuilderState>(debugLabel: 'update_profile_screen');

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<UserBloc, UserState>(
          listener: (context, state) {
            if (state.status == UserStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == UserStatus.success) {
              if (state.message != null && state.message!.isNotEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            } else if (state.status == UserStatus.requireMobileVerify) {
              GoRouter.of(context).go(Paths.mobileVerification);
            }
          },
        ),
        BlocListener<CompanyBloc, CompanyState>(
          listener: (context, state) {
            if (state.status == CompanyStateStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == CompanyStateStatus.success) {
              if (state.message != null && state.message!.isNotEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
      ],
      child: FormBuilder(
        key: _formKey,
        child: !isFullScreen ? _body(context) : _bodyPortrait(context),
      ),
    );
  }

  Widget _bodyPortrait(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const [
              UpdateProfilePortraitHeader(),
              Gap(16),
              UpdateProfilePortraitPersonalFields(),
              Gap(16),
              UpdateProfilePortraitAddressFields(),
            ],
          ),
        ),
        const Gap(8),
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppWidgets.defaultFilledButton(
              child: const Text('Update'),
              onPressed: () => _onUpdatePressed(context),
              foregroundColor: AppColors.green1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    return SizedBox(
      width: 800,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            forCompany ? 'Company details' : 'Personal details',
            style: const TextStyle(
              color: AppColors.black,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          const Gap(24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (forCompany)
                Expanded(
                  child: UpdateProfileCompanyDetails(formKey: _formKey),
                )
              else
                const Expanded(
                  child: UpdateProfilePrimaryDetails(),
                ),
              if (showAddress) ...[
                const Gap(24),
                const Expanded(
                  child: UpdateProfileAddress(),
                ),
              ],
            ],
          ),
          const Gap(24),
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: const Text('Update'),
              onPressed: () => _onUpdatePressed(context),
              foregroundColor: AppColors.green1,
            ),
          ),
        ],
      ),
    );
  }

  void _onUpdatePressed(BuildContext context) {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      if (forCompany) {
        context.read<CompanyBloc>().updateCompany(
              AuthenticationService.instance.company,
              _formKey.currentState!.value,
            );
      } else {
        context.read<UserBloc>().updateUser(
              _formKey.currentState!.value,
              user: AuthenticationService.instance.user,
            );
      }
    }
  }
}
