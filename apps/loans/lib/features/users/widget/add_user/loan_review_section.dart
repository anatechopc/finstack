import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/loan_application.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/utils/extensions.dart';

class LoanReviewSection extends StatelessWidget {
  const LoanReviewSection({
    required this.formKey,
    required this.loanApplicationKey,
    super.key,
  });

  final GlobalKey<FormBuilderState> formKey;
  final GlobalKey<LoanApplicationState> loanApplicationKey;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductBloc, ProductState>(
      buildWhen: (prev, next) {
        return [
          ProductStatus.refresh,
          ProductStatus.selected,
          ProductStatus.unselected,
          ProductStatus.initial,
          ProductStatus.loanSelected,
        ].contains(next.status);
      },
      builder: (context, state) {
        final selectedUser = context.read<UserBloc>().selectedUser;
        final loanAmount = double.parse(
          formKey.currentState?.fields['amount']?.value?.toString() ??
              '0',
        );
        final period = int.parse(
          formKey.currentState?.fields['period']?.value?.toString() ??
              '0',
        );

        final paymentFrequency = formKey
                .currentState?.fields['payment_frequency']?.value
                ?.toString() ??
            '';

        if (selectedUser != null) {
          final productView =
              context.read<ProductBloc>().tempProductView;

          context.read<LoansBloc>().calculateLoan(
            fields: {
              'amount': loanAmount.toString(),
              'period': period.toString(),
              'payment_frequency': paymentFrequency,
            },
            term: productView.term,
            interestRate: productView.interestRate,
            additionalCharges: context.read<ProductBloc>().charges,
            deductions: context.read<ProductBloc>().deductions,
            user: context.read<UserBloc>().selectedUser,
          );
        }

        return BlocBuilder<LoansBloc, LoansState>(
          buildWhen: (prev, next) {
            return next.status == LoansStatus.refresh;
          },
          builder: (context, state) {
            return LoanApplication(
              key: loanApplicationKey,
              loanAmount: loanAmount,
              period: period,
              productView:
                  context.read<ProductBloc>().tempProductView,
              showContinueButton: false,
              completeTerm: paymentFrequency == 'salary_days'
                  ? context
                          .read<UserBloc>()
                          .selectedUser
                          ?.employmentDetails
                          .salaryDays
                          .join(',')
                          .generateOrdinalIndicators()
                  : paymentFrequency.isNotEmpty
                      ? paymentFrequency.completeTerm()
                      : null,
            );
          },
        );
      },
    );
  }
}
