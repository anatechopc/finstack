import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/products/widget/loan_application/loan_application_continue.dart';
import 'package:loooans/features/products/widget/loan_application/loan_application_quotation.dart';
import 'package:loooans/features/products/widget/loan_application/loan_application_requirements.dart';
import 'package:loooans/features/products/widget/loan_application/loan_application_title.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:product_view_repository/product_view_repository.dart';

class LoanApplication extends StatefulWidget {
  const LoanApplication({
    required this.loanAmount,
    required this.period,
    required this.productView,
    super.key,
    this.isFullScreen = false,
    this.showContinueButton = true,
    this.completeTerm,
  });

  final bool isFullScreen;
  final double loanAmount;
  final int period;
  final ProductView productView;
  final bool showContinueButton;
  final String? completeTerm;

  @override
  State<LoanApplication> createState() => LoanApplicationState();
}

class LoanApplicationState extends State<LoanApplication> {
  final _formKey = GlobalKey<FormBuilderState>(debugLabel: 'loan_application');

  @override
  Widget build(BuildContext context) {
    final isCompact = getScreenSize(context: context) == ScreenSize.compact;

    return BlocListener<LoansBloc, LoansState>(
      listener: (context, state) {
        if (state.status == LoansStatus.loading) {
          if (state.isLoading) {
            AppWidgets.showDefaultLoadingDialog(context);
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } else if (state.status == LoansStatus.success) {
          if (state.message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message!)));
          }

          if (!isCompact) {
            Navigator.of(context, rootNavigator: true).pop();
            if (AuthenticationService.instance.allowAddClients) {
              GoRouter.of(context).go('${Paths.index}?sec=clients');
            }
          } else {
            GoRouter.of(context).pop();
          }
        }
      },
      child: Padding(
        padding:
            widget.isFullScreen ? const EdgeInsets.all(16) : EdgeInsets.zero,
        child: FormBuilder(
          key: _formKey,
          child: Column(
            children: [
              LoanApplicationTitle(isFullScreen: widget.isFullScreen),
              const Gap(16),
              Expanded(
                child: widget.isFullScreen && isCompact
                    ? _bodyCompact(context)
                    : _body(context),
              ),
              const Gap(16),
              LoanApplicationContinue(
                showContinueButton: widget.showContinueButton,
                onContinuePressed: () => _onContinuePressed(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyCompact(BuildContext context) {
    final schedules = context.read<LoansBloc>().clientLoanSchedules;
    return ListView.separated(
      itemBuilder: (context, index) {
        return switch (index) {
          0 => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppWidgets.defaultFormBuilderTextField(
                  name: 'reason',
                  label: 'Reason',
                  helperText: 'Reason for applying a loan',
                  validator: FormBuilderValidators.required(),),
            ),
          1 => const LoanApplicationRequirements(),
          2 => LoanApplicationQuotation(
              loanAmount: widget.loanAmount,
              period: widget.period,
              interestRate: widget.productView.interestRate,
            ),
          3 => const Text(
              'Loan payment schedule',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 24,
              ),
            ),
          4 => const Text(
              'You need to pay \u20B1 5,500.00 every 15th day for the next 30 days',
              style: TextStyle(
                fontSize: 12,
              ),
            ),
          5 => const Text(
              'Schedule details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          _ => LoanScheduleWidget.scheduleItem(
              context,
              schedule: schedules[index - 6],
              index: index - 6,
            ),
        };
      },
      separatorBuilder: (context, index) {
        if (index == 4) {
          return const Gap(24);
        } else if (index == 5) {
          return const Gap(8);
        }
        return const Gap(16);
      },
      itemCount: 6 + schedules.length,
    );
  }

  Widget _body(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView.separated(
            itemBuilder: (context, index) {
              return switch (index) {
                0 => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AppWidgets.defaultFormBuilderTextField(
                        name: 'reason',
                        label: 'Reason',
                        helperText: 'Reason for applying a loan',
                        validator: FormBuilderValidators.required(),),
                  ),
                1 => const LoanApplicationRequirements(),
                2 => LoanApplicationQuotation(
                    loanAmount: widget.loanAmount,
                    period: widget.period,
                    interestRate: widget.productView.interestRate,
                  ),
                _ => Container()
              };
            },
            separatorBuilder: (context, index) {
              return const Gap(24);
            },
            itemCount: 3,
          ),
        ),
        const Gap(24),
        Expanded(
          child: LoanScheduleWidget(
            amortization: context.read<LoansBloc>().monthlyAmortization,
            schedules: context.read<LoansBloc>().clientLoanSchedules,
            completeTerm:
                widget.completeTerm ?? widget.productView.completeTerm,
          ),
        ),
      ],
    );
  }

  void _onContinuePressed(BuildContext context) {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      final selectedProduct = context.read<ProductBloc>().selectedProduct;

      if (selectedProduct != null) {
        context.read<LoansBloc>().addLoan(
          fields: {
            'amount': widget.loanAmount.toString(),
            'period': widget.period.toString(),
            'reason': _formKey.currentState!.value['reason'] as String,
            'company_name': widget.productView.companyName,
          },
          term: selectedProduct.term,
          interestRate: selectedProduct.interestRate,
          product: selectedProduct,
        );
      }
    }
  }

  String getReason() {
    return _formKey.currentState?.simplifiedFields()['reason'] as String? ??
        'No reason';
  }

  bool validateForm() {
    return _formKey.currentState?.saveAndValidate() ?? false;
  }
}
