import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:gap/gap.dart';
import 'package:loooans/app/counter_cubit.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/loan_application.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class AddUserNavigationButtons extends StatelessWidget {
  const AddUserNavigationButtons({
    required this.pageViewController,
    required this.formKey,
    required this.loanApplicationKey,
    this.allowAddOns,
    super.key,
  });

  final PageController pageViewController;
  final GlobalKey<FormBuilderState> formKey;
  final GlobalKey<LoanApplicationState> loanApplicationKey;
  final bool? allowAddOns;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CounterCubit, int>(
      builder: (context, state) {
        return Row(
          children: [
            Expanded(
              child: AppWidgets.defaultFilledButton(
                child: const Text('Previous'),
                onPressed: () {
                  pageViewController.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.fastLinearToSlowEaseIn,);
                },
              ),
            ),
            const Gap(16),
            Expanded(
                child: AppWidgets.defaultFilledButton(
              child: Text(
                state == 2 ? 'Continue' : 'Next',
                style: TextStyle(
                  color: state == 2 ? AppColors.green1 : AppColors.white,
                ),
              ),
              onPressed: () {
                _onNextPressed(context, state);
              },
            ),),
          ],
        );
      },
    );
  }

  void _onNextPressed(BuildContext context, int state) {
    if (state == 1 &&
        context.read<UserBloc>().selectedUser == null) {
      AppWidgets.showDefaultSimpleDialog(
        context,
        content: 'Please select a borrower to continue',
      );
      return;
    } else if (state == 1 &&
        context.read<UserBloc>().coMakers.length !=
            (context
                    .read<ProductBloc>()
                    .selectedProduct
                    ?.requiredCoMakerCount ??
                0)) {
      AppWidgets.showDefaultSimpleDialog(
        context,
        content: 'Please add co-makers to continue',
      );
      return;
    }

    if (state == 0 &&
        context.read<ProductBloc>().selectedProduct == null) {
      AppWidgets.showDefaultSimpleDialog(
        context,
        content: 'Please select a loan to continue',
      );
      return;
    }

    final maxPeriod =
        context.read<ProductBloc>().selectedProduct?.maxPeriod ?? 1;
    final period = int.parse(
      formKey.currentState?.fields['period']?.value?.toString() ?? '0',
    );

    if (state == 0 && maxPeriod >= 1 && period == 0) {
      AppWidgets.showDefaultSimpleDialog(
        context,
        content: 'Please enter a valid period to continue',
      );
      return;
    }

    pageViewController.nextPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.fastLinearToSlowEaseIn,
    );

    if (state == 2) {
      if ((formKey.currentState?.saveAndValidate() ?? false) &&
          (loanApplicationKey.currentState?.validateForm() ?? false)) {
        final reasonForLoan =
            loanApplicationKey.currentState?.getReason();
        final productBloc = context.read<ProductBloc>();
        final productView = productBloc.tempProductView;
        final selectedProduct = productBloc.selectedProduct;
        final selectedUser = context.read<UserBloc>().selectedUser;
        final coMakers = context.read<UserBloc>().coMakers;
        String? parentId;

        if (!(allowAddOns ?? true)) {
          parentId = context.read<LoansBloc>().selectedLoan.id;
        }

        if (selectedProduct != null && selectedUser != null) {
          context.read<LoansBloc>().addLoan(
            fields: {
              ...formKey.currentState!.simplifiedFields(),
              'reason': reasonForLoan,
              'company_name': productView.companyName,
            },
            term: selectedProduct.term,
            interestRate: selectedProduct.interestRate,
            product: selectedProduct,
            user: selectedUser,
            coMakers: coMakers,
            parentId: parentId,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Please select a borrower and/or a loan product to proceed',),),);
        }
      }

      return;
    }
  }
}
