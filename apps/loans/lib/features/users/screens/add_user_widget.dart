import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/counter_cubit.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/widget/add_loan_stage_indicator.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/loan_application.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/features/registration/widgets/register_screen_form_users_widget.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/add_user/add_user_navigation_buttons.dart';
import 'package:loooans/features/users/widget/add_user/borrower_details_section.dart';
import 'package:loooans/features/users/widget/add_user/choose_loan_section.dart';
import 'package:loooans/features/users/widget/add_user/loan_form_fields_section.dart';
import 'package:loooans/features/users/widget/add_user/loan_review_section.dart';
import 'package:loooans/utils/debounce.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// The dialog title for [AddUserWidget], derived from its mode.
///
/// - Loan-application flow ([extendedDetailsOnly] is false) → "Add loan".
/// - Extended-details flow → "Add team member" for staff invites
///   ([isTeamMember] true), otherwise "Add borrower".
@visibleForTesting
String addUserWidgetTitle({
  required bool extendedDetailsOnly,
  required bool isTeamMember,
}) {
  if (!extendedDetailsOnly) return 'Add loan';
  return isTeamMember ? 'Add team member' : 'Add borrower';
}

class AddUserWidget extends StatefulWidget {
  const AddUserWidget({
    super.key,
    this.withLoanApplication = false,
    this.withExtendedUserDetailInputs = false,
    this.allowAddOns,
    this.isTeamMember = false,
  });

  final bool withLoanApplication;
  final bool withExtendedUserDetailInputs;
  final bool? allowAddOns;
  final bool isTeamMember;

  @override
  State<AddUserWidget> createState() => _AddUserWidgetState();
}

class _AddUserWidgetState extends State<AddUserWidget> {
  final _formKey = GlobalKey<FormBuilderState>(debugLabel: 'add_user');
  final _loanApplicationKey = GlobalKey<LoanApplicationState>(
      debugLabel: 'add_user_loan_application_child',);
  final bool _enableUserForm = true;
  int _selectedIndex = -1;
  int _selectedPage = 0;
  final _debounce = Debounce(milliseconds: 500);
  final _pageViewController = PageController();

  bool get onlyExtendedUserDetailsInput =>
      widget.withExtendedUserDetailInputs && !widget.withLoanApplication;

  @override
  void initState() {
    super.initState();
    final allowAddOns = widget.allowAddOns;

    context.read<ProductBloc>().loadNext(allowAddOns: allowAddOns);

    if (allowAddOns != null && !allowAddOns) {
      context
          .read<UserBloc>()
          .setCoMakers(context.read<LoansBloc>().selectedLoanCoMakers);

      Timer(const Duration(milliseconds: 500), () {
        context
            .read<UserBloc>()
            .setUser(context.read<UserBloc>().selectedUser!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ProductBloc, ProductState>(
          listener: (context, state) {
            if (state.status == ProductStatus.unselected) {
              context.read<UserBloc>().unselectUser();
              _formKey.currentState?.reset();
            }
          },
        ),
        BlocListener<LoansBloc, LoansState>(
          listener: (context, state) {
            if (state.status == LoansStatus.error) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
        BlocListener<UserBloc, UserState>(
          listener: (context, state) {
            if (state.status == UserStatus.success && state.user != null) {
            } else if (state.status == UserStatus.selected) {
              _formKey.currentState?.patchValue({
                'first_name': state.user?.firstName,
                'middle_name': state.user?.middleName,
                'birth_date': state.user?.birthDate,
                'mobile_number': state.user?.mobileNumber,
                'email_address': state.user?.emailAddress,
              });

              if (!(widget.allowAddOns ?? true)) {
                _formKey.currentState?.fields['last_name']?.didChange(
                  state.user,
                );
              }
              context.read<UserBloc>().refresh();
            } else if (state.status == UserStatus.loading) {
              if (widget.withExtendedUserDetailInputs) {
                if (state.isLoading) {
                  AppWidgets.showDefaultLoadingDialog(context);
                } else {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              }
            } else if (state.status == UserStatus.error) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
        BlocListener<RegistrationBloc, RegistrationState>(
          listener: (context, state) {
            if (state is RegistrationLoadingState) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state is RegistrationErrorState) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
              Navigator.of(context, rootNavigator: true).pop();
            } else if (state is RegistrationSuccessState) {
              Navigator.of(context, rootNavigator: true).pop();
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
        ),
      ],
      child: FormBuilder(
        key: _formKey,
        onChanged: () {
          _debounce.run(() {
            context.read<ProductBloc>().refresh();
          });
        },
        child: BlocProvider(
          create: (context) => CounterCubit(),
          child: Builder(
            builder: _body,
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
      ),
      width: 1200,
      height: onlyExtendedUserDetailsInput ? 1000 : null,
      constraints: const BoxConstraints(
        maxWidth: 1200,
        maxHeight: 1068,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            addUserWidgetTitle(
              extendedDetailsOnly: onlyExtendedUserDetailsInput,
              isTeamMember: widget.isTeamMember,
            ),
            style: const TextStyle(
              fontSize: 24,
              color: AppColors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(16),
          if (!onlyExtendedUserDetailsInput) ...[
            BlocBuilder<CounterCubit, int>(
              builder: (context, index) {
                return AddLoanStageIndicator(selectedIndex: index);
              },
            ),
            const Gap(16),
          ],
          Expanded(
            child: PageView.builder(
              allowImplicitScrolling: true,
              controller: _pageViewController,
              onPageChanged: (page) {
                if (page > _selectedPage) {
                  context.read<CounterCubit>().increase();
                } else {
                  context.read<CounterCubit>().decrease();
                }
                _selectedPage = page;
              },
              itemCount: !widget.withLoanApplication ? 1 : 3,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _buildPage0(context);
                } else if (index == 1) {
                  return BorrowerDetailsSection(
                    enableUserForm: _enableUserForm,
                    allowAddOns: widget.allowAddOns,
                  );
                } else if (index == 2) {
                  return LoanReviewSection(
                    formKey: _formKey,
                    loanApplicationKey: _loanApplicationKey,
                  );
                }

                throw Exception('Page number $index not supported');
              },
            ),
          ),
          if (!onlyExtendedUserDetailsInput) ...[
            const Gap(32),
            AddUserNavigationButtons(
              pageViewController: _pageViewController,
              formKey: _formKey,
              loanApplicationKey: _loanApplicationKey,
              allowAddOns: widget.allowAddOns,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPage0(BuildContext context) {
    if (widget.withExtendedUserDetailInputs) {
      return RegisterScreenFormUsersWidget(
        disableWidthConstraints: true,
        defaultInputColor: AppColors.black,
        isAdminCreating: true,
        isTeamMemberMode: widget.isTeamMember,
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: ChooseLoanSection(
              selectedIndex: _selectedIndex,
              allowAddOns: widget.allowAddOns,
              onProductSelected: (index, productId, productView) {
                setState(() {
                  _selectedIndex = index;
                });
                context.read<ProductBloc>().selectProduct(
                      productId,
                      productView: productView,
                      forLoans: true,
                    );
              },
              onProductUnselected: () {
                setState(() {
                  _selectedIndex = -1;
                });
                context.read<ProductBloc>().unselectProduct();
              },
            ),
          ),
          LoanFormFieldsSection(formKey: _formKey),
        ],
      );
    }
  }
}
