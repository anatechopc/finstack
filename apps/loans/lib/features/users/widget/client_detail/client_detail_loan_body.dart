import 'package:company_repository/company_repository.dart';
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
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:payment_repository/payment_repository.dart';

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
                onConfirmPayment: (schedule) =>
                    _onConfirmPayment(context, schedule),
                onRejectPayment: (schedule) =>
                    _onRejectPayment(context, schedule),
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

  /// Whether the current lender user may confirm/reject borrower submissions.
  /// Mirrors the gating used by the Payment Center (self-managed company,
  /// admin or teller).
  bool _canManageSubmissions() {
    final company = AuthenticationService.instance.company;
    final user = AuthenticationService.instance.user;
    return company.managementType == CompanyManagementType.selfManaged &&
        (user.isAdmin() || user.isTeller());
  }

  PaymentConfirmationService _buildConfirmationService(BuildContext context) {
    return PaymentConfirmationService(
      loanScheduleRepository: context.read<LoanScheduleRepository>(),
      loanRepository: context.read<LoanRepository>(),
      paymentRepository: context.read<PaymentRepository>(),
    );
  }

  /// Re-selects the currently selected loan so the schedule table reflects the
  /// updated payment state. Reuses [LoansBloc.selectLoan] (SelectLoanEvent),
  /// which is the same path the modal uses to load a loan.
  void _refreshSelectedLoan(BuildContext context) {
    final loansBloc = context.read<LoansBloc>();
    loansBloc.selectLoan(
      loansBloc.selectedLoan.id,
      userLoanView: loansBloc.selectedUserLoanView,
    );
  }

  Future<void> _onConfirmPayment(
    BuildContext context,
    LoanSchedule schedule,
  ) async {
    if (!_canManageSubmissions()) {
      debugPrint('User is not allowed to confirm payment submissions');
      return;
    }

    final paymentId = schedule.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      debugPrint('Cannot confirm payment: schedule has no paymentId');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final service = _buildConfirmationService(context);
    final paymentRepository = context.read<PaymentRepository>();

    try {
      final payment = await paymentRepository.get(id: paymentId);
      await service.confirm(
        payment: payment,
        confirmedById: AuthenticationService.instance.user.id,
      );

      if (!context.mounted) return;
      _refreshSelectedLoan(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Payment confirmed')),
      );
    } catch (err) {
      debugPrint('Confirm payment error: $err');
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to confirm payment')),
      );
    }
  }

  Future<void> _onRejectPayment(
    BuildContext context,
    LoanSchedule schedule,
  ) async {
    if (!_canManageSubmissions()) {
      debugPrint('User is not allowed to reject payment submissions');
      return;
    }

    final paymentId = schedule.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      debugPrint('Cannot reject payment: schedule has no paymentId');
      return;
    }

    final reason = await _showRejectReasonDialog(context);
    if (reason == null || reason.trim().isEmpty) return;

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = _buildConfirmationService(context);
    final paymentRepository = context.read<PaymentRepository>();

    try {
      final payment = await paymentRepository.get(id: paymentId);
      await service.reject(
        payment: payment,
        confirmedById: AuthenticationService.instance.user.id,
        reason: reason.trim(),
      );

      if (!context.mounted) return;
      _refreshSelectedLoan(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Payment rejected')),
      );
    } catch (err) {
      debugPrint('Reject payment error: $err');
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to reject payment')),
      );
    }
  }

  /// Mirrors the Payment Center's reject reason dialog
  /// (`pending_submission_section.dart`) for consistency.
  Future<String?> _showRejectReasonDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reject submission'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Why is this submission being rejected?',
            ),
          ),
          actions: [
            AppWidgets.defaultFilledButton(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true)
                    .pop(controller.text);
              },
              child: const Text('Reject'),
            ),
            AppWidgets.defaultOutlinedButton(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
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
