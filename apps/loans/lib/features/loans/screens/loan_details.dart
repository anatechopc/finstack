import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_svg/svg.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/payments/widget/submit_payment_dialog.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

class LoanDetails extends StatefulWidget {
  const LoanDetails({
    required this.id,
    super.key,
    this.fullScreen = false,
    this.userLoanView,
  });
  final String id;
  final bool fullScreen;
  final UserLoanView? userLoanView;

  @override
  State<LoanDetails> createState() => _LoanDetailsState();
}

class _LoanDetailsState extends State<LoanDetails> {
  @override
  void initState() {
    super.initState();

    context.read<LoansBloc>().selectLoan(
          widget.id,
          userLoanView: widget.userLoanView,
        );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = getScreenSize(context: context);

    if (screenSize.index > ScreenSize.medium.index) {
      GoRouter.of(context).goSafe('${Paths.index}?sec=loans&id=${widget.id}');
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<LoansBloc, LoansState>(
          listener: (context, state) {
            if (state.status == LoansStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            } else if (state.status == LoansStatus.selected) {
              final userLoanView =
                  context.read<LoansBloc>().selectedUserLoanView;
              context.read<ProductBloc>().selectProduct(
                    userLoanView.productId,
                    forLoans: true,
                  );
            } else if (state.status == LoansStatus.success) {
              if (state.message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(state.message!)));
              }
            }
          },
        ),
        BlocListener<ProductBloc, ProductState>(
          listener: (context, state) {
            if (state.status == ProductStatus.loading) {
              if (state.isLoading) {
                AppWidgets.showDefaultLoadingDialog(context);
              } else {
                Navigator.of(context, rootNavigator: true).pop();
              }
            }
          },
        ),
      ],
      child: widget.fullScreen ? _bodyFullScreen(context) : _body(context),
    );
  }

  Widget _bodyFullScreen(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final userLoanView = widget.userLoanView ??
            context.read<LoansBloc>().selectedUserLoanView;
        final loan = context.read<LoansBloc>().selectedLoan;
        final schedules = context.read<LoansBloc>().clientLoanSchedules;
        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: BlocBuilder<ProductBloc, ProductState>(
              buildWhen: (prev, next) {
                return next.status == ProductStatus.loanSelected;
              },
              builder: (context, state) {
                if (state.status != ProductStatus.loanSelected) {
                  return Container();
                }

                final productView = context.read<ProductBloc>().tempProductView;
                final companyProfileUrl = productView.companyProfilePhotoUrl;

                return Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.32),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.white,
                    backgroundImage: companyProfileUrl != null
                        ? CachedNetworkImageProvider(companyProfileUrl.url)
                        : null,
                    child: companyProfileUrl == null
                        ? Text(
                            userLoanView.companyName.initials(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                );
              },
            ),
            title: Text(
              userLoanView.companyName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () {
                    GoRouter.of(context).goSafe('${Paths.index}?sec=loans');
                  },
                  child: SvgPicture.asset(
                    'svg/close.svg'.assetSafe,
                    colorFilter: const ColorFilter.mode(
                      AppColors.black,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView.separated(
              itemBuilder: (context, index) {
                return switch (index) {
                  0 => Text(
                      userLoanView.loanType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  1 => _nextPayment(
                      fullScreen: true,
                    ),
                  2 => loan.status == LoanStatus.completed
                      ? SizedBox(
                          width: double.infinity,
                          child: AppWidgets.defaultOutlinedButton(
                            child: const Text(
                              'Review',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onPressed: () {
                              _reviewDialog(
                                context,
                                companyName: userLoanView.companyName,
                              );
                            },
                          ),
                        )
                      : Container(),
                  3 => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _reasonForLoan(reason: loan.reason),
                        ),
                        Expanded(
                          child: QuotationWidget(
                            loanAmount: loan.amount,
                            period: loan.period,
                            interestRate: loan.interestRate,
                          ),
                        ),
                      ],
                    ),
                  4 => const Text(
                      'Loan schedule',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  _ => LoanScheduleWidget.scheduleItem(
                      context,
                      schedule: schedules[index - 5],
                      index: index - 5,
                    ),
                };
              },
              separatorBuilder: (context, index) {
                return switch (index) {
                  0 => const Gap(16),
                  _ => const Gap(16),
                };
              },
              itemCount: schedules.length + 5,
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final userLoanView = widget.userLoanView ??
            context.read<LoansBloc>().selectedUserLoanView;
        final loan = context.read<LoansBloc>().selectedLoan;
        final schedules = context.read<LoansBloc>().clientLoanSchedules;
        // The whole panel scrolls; the schedule table is sized to its content
        // (48px per row including the header) so a long schedule extends the
        // scroll instead of being squeezed by the fixed top section.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userLoanView.loanType,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _reasonForLoan(reason: loan.reason),
                  const Gap(24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 286),
                    // QuotationWidget is the direct child here (no Expanded): an
                    // Expanded would write FlexParentData to a child whose parent
                    // is this ConstrainedBox (not a Flex) — a no-op in debug but a
                    // "ParentData is not a subtype of FlexParentData" crash in
                    // release/profile that blanks the whole panel.
                    child: QuotationWidget(
                      loanAmount: loan.amount,
                      period: loan.period,
                      interestRate: loan.interestRate,
                    ),
                  ),
                  const Gap(24),
                  Expanded(
                    child: Column(
                      children: [
                        _nextPayment(
                          fullScreen: true,
                        ),
                        if (loan.status == LoanStatus.completed) ...[
                          const Gap(16),
                          SizedBox(
                            width: double.infinity,
                            child: AppWidgets.defaultOutlinedButton(
                              child: const Text(
                                'Review',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onPressed: () {
                                _reviewDialog(
                                  context,
                                  companyName: userLoanView.companyName,
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(16),
              LoanScheduleWidget(
                // The per-period amortization (e.g. ₱40.92), NOT loan.amount
                // (the principal) — otherwise the "You need to pay X every
                // month" line shows the wrong figure.
                amortization: context.read<LoansBloc>().monthlyAmortization,
                schedules: schedules,
                completeTerm: loan.completeTerm,
                buildTable: true,
                tableHeight: (schedules.length + 1) * 48.0,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _reasonForLoan({required String reason}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reason for loan',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(16),
        Text(
          reason,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _nextPayment({
    bool fullScreen = false,
  }) {
    final userLoanView =
        widget.userLoanView ?? context.read<LoansBloc>().selectedUserLoanView;
    final loan = context.read<LoansBloc>().selectedLoan;
    final schedules = context.read<LoansBloc>().clientLoanSchedules;

    final unpaid = schedules
        .where(
          (s) =>
              s.status != LoanStatus.paid_on_time &&
              s.status != LoanStatus.paid_late &&
              s.status != LoanStatus.payment_submitted,
        )
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final nextDue = unpaid.isNotEmpty ? unpaid.first : null;
    // The lender side collects amortization + any extraPayment.
    final nextDueAmount =
        nextDue == null ? 0.0 : nextDue.amortization + nextDue.extraPayment;
    final remainingTotal = unpaid.fold<double>(
      0,
      (sum, s) => sum + s.amortization + s.extraPayment,
    );

    // Nothing left to pay (or the loan has completed) — show a "fully paid"
    // panel instead of the Pay now / Pay in full buttons, which would otherwise
    // invite payment on a zero-balance loan.
    if (unpaid.isEmpty || loan.status == LoanStatus.completed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: !fullScreen
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: const [
            Row(
              children: [
                Text(
                  'Next payment',
                  style: TextStyle(
                    color: AppColors.green1,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Gap(16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.green1, size: 18),
                Gap(8),
                Text(
                  'Loan fully paid',
                  style: TextStyle(
                    color: AppColors.green1,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            !fullScreen ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          const Row(
            children: [
              Text(
                'Next payment',
                style: TextStyle(
                  color: AppColors.green1,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Gap(16),
          Text(
            (nextDue?.dueAt ?? DateTime.now()).toDefaultDateFormatWithDay(),
            style: const TextStyle(
              color: AppColors.green1,
              fontSize: 12,
            ),
          ),
          const Gap(8),
          Text(
            nextDueAmount.toCurrency(),
            style: const TextStyle(
              color: AppColors.green1,
              fontSize: 12,
            ),
          ),
          const Gap(16),
          SizedBox(
            width: !fullScreen ? null : double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: const Text('Pay now'),
              backgroundColor: AppColors.green1,
              foregroundColor: AppColors.black,
              onPressed: () {
                if (nextDue == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No upcoming payment')),
                  );
                  return;
                }
                showSubmitPaymentDialog(
                  context,
                  schedules: [nextDue],
                  loanId: loan.id,
                  companyId: userLoanView.companyId,
                  amount: nextDueAmount,
                );
              },
            ),
          ),
          const Gap(16),
          SizedBox(
            width: !fullScreen ? null : double.infinity,
            child: AppWidgets.defaultOutlinedButton(
              child: const Text('Pay in full'),
              foregroundColor: AppColors.green1,
              onPressed: () {
                if (unpaid.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No upcoming payment')),
                  );
                  return;
                }
                showSubmitPaymentDialog(
                  context,
                  schedules: unpaid,
                  loanId: loan.id,
                  companyId: userLoanView.companyId,
                  amount: remainingTotal,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _reviewDialog(BuildContext context, {required String companyName}) {
    showDialog(
      context: context,
      builder: (context) {
        final formKey =
            GlobalKey<FormBuilderState>(debugLabel: 'review_dialog');
        return AlertDialog(
          title: const Text(
            'Write a review',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          content: FormBuilder(
            key: formKey,
            child: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FormBuilderField<double>(
                    initialValue: 5,
                    builder: (state) {
                      return AppWidgets.defaultRatingBar(
                        onRatingUpdate: (rating) {
                          state.didChange(rating);
                        },
                      );
                    },
                    name: 'rating',
                    validator: FormBuilderValidators.required(),
                  ),
                  const Gap(16),
                  AppWidgets.defaultFormBuilderTextField(
                    name: 'review',
                    label: 'Tell us what you think',
                    hintText:
                        'How did $companyName helped you in your financial situation? How was the service?',
                    maxLines: 5,
                    validator: FormBuilderValidators.required(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text('Send'),
                onPressed: () {
                  try {
                    final selectedProductView =
                        context.read<ProductBloc>().tempProductView;
                    if (formKey.currentState?.saveAndValidate() ?? false) {
                      final values = formKey.currentState!.value;
                      context.read<LoansBloc>().addReview(
                            review: values['review'] as String,
                            rating: (values['rating'] as double).toInt(),
                            productView: selectedProductView,
                          );
                      Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop();
                    }
                  } catch (err) {
                    // NOTE: possible error is the tempProductView creation
                    var message = 'Cannot add review';
                    if (err is Exception) {
                      message = '$message: $err';
                    }

                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(message)));
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop();
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
