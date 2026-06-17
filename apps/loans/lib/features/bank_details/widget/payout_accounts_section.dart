import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/bank_details/bloc/bank_details_bloc.dart';
import 'package:loooans/features/bank_details/widget/bank_details_form_dialog.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// Lender-facing "Payout accounts" section for the Settings screen. Lists the
/// company's payout accounts with add / edit / delete. Creates its own
/// [BankDetailsBloc] and loads on build.
class PayoutAccountsSection extends StatelessWidget {
  const PayoutAccountsSection({this.createBloc, super.key});

  /// Test seam. Production omits this and gets a real bloc wired to DI.
  final BankDetailsBloc Function(BuildContext)? createBloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) =>
          (createBloc ?? BankDetailsBloc.new)(ctx)..add(LoadBankDetailsEvent()),
      child: const _PayoutAccountsBody(),
    );
  }
}

class _PayoutAccountsBody extends StatelessWidget {
  const _PayoutAccountsBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payout accounts',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const Gap(8),
        BlocBuilder<BankDetailsBloc, BankDetailsState>(
          builder: (context, state) {
            final isBusy = state.status == BankDetailsStatus.loading ||
                state.status == BankDetailsStatus.saving;

            if (isBusy && state.accounts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            if (state.accounts.isEmpty) {
              return const Text(
                'No payout accounts yet. Add one so borrowers know where '
                'to pay.',
                style: TextStyle(color: Colors.black),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.accounts.length,
              separatorBuilder: (_, __) => const Gap(4),
              itemBuilder: (context, index) {
                final account = state.accounts[index];
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${account.bankName} · ${account.accountName} · '
                        '${account.accountNumber}',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () => _onEdit(context, account),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Delete',
                      onPressed: () => _onDelete(context, account),
                    ),
                  ],
                );
              },
            );
          },
        ),
        const Gap(8),
        AppWidgets.defaultOutlinedButton(
          onPressed: () => _onAdd(context),
          child: const Text('+ Add account'),
        ),
      ],
    );
  }

  Future<void> _onAdd(BuildContext context) async {
    final bloc = context.read<BankDetailsBloc>();
    final result = await showBankDetailsFormDialog(context);
    if (result == null) return;
    if (!context.mounted) return;
    bloc.add(
      AddBankDetailsEvent(
        bankName: result.bankName,
        accountName: result.accountName,
        accountNumber: result.accountNumber,
      ),
    );
  }

  Future<void> _onEdit(BuildContext context, BankDetails account) async {
    final bloc = context.read<BankDetailsBloc>();
    final result = await showBankDetailsFormDialog(context, existing: account);
    if (result == null) return;
    if (!context.mounted) return;
    // Build a NEW object (preserving id/dataId/dataType/timestamps) rather than
    // mutating the one held in bloc state — so a failed update doesn't leave the
    // displayed list showing the edited-but-unsaved values.
    final updated = BankDetails()
      ..id = account.id
      ..dataId = account.dataId
      ..dataType = account.dataType
      ..createdAt = account.createdAt
      ..updatedAt = account.updatedAt
      ..bankName = result.bankName
      ..accountName = result.accountName
      ..accountNumber = result.accountNumber;
    bloc.add(UpdateBankDetailsEvent(bankDetails: updated));
  }

  Future<void> _onDelete(BuildContext context, BankDetails account) async {
    final bloc = context.read<BankDetailsBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete payout account'),
        content: Text(
          'Remove ${account.bankName} · ${account.accountName} · '
          '${account.accountNumber}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    bloc.add(DeleteBankDetailsEvent(bankDetails: account));
  }
}
