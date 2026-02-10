import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/bloc/product_status.dart';
import 'package:loooans/features/products/widget/quotation_widget.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_basic_info.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_co_makers_info.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_dialogs.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_reason_for_loan.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_schedule_item.dart';
import 'package:loooans/features/users/widget/client_detail/client_detail_submitted_files.dart';

class ClientDetailLoanBody extends StatelessWidget {
  const ClientDetailLoanBody({
    required this.isCompactOrMedium,
    required this.userId,
    super.key,
  });

  final bool isCompactOrMedium;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final loansBloc = context.read<LoansBloc>();
        final selectedLoan = loansBloc.selectedLoan;
        final clientLoanSchedules = loansBloc.clientLoanSchedules;
        const additionalPosition = 0;

        var basicLoanInfo = _buildDesktopLoanInfo(
          context,
          selectedLoan: selectedLoan,
        );

        var basicPersonalInfo = _buildDesktopPersonalInfo(
          context,
          selectedLoan: selectedLoan,
        );

        if (isCompactOrMedium) {
          basicLoanInfo = _buildCompactLoanInfo(
            context,
            selectedLoan: selectedLoan,
          );
          basicPersonalInfo = _buildCompactPersonalInfo(
            context,
            selectedLoan: selectedLoan,
          );
        }

        return ListView.builder(
          itemBuilder: (context, index) {
            if (index == 0) {
              return basicPersonalInfo;
            } else if (index == 1) {
              return basicLoanInfo;
            } else if (index == 2) {
              return const Text(
                'Loan schedule',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              );
            } else if (index == 3) {
              // headers
              return ClientDetailScheduleItem(
                index: 0,
                schedule: clientLoanSchedules.first,
                isHeader: true,
                onMakePayment: (schedule) =>
                    _onMakePayment(context, schedule),
              );
            } else {
              final finalIndex = index - (4 + additionalPosition);
              final schedule = clientLoanSchedules[finalIndex];
              return ClientDetailScheduleItem(
                index: finalIndex,
                schedule: schedule,
                onMakePayment: (schedule) =>
                    _onMakePayment(context, schedule),
              );
            }
          },
          itemCount: 4 +
              additionalPosition +
              context.read<LoansBloc>().clientLoanSchedules.length,
        );
      },
    );
  }

  void _onMakePayment(BuildContext context, LoanSchedule schedule) {
    showMakePaymentDialog(
      context,
      schedule: schedule,
      userId: userId,
    );
  }

  Widget _buildDesktopLoanInfo(
    BuildContext context, {
    required Loan selectedLoan,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClientDetailReasonForLoan(
                reason: selectedLoan.reason,
              ),
            ),
            const Gap(16),
            const Expanded(child: ClientDetailSubmittedFiles()),
            const Gap(16),
            Expanded(
              flex: 2,
              child: BlocBuilder<ProductBloc, ProductState>(
                buildWhen: (prev, next) {
                  return next.status == ProductStatus.loanSelected;
                },
                builder: (context, state) {
                  if (state.status != ProductStatus.loanSelected) {
                    return Container();
                  }

                  return QuotationWidget(
                    loanAmount: selectedLoan.amount,
                    period: selectedLoan.period,
                    interestRate: selectedLoan.interestRate,
                  );
                },
              ),
            ),
          ],
        ),
        const Gap(24),
      ],
    );
  }

  Widget _buildCompactLoanInfo(
    BuildContext context, {
    required Loan selectedLoan,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ClientDetailSubmittedFiles(),
              const Gap(16),
              ClientDetailReasonForLoan(
                reason: selectedLoan.reason,
              ),
            ],
          ),
        ),
        const Gap(16),
        Expanded(
          child: BlocBuilder<ProductBloc, ProductState>(
            buildWhen: (prev, next) {
              return next.status == ProductStatus.loanSelected;
            },
            builder: (context, state) {
              if (state.status != ProductStatus.loanSelected) {
                return Container();
              }

              return QuotationWidget(
                loanAmount: selectedLoan.amount,
                period: selectedLoan.period,
                interestRate: selectedLoan.interestRate,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopPersonalInfo(
    BuildContext context, {
    required Loan selectedLoan,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: ClientDetailBasicInfo(),
            ),
            if (selectedLoan.coMakerUserIds.isNotEmpty) ...[
              const Gap(24),
              const Expanded(
                child: ClientDetailCoMakersInfo(),
              ),
            ],
          ],
        ),
        const Gap(24),
      ],
    );
  }

  Widget _buildCompactPersonalInfo(
    BuildContext context, {
    required Loan selectedLoan,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ClientDetailBasicInfo(),
        const Gap(24),
        if (selectedLoan.coMakerUserIds.isNotEmpty) ...[
          const ClientDetailCoMakersInfo(),
          const Gap(24),
        ],
      ],
    );
  }
}
